import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/song_model.dart';
import '../../services/album_art_service.dart';
import 'app_providers.dart';

// ─── Album Art State ─────────────────────────────────────────────────────────

/// Holds the resolved artwork and dynamic colors for the currently playing song.
class AlbumArtState {
  final Uint8List? artBytes;
  final Color dominantColor;
  final List<Color> gradientColors;
  final Uri? artUri;
  final bool isLoading;

  const AlbumArtState({
    this.artBytes,
    required this.dominantColor,
    required this.gradientColors,
    this.artUri,
    this.isLoading = false,
  });

  factory AlbumArtState.loading() => const AlbumArtState(
        dominantColor: AlbumArtService.kFallbackColor,
        gradientColors: AlbumArtService.kFallbackGradient,
        isLoading: true,
      );

  factory AlbumArtState.fromResult(AlbumArtResult result) => AlbumArtState(
        artBytes: result.artBytes,
        dominantColor: result.dominantColor,
        gradientColors: result.gradientColors,
        artUri: result.artUri,
      );

  factory AlbumArtState.fallback() => const AlbumArtState(
        dominantColor: AlbumArtService.kFallbackColor,
        gradientColors: AlbumArtService.kFallbackGradient,
      );
}

// ─── Album Art Notifier ───────────────────────────────────────────────────────

/// Watches [playerProvider] and re-processes artwork whenever the current song
/// changes. Debounced to 150 ms so rapid skips don't hammer palette_generator.
class AlbumArtNotifier extends Notifier<AlbumArtState> {
  int? _lastProcessedSongId;
  bool _processing = false;

  @override
  AlbumArtState build() {
    // React to song changes without blocking the build method
    ref.listen<PlayerState>(playerProvider, (prev, next) {
      final newSong = next.currentSong;
      final oldSong = prev?.currentSong;
      if (newSong?.id != oldSong?.id) {
        _onSongChanged(newSong);
      }
    });

    // Also process on initial build if a song is already playing
    final currentSong = ref.read(playerProvider).currentSong;
    if (currentSong != null) {
      Future.microtask(() => _onSongChanged(currentSong));
    }

    return AlbumArtState.fallback();
  }

  Future<void> _onSongChanged(SongModel? song) async {
    if (song == null) {
      state = AlbumArtState.fallback();
      _lastProcessedSongId = null;
      return;
    }

    // Deduplicate: skip if same song is already processed/processing
    if (song.id == _lastProcessedSongId && !_processing) return;

    _processing = true;
    _lastProcessedSongId = song.id;

    // Only show loading flash when bytes aren't cached yet.
    // If already cached, go straight to processing so that PlayerScreen's
    // initState postFrameCallback reads a fully-resolved state (not isLoading).
    final isCached = AlbumArtService.instance.isBytesCached(song.id);
    if (!isCached) state = AlbumArtState.loading();

    try {
      final service = AlbumArtService.instance;
      final datasource = ref.read(musicLocalDatasourceProvider);
      final result = await service.process(song.id, datasource);

      // Only apply if song hasn't changed during the async gap
      if (song.id == _lastProcessedSongId) {
        state = AlbumArtState.fromResult(result);
      }
    } catch (_) {
      if (song.id == _lastProcessedSongId) {
        state = AlbumArtState.fallback();
      }
    } finally {
      _processing = false;
    }
  }

  /// Force-refresh artwork for the current song (e.g. after scan).
  void refresh() {
    _lastProcessedSongId = null;
    final song = ref.read(playerProvider).currentSong;
    if (song != null) _onSongChanged(song);
  }
}

final albumArtProvider =
    NotifierProvider<AlbumArtNotifier, AlbumArtState>(AlbumArtNotifier.new);
