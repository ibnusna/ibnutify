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

  /// Hapus semua in-memory cache untuk [songId].
  /// Dipanggil setelah metadata (termasuk albumArtPath) diubah oleh user.
  void evictSong(int songId) {
    _bytesCache.remove(songId);
    _colorCache.remove(songId);
    _pathCache.remove(songId);
  }

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
      );

      // Priority: darkMuted → darkVibrant → muted → dominant → fallback
      final raw = palette.darkMutedColor?.color ??
          palette.darkVibrantColor?.color ??
          palette.mutedColor?.color ??
          palette.dominantColor?.color ??
          kFallbackColor;

      final color = _clampToVibrant(raw);
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
  /// Returns [AlbumArtResult] with vibrant 2-3 color palette needed by Player Screen UI.
  Future<AlbumArtResult> process(
    int songId,
    MusicLocalDatasource datasource,
  ) async {
    final bytes = await getArtworkBytes(songId, datasource);
    if (bytes == null) {
      return AlbumArtResult.fallback();
    }

    Color primaryColor = kFallbackColor;
    Color secondaryColor = kFallbackColor;
    Color darkColor = const Color(0xFF181818);

    try {
      final palette = await PaletteGenerator.fromImageProvider(
        MemoryImage(bytes),
        maximumColorCount: 24,
      );

      // Spotify priority: vibrant → lightVibrant → dominant → darkMuted
      final c1 = palette.vibrantColor?.color ??
          palette.lightVibrantColor?.color ??
          palette.dominantColor?.color ??
          palette.darkVibrantColor?.color ??
          kFallbackColor;

      final c2 = palette.lightVibrantColor?.color ??
          palette.mutedColor?.color ??
          palette.darkMutedColor?.color ??
          c1;

      primaryColor = _clampToVibrant(c1);
      secondaryColor = _clampToVibrant(c2);

      final primaryHsl = HSLColor.fromColor(primaryColor);
      darkColor = primaryHsl.withLightness((primaryHsl.lightness * 0.35).clamp(0.08, 0.22)).toColor();
      _colorCache[songId] = primaryColor;
    } catch (_) {
      primaryColor = kFallbackColor;
      secondaryColor = kFallbackColor;
    }

    final path = await saveArtworkToTemp(bytes, songId);

    return AlbumArtResult(
      artBytes: bytes,
      dominantColor: primaryColor,
      gradientColors: [
        primaryColor,
        secondaryColor.withOpacity(0.75),
        darkColor,
      ],
      artUri: path != null ? Uri.file(path) : null,
    );
  }

  // ─── Private helpers ─────────────────────────────────────────────────────

  /// Ensure color is vibrant and rich for player background without over-darkening.
  Color _clampToVibrant(Color color) {
    final hsl = HSLColor.fromColor(color);
    double targetLightness = hsl.lightness;
    if (targetLightness < 0.28) targetLightness = 0.34;
    if (targetLightness > 0.55) targetLightness = 0.48;

    double targetSaturation = (hsl.saturation * 1.1).clamp(0.35, 0.95);
    return hsl.withLightness(targetLightness).withSaturation(targetSaturation).toColor();
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
