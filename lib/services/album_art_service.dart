import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:path_provider/path_provider.dart';
import '../data/datasources/music_local_datasource.dart';

/// Service that handles:
/// 1. Fetching artwork bytes from on_audio_query (with in-memory LRU cache)
/// 2. Extracting dominant color via palette_generator (Spotify dark-clamped)
/// 3. Saving artwork to a temp file so MediaItem.artUri works for notifications
///
/// This is intentionally a plain Dart class (no Riverpod) so it can be used
/// both from providers and from the AudioHandler without circular deps.
class AlbumArtService {
  AlbumArtService._();
  static final AlbumArtService instance = AlbumArtService._();

  // ─── In-memory caches ────────────────────────────────────────────────────

  /// Raw JPEG bytes keyed by song ID (max 60 entries LRU)
  final Map<int, Uint8List> _bytesCache = {};

  /// Dominant Color keyed by song ID
  final Map<int, Color> _colorCache = {};

  /// Temp file path keyed by song ID
  final Map<int, String> _pathCache = {};

  static const int _maxCacheSize = 60;

  // Spotify-style fallback dark green when no art is available
  static const Color kFallbackColor = Color(0xFF1A3A2A);
  static const List<Color> kFallbackGradient = [
    Color(0xFF1A3A2A),
    Color(0xFF121212),
  ];

  // ─── Public API ──────────────────────────────────────────────────────────

  /// Returns true if artwork bytes for [songId] are already in memory cache.
  /// Used to decide whether to show a loading flash before processing.
  bool isBytesCached(int songId) => _bytesCache.containsKey(songId);

  /// Returns cached artwork bytes for [songId], or queries native if missing.
  Future<Uint8List?> getArtworkBytes(
    int songId,
    MusicLocalDatasource datasource,
  ) async {
    if (_bytesCache.containsKey(songId)) return _bytesCache[songId];

    try {
      final list = await datasource.queryArtwork(songId);
      if (list == null || list.isEmpty) return null;
      final bytes = Uint8List.fromList(list);
      _evictIfNeeded(_bytesCache);
      _bytesCache[songId] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  /// Returns the dominant dark color extracted from [bytes].
  /// Auto-darkens if luminance > 0.35 to keep notification background readable.
  Future<Color> extractDominantColor(Uint8List bytes, int songId) async {
    if (_colorCache.containsKey(songId)) return _colorCache[songId]!;

    try {
      final palette = await PaletteGenerator.fromImageProvider(
        MemoryImage(bytes),
        maximumColorCount: 20,
        // Downsample to 100px for performance — we only need color, not detail
        size: const Size(100, 100),
      );

      // Priority: darkMuted → darkVibrant → muted → dominant → fallback
      final raw = palette.darkMutedColor?.color ??
          palette.darkVibrantColor?.color ??
          palette.mutedColor?.color ??
          palette.dominantColor?.color ??
          kFallbackColor;

      final color = _clampToDark(raw);
      _colorCache[songId] = color;
      return color;
    } catch (_) {
      return kFallbackColor;
    }
  }

  /// Saves [bytes] to a temp file and returns the file path.
  /// Android MediaSession uses this URI to display art in notifications
  /// and on the lockscreen.
  Future<String?> saveArtworkToTemp(Uint8List bytes, int songId) async {
    if (_pathCache.containsKey(songId)) {
      // Verify still exists (temp dir can be cleared by OS)
      final existing = File(_pathCache[songId]!);
      if (await existing.exists()) return _pathCache[songId];
    }

    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/ibnutify_art_$songId.jpg');
      await file.writeAsBytes(bytes, flush: true);
      _pathCache[songId] = file.path;
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// Convenience method: fetch bytes + save to temp + return Uri.
  /// Returns null if no artwork is available.
  Future<Uri?> getArtworkUri(
    int songId,
    MusicLocalDatasource datasource,
  ) async {
    final bytes = await getArtworkBytes(songId, datasource);
    if (bytes == null) return null;
    final path = await saveArtworkToTemp(bytes, songId);
    if (path == null) return null;
    return Uri.file(path);
  }

  /// Full pipeline: bytes + dominant color + gradient.
  /// Returns [AlbumArtResult] with everything needed by the UI.
  Future<AlbumArtResult> process(
    int songId,
    MusicLocalDatasource datasource,
  ) async {
    final bytes = await getArtworkBytes(songId, datasource);
    if (bytes == null) {
      return AlbumArtResult.fallback();
    }

    final color = await extractDominantColor(bytes, songId);
    final path = await saveArtworkToTemp(bytes, songId);

    return AlbumArtResult(
      artBytes: bytes,
      dominantColor: color,
      gradientColors: [
        color.withOpacity(0.90),
        color.withOpacity(0.50),
        const Color(0xFF121212),
      ],
      artUri: path != null ? Uri.file(path) : null,
    );
  }

  // ─── Private helpers ─────────────────────────────────────────────────────

  /// Clamp raw color luminance to ≤ 0.32 for readable dark backgrounds.
  Color _clampToDark(Color color) {
    final hsl = HSLColor.fromColor(color);
    if (hsl.lightness <= 0.32) return color;
    return hsl.withLightness(0.22).withSaturation(
      (hsl.saturation * 0.85).clamp(0.0, 1.0),
    ).toColor();
  }

  /// Simple LRU eviction: remove oldest entry when over capacity.
  void _evictIfNeeded(Map<int, dynamic> cache) {
    if (cache.length >= _maxCacheSize) {
      cache.remove(cache.keys.first);
    }
  }
}

/// Immutable result from [AlbumArtService.process].
class AlbumArtResult {
  final Uint8List? artBytes;
  final Color dominantColor;
  final List<Color> gradientColors;
  final Uri? artUri;

  const AlbumArtResult({
    required this.artBytes,
    required this.dominantColor,
    required this.gradientColors,
    required this.artUri,
  });

  factory AlbumArtResult.fallback() => const AlbumArtResult(
        artBytes: null,
        dominantColor: AlbumArtService.kFallbackColor,
        gradientColors: AlbumArtService.kFallbackGradient,
        artUri: null,
      );
}
