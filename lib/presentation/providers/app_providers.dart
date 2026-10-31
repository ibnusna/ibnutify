import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ibnutify/data/datasources/database_helper.dart';
import 'package:ibnutify/data/datasources/music_local_datasource.dart';
import 'package:ibnutify/data/datasources/gemini_datasource.dart';
import 'package:ibnutify/data/repositories/music_repository.dart';
import 'package:ibnutify/data/models/song_model.dart';
import 'package:ibnutify/data/models/playlist_model.dart';
import 'package:ibnutify/data/models/activity_model.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ibnutify/services/audio_handler.dart';
import 'package:ibnutify/services/album_art_service.dart';
import 'package:ibnutify/services/location_service.dart';
import 'package:ibnutify/services/health_connect_service.dart';
import 'package:ibnutify/services/ml_service.dart';
import 'package:ibnutify/services/download_service.dart';
import 'package:ibnutify/services/smart_shuffle_service.dart';
import 'package:ibnutify/services/workout_task_handler.dart';
import 'package:ibnutify/services/sensor_fusion_engine.dart';
import 'package:ibnutify/services/watch_service.dart';
import 'package:ibnutify/services/chat_history_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Infrastructure Providers ─────────────────────────────────────────────

final audioHandlerProvider = Provider<IbnuTifyAudioHandler>((ref) {
  throw UnimplementedError('Override in main with actual instance');
});

final musicLocalDatasourceProvider = Provider<MusicLocalDatasource>((ref) {
  return MusicLocalDatasource();
});

final geminiDatasourceProvider = Provider<GeminiDatasource>((ref) {
  final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
  return GeminiDatasource(apiKey: apiKey);
});

final musicRepositoryProvider = Provider<MusicRepository>((ref) {
  return MusicRepository(
    local: ref.watch(musicLocalDatasourceProvider),
    gemini: ref.watch(geminiDatasourceProvider),
  );
});

final mlServiceProvider = Provider<MLService>((ref) {
  return MLService(ref.watch(musicRepositoryProvider));
});

final mlProgressProvider = StateProvider<String?>((ref) => null);

// ─── Songs State ──────────────────────────────────────────────────────────

class SongsNotifier extends AsyncNotifier<List<SongModel>> {
  @override
  Future<List<SongModel>> build() async {
    final repo = ref.watch(musicRepositoryProvider);
    await repo.checkAndPerformScheduledResets();
    final cached = await repo.getAllSongs();

    // Auto incremental scan di background
    Future.microtask(() async {
      try {
        final updated = await repo.scanDeviceSongs();
        if (state.hasValue) {
          final currentIds = state.value!.map((s) => s.id).toSet();
          final newIds = updated.map((s) => s.id).toSet();
          if (!currentIds.containsAll(newIds) || !newIds.containsAll(currentIds)) {
            state = AsyncData(updated);
          }
        }

        // Run background ML feature extraction and clustering
        final ml = ref.read(mlServiceProvider);
        ref.read(mlProgressProvider.notifier).state = "Memulai analisis musik...";
        await ml.processAndClusterSongs(updated, onProgress: (progress) {
          ref.read(mlProgressProvider.notifier).state = progress;
        });
        ref.read(mlProgressProvider.notifier).state = null;
        await refresh();
      } catch (_) {
        ref.read(mlProgressProvider.notifier).state = null;
      }
    });

    return cached;
  }

  Future<void> scanDeviceSongs() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(musicRepositoryProvider);
      final songs = await repo.scanDeviceSongs();

      // Run background ML feature extraction and clustering
      Future.microtask(() async {
        try {
          final ml = ref.read(mlServiceProvider);
          ref.read(mlProgressProvider.notifier).state = "Memulai analisis musik...";
          await ml.processAndClusterSongs(songs, onProgress: (progress) {
            ref.read(mlProgressProvider.notifier).state = progress;
          });
          ref.read(mlProgressProvider.notifier).state = null;
          await refresh();
        } catch (_) {
          ref.read(mlProgressProvider.notifier).state = null;
        }
      });

      return songs;
    });
  }

  Future<void> refresh() async {
    final repo = ref.read(musicRepositoryProvider);
    final updated = await repo.getAllSongs();
    state = AsyncData(updated);
  }

  Future<void> toggleLike(int songId) async {
    final repo = ref.read(musicRepositoryProvider);
    await repo.toggleLike(songId);
    await refresh();
  }

  Future<void> deleteSong(int songId) async {
    final playerNotif = ref.read(playerProvider.notifier);
    final playerState = ref.read(playerProvider);

    // Stop playback or skip if the song being deleted is currently playing
    if (playerState.currentSong?.id == songId) {
      if (playerState.queue.length <= 1) {
        await playerNotif.clearQueue();
      } else {
        await playerNotif.nextTrack();
      }
    }

    // Remove deleted song from live queue
    playerNotif.removeFromQueue(songId);

    final repo = ref.read(musicRepositoryProvider);
    await repo.deleteSong(songId);
    if (state.hasValue) {
      state = AsyncData(state.value!.where((s) => s.id != songId).toList());
    }
    ref.invalidate(duplicateSongsProvider);
    ref.invalidate(recentlyPlayedProvider);
    ref.invalidate(topSongsProvider);
  }

  Future<SongModel> duplicateSong(SongModel song) async {
    final repo = ref.read(musicRepositoryProvider);
    final copy = await repo.duplicateSong(song);
    await refresh();
    ref.invalidate(duplicateSongsProvider);
    return copy;
  }

  /// Update metadata lagu (artist, album, youtubeUrl) yang bisa diedit user.
  /// Setelah update DB, evict art cache, refresh list, dan sync player jika perlu.
  Future<void> updateMetadata(
    int songId, {
    String? artist,
    String? album,
    String? youtubeUrl,
  }) async {
    final repo = ref.read(musicRepositoryProvider);
    await repo.updateSongMetadata(songId,
        artist: artist, album: album, youtubeUrl: youtubeUrl);

    // Bersihkan art cache agar artwork di-reload ulang
    AlbumArtService.instance.evictSong(songId);

    // Refresh state list lagu
    await refresh();

    // Jika lagu yang diedit sedang diputar, sync currentSong di player
    final playerState = ref.read(playerProvider);
    if (playerState.currentSong?.id == songId) {
      ref.read(playerProvider.notifier).syncCurrentSong(songId);
    }
  }
}

final songsProvider =
    AsyncNotifierProvider<SongsNotifier, List<SongModel>>(SongsNotifier.new);

// ─── Player State ──────────────────────────────────────────────────────────

final isVideoModeProvider = StateProvider<bool>((ref) => false);

enum RepeatMode { off, one, all }

class PlayerState {
  final SongModel? currentSong;
  final List<SongModel> queue;
  final bool isPlaying;
  final bool isShuffle;
  final RepeatMode repeatMode;
  final Duration position;
  final Duration duration;
  /// Sumber lagu yang sedang diputar, misal: 'Library', 'Search', 'Playlist: Liked Songs'
  final String? queueSource;

  const PlayerState({
    this.currentSong,
    this.queue = const [],
    this.isPlaying = false,
    this.isShuffle = false,
    this.repeatMode = RepeatMode.off,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.queueSource,
  });

  PlayerState copyWith({
    SongModel? currentSong,
    List<SongModel>? queue,
    bool? isPlaying,
    bool? isShuffle,
    RepeatMode? repeatMode,
    Duration? position,
    Duration? duration,
    String? queueSource,
    bool clearQueueSource = false,
  }) {
    return PlayerState(
      currentSong: currentSong ?? this.currentSong,
      queue: queue ?? this.queue,
      isPlaying: isPlaying ?? this.isPlaying,
      isShuffle: isShuffle ?? this.isShuffle,
      repeatMode: repeatMode ?? this.repeatMode,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      queueSource: clearQueueSource ? null : (queueSource ?? this.queueSource),
    );
  }
}

class PlayerNotifier extends Notifier<PlayerState> {
  int? _trackingId;

  @override
  PlayerState build() {
    final handler = ref.read(audioHandlerProvider);

    handler.positionStream.listen((pos) {
      state = state.copyWith(position: pos);
    });

    handler.durationStream.listen((dur) {
      if (dur != null) {
        state = state.copyWith(duration: dur);
      }
    });

    handler.playbackState.listen((ps) {
      state = state.copyWith(isPlaying: ps.playing);
    });

    handler.mediaItem.listen((item) {
      if (item == null) return;
      final songId = item.extras?['songId'] as int?;
      if (songId == null) return;

      // [FIX-BUG2] Guard sederhana: hanya update currentSong jika songId cocok
      // dengan index aktif di queue player. Ini mencegah ghost-update dari
      // AudioService saat switching lagu atau resume dari background.
      final curIdx = handler.player.currentIndex;
      if (curIdx != null && curIdx < handler.currentQueueItems.length) {
        final activeSongId = handler.currentQueueItems[curIdx].extras?['songId'] as int?;
        if (activeSongId != null && activeSongId != songId) {
          // Abaikan: mediaItem tidak cocok dengan index aktif (stale broadcast)
          return;
        }
      }

      _trackingId = songId;
      _syncCurrentSongFromCache(songId);
      ref.invalidate(recentlyPlayedProvider);
    });

    handler.queue.listen((items) {
      final songsCache = ref.read(songsProvider).value ?? [];
      final updatedQueue = items.map((item) {
        final songId = item.extras?['songId'] as int?;
        return songsCache.where((s) => s.id == songId).firstOrNull;
      }).whereType<SongModel>().toList();
      state = state.copyWith(queue: updatedQueue);
    });

    return const PlayerState();
  }

  void _syncCurrentSongFromCache(int songId) {
    final songsCache = ref.read(songsProvider).value ?? [];
    final found = songsCache.where((s) => s.id == songId).firstOrNull;
    if (found != null) {
      state = state.copyWith(currentSong: found);
    }
  }

  /// Public alias dipakai oleh SongsNotifier setelah updateMetadata().
  void syncCurrentSong(int songId) => _syncCurrentSongFromCache(songId);

  Future<void> playSong(SongModel song, List<SongModel> queue, {String? source, bool skipAutoShuffle = false}) async {
    final handler = ref.read(audioHandlerProvider);
    final repo = ref.read(musicRepositoryProvider);
    final datasource = ref.read(musicLocalDatasourceProvider);

    // Resolve artUri lagu aktif SEBELUM playQueue — notifikasi langsung punya cover.
    final artUri = await AlbumArtService.instance.getArtworkUri(song.id, datasource);

    // [BUG-4 FIX] Auto Smart Shuffle: terapkan Smart Shuffle secara default
    // untuk setiap queue dengan 3+ lagu, kecuali jika queue = 1 lagu saja.
    // skipAutoShuffle=true dipakai oleh playFromSearch() yang sudah punya queue ter-shuffle sendiri.
    List<SongModel> effectiveQueue = queue;
    bool appliedShuffle = false;

    if (!skipAutoShuffle && queue.length >= 3) {
      try {
        final recentLogs = await repo.getListeningHistory24h();
        final shuffledIndices = await SmartShuffleService.computeSmartShuffleIndices(
          queue,
          recentLogs,
          song.id,
        );
        if (shuffledIndices.isNotEmpty) {
          effectiveQueue = shuffledIndices.map((i) => queue[i]).toList();
          appliedShuffle = true;
          debugPrint('[PlayerNotifier] Auto Smart Shuffle applied — ${effectiveQueue.length} songs reordered');
        }
      } catch (e) {
        // Fallback ke queue asli jika Smart Shuffle gagal
        debugPrint('[PlayerNotifier] Smart Shuffle error (using original order): $e');
        effectiveQueue = queue;
      }
    }

    // Bangun queue, patch lagu aktif dengan artUri yang sudah resolved.
    final mediaItems = effectiveQueue.map((s) {
      final item = _toMediaItemSync(s);
      if (s.id == song.id && artUri != null) {
        return item.copyWith(artUri: artUri);
      }
      return item;
    }).toList();

    final index = effectiveQueue.indexWhere((s) => s.id == song.id);
    final safeIndex = index < 0 ? 0 : index;

    await handler.playQueue(mediaItems, initialIndex: safeIndex);

    await repo.incrementPlayCount(song.id);
    _trackingId = song.id;

    state = state.copyWith(
      currentSong: song,
      queue: effectiveQueue,
      queueSource: source ?? 'Library',
      isShuffle: appliedShuffle, // [BUG-4 FIX] Set isShuffle=true jika Smart Shuffle aktif
    );

    // Update artwork sisa queue di background.
    _fetchAndSendArtwork(effectiveQueue, handler);
  }


  Future<void> playFromSearch(SongModel song) async {
    final allSongs = ref.read(songsProvider).value ?? [];
    
    // 1. Separate same artist and other artists
    final sameArtist = allSongs
        .where((s) =>
            s.id != song.id &&
            s.artist.toLowerCase() == song.artist.toLowerCase())
        .toList();
        
    final otherArtists = allSongs
        .where((s) =>
            s.artist.toLowerCase() != song.artist.toLowerCase())
        .toList();

    final repo = ref.read(musicRepositoryProvider);
    final recentLogs = await repo.getListeningHistory24h();

    // 2. Select at most 1 song from same artist
    SongModel? chosenSameArtist;
    if (sameArtist.isNotEmpty) {
      final sameIndices = await SmartShuffleService.computeSmartShuffleIndices(
        sameArtist,
        recentLogs,
        null,
      );
      if (sameIndices.isNotEmpty) {
        chosenSameArtist = sameArtist[sameIndices.first];
      }
    }

    // 3. Compute Smart Shuffle for other artists
    final otherIndices = await SmartShuffleService.computeSmartShuffleIndices(
      otherArtists,
      recentLogs,
      null,
    );
    final sortedOthers = otherIndices.map((idx) => otherArtists[idx]).toList();

    // 4. Build final queue
    final finalQueue = <SongModel>[song];
    if (chosenSameArtist != null) {
      finalQueue.add(chosenSameArtist);
    }
    finalQueue.addAll(sortedOthers);

    // 5. Play queue and enable shuffle mode visually
    // skipAutoShuffle=true karena queue sudah di-shuffle oleh Smart Shuffle di atas
    await playSong(song, finalQueue, source: 'Search', skipAutoShuffle: true);
    state = state.copyWith(isShuffle: true);
  }

  void _fetchAndSendArtwork(
      List<SongModel> songs, IbnuTifyAudioHandler handler) async {
    try {
      final datasource = ref.read(musicLocalDatasourceProvider);
      final artBytesMap = <int, Uint8List>{};

      if (songs.isNotEmpty) {
        final currentSong = songs.first;
        final bytes = await AlbumArtService.instance.getArtworkBytes(
          currentSong.id,
          datasource,
        );
        if (bytes != null) {
          artBytesMap[currentSong.id] = bytes;
          handler.updateArtwork({currentSong.id: bytes});
        }
      }

      final limit = songs.length > 50 ? 50 : songs.length;
      for (final song in songs.skip(1).take(limit - 1)) {
        final bytes = await AlbumArtService.instance.getArtworkBytes(
          song.id,
          datasource,
        );
        if (bytes != null) artBytesMap[song.id] = bytes;
      }

      if (artBytesMap.isNotEmpty) {
        handler.updateArtwork(artBytesMap);
      }
    } catch (_) {}
  }

  Future<void> togglePlay() async {
    final handler = ref.read(audioHandlerProvider);
    if (state.isPlaying) {
      await handler.pause();
    } else {
      // Guard: jika player belum memiliki audio source namun ada currentSong
      if (handler.player.audioSource == null && state.currentSong != null) {
        final songToPlay = state.currentSong!;
        final queueToPlay = state.queue.isNotEmpty ? state.queue : [songToPlay];
        await playSong(songToPlay, queueToPlay, source: state.queueSource);
      } else {
        await handler.play();
      }
    }
  }

  /// [F2-5 FIX] Paksa pause musik — digunakan oleh NoisyReceiver (TWS/Bluetooth disconnect)
  /// agar musik tidak auto-resume lewat speaker saat perangkat audio terputus.
  Future<void> pause() async {
    final handler = ref.read(audioHandlerProvider);
    if (state.isPlaying) {
      await handler.pause();
      state = state.copyWith(isPlaying: false);
    }
  }

  Future<void> nextTrack() async {
    final handler = ref.read(audioHandlerProvider);
    await handler.skipToNext();
    _pushArtworkForCurrentSong(handler);
  }

  Future<void> previousTrack() async {
    final handler = ref.read(audioHandlerProvider);
    await handler.skipToPrevious();
    _pushArtworkForCurrentSong(handler);
  }

  /// Push artwork for the current song to notification after a skip.
  void _pushArtworkForCurrentSong(IbnuTifyAudioHandler handler) async {
    try {
      final songId = _trackingId;
      if (songId == null) return;
      final datasource = ref.read(musicLocalDatasourceProvider);
      final bytes = await AlbumArtService.instance.getArtworkBytes(songId, datasource);
      if (bytes != null) handler.updateArtwork({songId: bytes});
    } catch (_) {}
  }

  Future<void> seek(double percent) async {
    final handler = ref.read(audioHandlerProvider);
    final targetMs = (percent / 100) * state.duration.inMilliseconds;
    await handler.seek(Duration(milliseconds: targetMs.toInt()));
  }

  Future<void> seekToDuration(Duration position) async {
    final handler = ref.read(audioHandlerProvider);
    await handler.seek(position);
  }

  Future<void> toggleShuffle() async {
    final handler = ref.read(audioHandlerProvider);
    final newShuffle = !state.isShuffle;
    
    if (newShuffle && state.queue.isNotEmpty) {
      final repo = ref.read(musicRepositoryProvider);
      final recentLogs = await repo.getListeningHistory24h();
      
      final newIndices = await SmartShuffleService.computeSmartShuffleIndices(
        state.queue,
        recentLogs,
        state.currentSong?.id,
      );
      
      await handler.injectCustomQueue(newIndices);
    } else if (!newShuffle) {
      // Logic for disabling shuffle would involve restoring original queue order if needed.
    }

    final updatedQueueItems = handler.currentQueueItems;
    final allSongs = ref.read(songsProvider).value ?? [];
    final newQueue = updatedQueueItems.map((item) {
      final songId = item.extras?['songId'] as int?;
      return allSongs.where((s) => s.id == songId).firstOrNull;
    }).whereType<SongModel>().toList();

    state = state.copyWith(isShuffle: newShuffle, queue: newQueue);
  }

  Future<void> cycleRepeat() async {
    final handler = ref.read(audioHandlerProvider);
    final next = RepeatMode
        .values[(state.repeatMode.index + 1) % RepeatMode.values.length];
    final serviceMode = switch (next) {
      RepeatMode.off => AudioServiceRepeatMode.none,
      RepeatMode.one => AudioServiceRepeatMode.one,
      RepeatMode.all => AudioServiceRepeatMode.all,
    };
    await handler.setRepeatMode(serviceMode);
    state = state.copyWith(repeatMode: next);
  }

  // ─── [BUG-6 FIX] Last Played Persistence ────────────────────────────────────
  // Kunci SharedPreferences untuk menyimpan state player terakhir

  static const _keyLastSongId = 'player_last_song_id';
  static const _keyLastPositionMs = 'player_last_position_ms';
  static const _keyLastQueueIds = 'player_last_queue_ids';
  static const _keyLastQueueSource = 'player_last_queue_source';

  /// Simpan state player saat ini ke SharedPreferences.
  /// Dipanggil dari MainShell.didChangeAppLifecycleState(paused/detached).
  Future<void> saveLastPlayed() async {
    try {
      final song = state.currentSong;
      if (song == null) return;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyLastSongId, song.id);
      await prefs.setInt(_keyLastPositionMs, state.position.inMilliseconds);
      await prefs.setString(_keyLastQueueSource, state.queueSource ?? 'Library');

      // Simpan queue sebagai JSON list of song IDs (max 200 lagu untuk hemat memori)
      final queueIds = state.queue.take(200).map((s) => s.id).toList();
      await prefs.setString(_keyLastQueueIds, jsonEncode(queueIds));

      debugPrint('[PlayerNotifier] saveLastPlayed: songId=${song.id}, pos=${state.position.inSeconds}s, queueLen=${queueIds.length}');
    } catch (e) {
      debugPrint('[PlayerNotifier] saveLastPlayed error: $e');
    }
  }

  /// Restore state player terakhir dari SharedPreferences.
  /// Dipanggil dari MainShell.initState() setelah frame pertama render.
  Future<void> restoreLastPlayed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSongId = prefs.getInt(_keyLastSongId);

      // Tunggu songsProvider siap (dibaca dari cache/database)
      List<SongModel> allSongs = ref.read(songsProvider).value ?? [];
      if (allSongs.isEmpty) {
        try {
          allSongs = await ref.read(songsProvider.future);
        } catch (_) {}
      }

      SongModel? lastSong;
      if (lastSongId != null) {
        lastSong = allSongs.where((s) => s.id == lastSongId).firstOrNull;
      }

      // Fallback jika tidak ada prefs: ambil dari recently played 24 jam terakhir
      if (lastSong == null) {
        try {
          final repo = ref.read(musicRepositoryProvider);
          final recent = await repo.getRecentlyPlayed24h(limit: 1);
          if (recent.isNotEmpty) {
            lastSong = recent.first;
          }
        } catch (_) {}
      }

      if (lastSong == null) {
        debugPrint('[PlayerNotifier] restoreLastPlayed: tidak ada lagu untuk di-restore');
        return;
      }

      // Rebuild queue dari ID yang tersimpan
      final queueIdsJson = prefs.getString(_keyLastQueueIds);
      List<SongModel> restoredQueue = [lastSong];
      if (queueIdsJson != null && allSongs.isNotEmpty) {
        try {
          final ids = (jsonDecode(queueIdsJson) as List).cast<int>();
          restoredQueue = ids
              .map((id) => allSongs.where((s) => s.id == id).firstOrNull)
              .whereType<SongModel>()
              .toList();
          if (!restoredQueue.any((s) => s.id == lastSong!.id)) {
            restoredQueue = [lastSong, ...restoredQueue];
          }
        } catch (_) {
          restoredQueue = [lastSong];
        }
      }

      final lastPositionMs = prefs.getInt(_keyLastPositionMs) ?? 0;
      final lastQueueSource = prefs.getString(_keyLastQueueSource) ?? 'Library';

      debugPrint('[PlayerNotifier] restoreLastPlayed: restoring "${lastSong.title}" at ${lastPositionMs}ms (${restoredQueue.length} songs in queue)');

      final handler = ref.read(audioHandlerProvider);
      final datasource = ref.read(musicLocalDatasourceProvider);
      final artUri = await AlbumArtService.instance.getArtworkUri(lastSong.id, datasource);

      final mediaItems = restoredQueue.map((s) {
        final item = _toMediaItemSync(s);
        if (s.id == lastSong!.id && artUri != null) {
          return item.copyWith(artUri: artUri);
        }
        return item;
      }).toList();

      final startIndex = restoredQueue.indexWhere((s) => s.id == lastSong!.id);
      
      await handler.loadQueuePaused(
        mediaItems,
        initialIndex: startIndex < 0 ? 0 : startIndex,
        initialPosition: lastPositionMs > 0
            ? Duration(milliseconds: lastPositionMs)
            : Duration.zero,
      );

      _trackingId = lastSong.id;
      final songDuration = lastSong.duration > 0
          ? Duration(milliseconds: lastSong.duration)
          : Duration.zero;

      state = state.copyWith(
        currentSong: lastSong,
        queue: restoredQueue,
        queueSource: lastQueueSource,
        position: lastPositionMs > 0 ? Duration(milliseconds: lastPositionMs) : Duration.zero,
        duration: songDuration,
        isPlaying: false,
      );

      debugPrint('[PlayerNotifier] restoreLastPlayed: selesai — player dalam keadaan PAUSED dengan durasi $songDuration');
    } catch (e) {
      debugPrint('[PlayerNotifier] restoreLastPlayed error: $e');
    }
  }

  Future<void> clearQueue() async {
    final handler = ref.read(audioHandlerProvider);
    await handler.clearQueue();
    state = state.copyWith(
      queue: const [],
      currentSong: null,
      isPlaying: false,
      position: Duration.zero,
      duration: Duration.zero,
    );
    _trackingId = null;
  }

  Future<void> addToQueue(SongModel song) async {
    final handler = ref.read(audioHandlerProvider);
    final datasource = ref.read(musicLocalDatasourceProvider);

    if (state.currentSong == null) {
      await playSong(song, [song]);
      return;
    }

    final item = _toMediaItemSync(song);
    await handler.addNextToQueue(item);

    AlbumArtService.instance.getArtworkBytes(song.id, datasource).then((bytes) {
      if (bytes != null) {
        handler.updateArtwork({song.id: bytes});
      }
    });
  }

  /// Removes a single song from the tracked queue state without touching audio playback.
  void removeFromQueue(int songId) {
    if (state.queue.any((s) => s.id == songId)) {
      state = state.copyWith(
        queue: state.queue.where((s) => s.id != songId).toList(),
      );
    }
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    final handler = ref.read(audioHandlerProvider);
    await handler.reorderQueue(oldIndex, newIndex);

    final newQueue = List<SongModel>.from(state.queue);
    if (oldIndex < newQueue.length && newIndex < newQueue.length) {
      final item = newQueue.removeAt(oldIndex);
      newQueue.insert(newIndex, item);
      state = state.copyWith(queue: newQueue);
    }
  }

  List<SongModel> buildContextualQueue(
      SongModel song, List<SongModel> allSongs) {
    if (allSongs.isEmpty) return [song];

    final sameArtist = allSongs
        .where((s) =>
            s.id != song.id &&
            s.artist.toLowerCase() == song.artist.toLowerCase())
        .toList();

    if (sameArtist.isNotEmpty) {
      final others = allSongs
          .where((s) =>
              s.id != song.id &&
              s.artist.toLowerCase() != song.artist.toLowerCase())
          .toList();
      return [song, ...sameArtist, ...others];
    }

    final idx = allSongs.indexWhere((s) => s.id == song.id);
    if (idx < 0) return [song, ...allSongs];

    final after = allSongs.sublist(idx + 1);
    final before = allSongs.sublist(0, idx);
    return [song, ...after, ...before];
  }

  MediaItem _toMediaItemSync(SongModel song) {
    return MediaItem(
      id: song.id.toString(),
      title: song.title.isNotEmpty ? song.title : 'Unknown Title',
      artist: song.artist.isNotEmpty ? song.artist : 'Unknown Artist',
      album: song.album.isNotEmpty ? song.album : '',
      duration: song.duration > 0
          ? Duration(milliseconds: song.duration)
          : null,
      extras: {
        'uri': song.uri,
        'songId': song.id,
      },
    );
  }
}

final playerProvider =
    NotifierProvider<PlayerNotifier, PlayerState>(PlayerNotifier.new);

// ─── Search State ─────────────────────────────────────────────────────────

class SearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void update(String query) => state = query;
}

final searchQueryProvider =
    NotifierProvider<SearchNotifier, String>(SearchNotifier.new);

// ─── Sleep Timer State & Notifier ───────────────────────────────────────────

class SleepTimerState {
  final Duration? duration;
  final int remainingSeconds;
  final bool isEndOfSong;

  const SleepTimerState({
    this.duration,
    this.remainingSeconds = 0,
    this.isEndOfSong = false,
  });

  String get formattedRemaining {
    if (isEndOfSong) return 'Akhir lagu';
    final m = remainingSeconds ~/ 60;
    final s = remainingSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

class SleepTimerNotifier extends Notifier<SleepTimerState> {
  Timer? _timer;
  StreamSubscription? _mediaItemSub;
  StreamSubscription? _stateSub;
  StreamSubscription? _positionSub;
  int? _targetSongId;

  @override
  SleepTimerState build() {
    ref.onDispose(() => _cancelAllSubscriptions());
    return const SleepTimerState();
  }

  void _cancelAllSubscriptions() {
    _timer?.cancel();
    _timer = null;
    _mediaItemSub?.cancel();
    _mediaItemSub = null;
    _stateSub?.cancel();
    _stateSub = null;
    _positionSub?.cancel();
    _positionSub = null;
    _targetSongId = null;
  }

  void setTimer(Duration? duration) {
    _cancelAllSubscriptions();

    if (duration == null) {
      state = const SleepTimerState();
      return;
    }

    if (duration.inSeconds == -1) {
      // Akhir lagu ini
      final currentSong = ref.read(playerProvider).currentSong;
      state = const SleepTimerState(
        duration: Duration(seconds: -1),
        isEndOfSong: true,
      );

      if (currentSong == null) return;
      _targetSongId = currentSong.id;

      final handler = ref.read(audioHandlerProvider);

      // 1. Listen ke mediaItem: saat lagu aktif berubah dari _targetSongId, pemicu stop & exit
      _mediaItemSub = handler.mediaItem.listen((item) {
        if (!state.isEndOfSong) return;
        final songId = item?.extras?['songId'] as int?;
        if (songId != null && _targetSongId != null && songId != _targetSongId) {
          debugPrint('[SleepTimer] Media item changed from $_targetSongId to $songId — triggering stop & exit');
          _triggerStopAndExit();
        }
      });

      // 2. Listen ke playerStateStream: ketika processingState == completed
      _stateSub = handler.player.playerStateStream.listen((ps) {
        if (!state.isEndOfSong) return;
        if (ps.processingState == ProcessingState.completed) {
          debugPrint('[SleepTimer] ProcessingState completed — triggering stop & exit');
          _triggerStopAndExit();
        }
      });

      // 3. Listen ke positionStream: ketika posisi mencapai durasi akhir lagu
      _positionSub = handler.positionStream.listen((pos) {
        if (!state.isEndOfSong) return;
        final dur = ref.read(playerProvider).duration;
        if (dur.inMilliseconds > 0 && pos.inMilliseconds >= dur.inMilliseconds - 400) {
          debugPrint('[SleepTimer] Position reached end of song — triggering stop & exit');
          _triggerStopAndExit();
        }
      });

      return;
    }

    final totalSecs = duration.inSeconds;
    state = SleepTimerState(
      duration: duration,
      remainingSeconds: totalSecs,
    );

    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      final next = state.remainingSeconds - 1;
      if (next <= 0) {
        t.cancel();
        _triggerStopAndExit();
      } else {
        state = SleepTimerState(
          duration: duration,
          remainingSeconds: next,
        );
      }
    });
  }

  void onSongCompleted() {
    if (state.isEndOfSong) {
      _triggerStopAndExit();
    }
  }

  Future<void> _triggerStopAndExit() async {
    _cancelAllSubscriptions();
    final handler = ref.read(audioHandlerProvider);
    final playerNotif = ref.read(playerProvider.notifier);

    // 1. Matikan audio playback dan hentikan AudioService foreground notification
    try {
      await handler.stop();
    } catch (_) {}

    // 2. Clear queue dan reset state player & timer
    try {
      await playerNotif.clearQueue();
    } catch (_) {}

    state = const SleepTimerState();

    // 3. Gunakan native closeAppDeeper agar task finish & exitProcess(0) dieksekusi
    try {
      const ch = MethodChannel('com.ibnutify.ml/audio');
      await ch.invokeMethod('closeAppDeeper');
    } catch (_) {
      SystemNavigator.pop();
    }
  }
}

final sleepTimerProvider =
    NotifierProvider<SleepTimerNotifier, SleepTimerState>(SleepTimerNotifier.new);

// ─── Curfew Check Service (00:00 - 03:00) ──────────────────────────────────

final curfewCheckProvider = Provider<void>((ref) {
  Timer.periodic(const Duration(minutes: 1), (_) {
    final now = DateTime.now();
    if (now.hour >= 0 && now.hour < 3) {
      final playerState = ref.read(playerProvider);
      if (playerState.isPlaying) {
        ref.read(audioHandlerProvider).stop().catchError((_) {});
        ref.read(playerProvider.notifier).clearQueue();
        const ch = MethodChannel('com.ibnutify.ml/audio');
        ch.invokeMethod('closeAppDeeper').catchError((_) {
          SystemNavigator.pop();
        });
      }
    }
  });
});

final selectedGenreProvider = StateProvider<String?>((ref) => null);

final selectedSearchCategoryProvider = StateProvider<String>((ref) => 'All');

final genreFilteredSongsProvider = Provider<List<SongModel>>((ref) {
  final genre = ref.watch(selectedGenreProvider);
  final songsAsync = ref.watch(songsProvider);
  final songs = songsAsync.value ?? [];
  if (genre == null || genre.isEmpty) return songs;
  return songs.where((s) => s.computedGenre.toLowerCase() == genre.toLowerCase()).toList();
});

final searchResultsProvider = FutureProvider<List<SongModel>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  final repo = ref.watch(musicRepositoryProvider);
  final songs = await repo.searchSongs(query);
  final genre = ref.watch(selectedGenreProvider);
  if (genre != null && genre.isNotEmpty) {
    return songs.where((s) => s.computedGenre.toLowerCase() == genre.toLowerCase()).toList();
  }
  return songs;
});

// ─── AI Moods State ───────────────────────────────────────────────────────

class AIMoodsState {
  final List<AIMood> moods;
  final bool isLoading;

  const AIMoodsState({this.moods = const [], this.isLoading = false});
}

class AIMoodsNotifier extends Notifier<AIMoodsState> {
  @override
  AIMoodsState build() => const AIMoodsState();

  Future<void> analyze(List<SongModel> songs) async {
    state = const AIMoodsState(isLoading: true);
    final repo = ref.read(musicRepositoryProvider);
    final moods = await repo.analyzeLibraryMoods(songs);
    state = AIMoodsState(moods: moods, isLoading: false);
  }

  void clear() => state = const AIMoodsState();
}

final aiMoodsProvider =
    NotifierProvider<AIMoodsNotifier, AIMoodsState>(AIMoodsNotifier.new);

// ─── AI Chat State ────────────────────────────────────────────────────────

class AIChatState {
  final String sessionId;          // UUID unik per sesi
  final DateTime sessionCreatedAt; // Waktu sesi dimulai
  final List<AIChatMessage> messages;
  final bool isLoading;
  final List<SongModel>? pendingSongs;
  final String? pendingPlaylistName;

  AIChatState({
    String? sessionId,
    DateTime? sessionCreatedAt,
    this.messages = const [],
    this.isLoading = false,
    this.pendingSongs,
    this.pendingPlaylistName,
  })  : sessionId = sessionId ?? _generateId(),
        sessionCreatedAt = sessionCreatedAt ?? DateTime.now();

  static String _generateId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rnd = math.Random().nextInt(99999);
    return 'sess_${now}_$rnd';
  }

  AIChatState copyWith({
    List<AIChatMessage>? messages,
    bool? isLoading,
    List<SongModel>? pendingSongs,
    String? pendingPlaylistName,
    bool clearPending = false,
  }) {
    return AIChatState(
      sessionId: sessionId,
      sessionCreatedAt: sessionCreatedAt,
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      pendingSongs: clearPending ? null : (pendingSongs ?? this.pendingSongs),
      pendingPlaylistName: clearPending ? null : (pendingPlaylistName ?? this.pendingPlaylistName),
    );
  }
}

class AIChatNotifier extends Notifier<AIChatState> {
  @override
  AIChatState build() {
    return AIChatState(
      messages: [],
    );
  }

  Future<void> sendMessage(String input) async {
    if (input.trim().isEmpty || state.isLoading) return;

    debugPrint('[AIChatNotifier] sendMessage: "$input"');

    // Tambah pesan user ke chat
    final userMsg = AIChatMessage(role: ChatRole.user, content: input.trim());
    state = state.copyWith(
      messages: [...state.messages, userMsg],
      isLoading: true,
      clearPending: true,
    );

    // Ambil semua lagu lokal sebagai konteks
    final songs = ref.read(songsProvider).value ?? [];
    final datasource = ref.read(geminiDatasourceProvider);

    final aiMsg = await datasource.sendChatMessage(input.trim(), songs);

    debugPrint('[AIChatNotifier] AI response received. isLoading → false');

    state = state.copyWith(
      messages: [...state.messages, aiMsg],
      isLoading: false,
      pendingSongs: aiMsg.recommendedSongs,
      pendingPlaylistName: aiMsg.pendingPlaylistName,
    );

    // Auto-save sesi ke history
    _autoSaveSession();
  }

  void _autoSaveSession() {
    try {
      final msgs = state.messages;
      // Cari pesan user pertama untuk judul
      final firstUser = msgs.where((m) => m.role == ChatRole.user).firstOrNull;
      final title = firstUser != null
          ? ChatHistoryService.generateTitle(firstUser.content)
          : 'Obrolan AI';

      final sessionMsgs = msgs.map((m) => ChatSessionMessage(
        role: m.role == ChatRole.user ? 'user' : 'ai',
        content: m.content,
      )).toList();

      final session = ChatSession(
        id: state.sessionId,
        title: title,
        messages: sessionMsgs,
        createdAt: state.sessionCreatedAt,
      );

      ChatHistoryService.instance.saveSession(session);
      debugPrint('[AIChatNotifier] Auto-saved session "$title"');
    } catch (e) {
      debugPrint('[AIChatNotifier] Auto-save error: $e');
    }
  }

  Future<void> createPlaylistFromPending() async {
    final songs = state.pendingSongs;
    final name = state.pendingPlaylistName ?? 'AI Mix';
    if (songs == null || songs.isEmpty) return;

    // Buat playlist dan isi dengan lagu rekomendasi
    final playlistsNotifier = ref.read(playlistsProvider.notifier);
    await playlistsNotifier.create(name,
        description: 'Dibuat oleh IbnuTify AI 🤖');

    // Ambil playlist yang baru saja dibuat (urutan terbaru)
    final allPlaylists = ref.read(playlistsProvider).value ?? [];
    if (allPlaylists.isEmpty) return;
    final newPlaylist = allPlaylists.first;

    await playlistsNotifier.addSongs(newPlaylist.id, songs.map((s) => s.id).toList());

    // Tambah konfirmasi ke chat
    final confirmMsg = AIChatMessage(
      role: ChatRole.ai,
      content:
          'Playlist "$name" berhasil dibuat dengan ${songs.length} lagu!\n'
          'Cek di tab Library ya.',
    );
    state = state.copyWith(
      messages: [...state.messages, confirmMsg],
      clearPending: true,
    );
  }

  /// Menambahkan pesan user ke chat tanpa memanggil AI.
  /// Dipakai saat user paste Spotify URL — URL-nya ditampilkan sebagai bubble kanan,
  /// tapi pemrosesan diteruskan ke DownloadNotifier, bukan AI.
  void addUserMessageOnly(AIChatMessage msg) {
    state = state.copyWith(messages: [...state.messages, msg]);
    debugPrint('[AIChatNotifier] addUserMessageOnly: "${msg.content.substring(0, msg.content.length.clamp(0, 60))}..."');
  }

  void clearChat() {
    debugPrint('[AIChatNotifier] clearChat — starting new session');
    state = build();
  }

  /// Restore sesi dari history ke state aktif.
  void restoreSession(ChatSession session) {
    debugPrint('[AIChatNotifier] Restoring session: "${session.title}"');
    final msgs = session.messages.map((m) => AIChatMessage(
      role: m.role == 'user' ? ChatRole.user : ChatRole.ai,
      content: m.content,
    )).toList();
    state = AIChatState(
      sessionId: session.id,
      sessionCreatedAt: session.createdAt,
      messages: msgs,
    );
  }
}

final aiChatProvider =
    NotifierProvider<AIChatNotifier, AIChatState>(AIChatNotifier.new);

// ─── Playlists State ──────────────────────────────────────────────────────

class PlaylistsNotifier extends AsyncNotifier<List<PlaylistModel>> {
  @override
  Future<List<PlaylistModel>> build() async {
    final repo = ref.watch(musicRepositoryProvider);
    return await repo.getAllPlaylists();
  }

  Future<void> refresh() async {
    final repo = ref.read(musicRepositoryProvider);
    state = AsyncData(await repo.getAllPlaylists());
  }

  Future<void> create(String name, {String? description}) async {
    final repo = ref.read(musicRepositoryProvider);
    await repo.createPlaylist(name, description: description);
    await refresh();
  }

  Future<void> addSong(String playlistId, int songId) async {
    final repo = ref.read(musicRepositoryProvider);
    await repo.addSongToPlaylist(playlistId, songId);
    await refresh();
  }

  Future<void> addSongs(String playlistId, List<int> songIds) async {
    final repo = ref.read(musicRepositoryProvider);
    await repo.addSongsToPlaylist(playlistId, songIds);
    await refresh();
  }

  Future<void> removeSong(String playlistId, int songId) async {
    final repo = ref.read(musicRepositoryProvider);
    await repo.removeSongFromPlaylist(playlistId, songId);
    await refresh();
  }

  Future<void> delete(String playlistId) async {
    final repo = ref.read(musicRepositoryProvider);
    await repo.deletePlaylist(playlistId);
    await refresh();
  }

  Future<void> updateCover(
    String playlistId, {
    required String coverTemplateType,
    String? coverColor,
    String? coverIcon,
    String? coverTitle,
  }) async {
    final repo = ref.read(musicRepositoryProvider);
    await repo.updatePlaylistCover(
      playlistId,
      coverTemplateType: coverTemplateType,
      coverColor: coverColor,
      coverIcon: coverIcon,
      coverTitle: coverTitle,
    );
    await refresh();
  }

  Future<void> addToLikedSongs(int songId) async {
    final repo = ref.read(musicRepositoryProvider);
    const likedName = 'Liked Songs';

    var playlists = await repo.getAllPlaylists();
    var liked = playlists.where((p) => p.name == likedName).firstOrNull;

    liked ??= await repo.createPlaylist(
      likedName,
      description: 'Songs you\'ve liked',
    );

    if (!liked.songIds.contains(songId)) {
      await repo.addSongToPlaylist(liked.id, songId);
    }

    await repo.toggleLike(songId);
    final allSongs = await repo.getAllSongs();
    final song = allSongs.where((s) => s.id == songId).firstOrNull;
    if (song != null && !song.isLiked) {
      await repo.toggleLike(songId);
    }

    await refresh();
    await ref.read(songsProvider.notifier).refresh();
  }

  bool isInLikedSongs(int songId) {
    if (!state.hasValue) return false;
    final likedPlaylist = state.value!.where((p) => p.name == 'Liked Songs').firstOrNull;
    return likedPlaylist?.songIds.contains(songId) ?? false;
  }
}

final playlistsProvider =
    AsyncNotifierProvider<PlaylistsNotifier, List<PlaylistModel>>(
        PlaylistsNotifier.new);

// ─── Navigation State ─────────────────────────────────────────────────────

enum AppScreen { home, search, library, aiMoods }

class NavigationNotifier extends Notifier<AppScreen> {
  @override
  AppScreen build() => AppScreen.home;

  void navigate(AppScreen screen) => state = screen;
}

final navigationProvider =
    NotifierProvider<NavigationNotifier, AppScreen>(NavigationNotifier.new);

// ─── Smart Lists Providers ─────────────────────────────────────────────

final recentlyPlayedProvider = FutureProvider<List<SongModel>>((ref) async {
  ref.watch(songsProvider);
  return await ref.read(musicRepositoryProvider).getRecentlyPlayed24h(limit: 100);
});

final topSongsProvider = FutureProvider<List<SongModel>>((ref) async {
  ref.watch(songsProvider);
  return await ref.read(musicRepositoryProvider).getTopSongs(limit: 20);
});

final duplicateSongsProvider = Provider<Map<String, List<SongModel>>>((ref) {
  final songs = ref.watch(songsProvider).value ?? [];
  final groups = <String, List<SongModel>>{};
  for (final song in songs) {
    final cleanTitle = song.title
        .replaceAll(RegExp(r'\s*\(Copy.*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\(\d+\)', caseSensitive: false), '')
        .toLowerCase()
        .trim();
    final key = '$cleanTitle|${song.artist.toLowerCase().trim()}';
    groups.putIfAbsent(key, () => []).add(song);
  }
  return Map.fromEntries(
    groups.entries.where((e) => e.value.length > 1),
  );
});

final randomHomeSongsProvider = Provider<List<SongModel>>((ref) {
  final songsAsync = ref.watch(songsProvider);
  final songs = songsAsync.value ?? [];
  if (songs.isEmpty) return [];
  final copy = List<SongModel>.from(songs)..shuffle();
  return copy.take(6).toList();
});

class NamedPlaylist {
  final String id;
  final String name;
  final String description;
  final List<SongModel> songs;

  NamedPlaylist({
    required this.id,
    required this.name,
    required this.description,
    required this.songs,
  });
}

final dailyMixesProvider = Provider<List<NamedPlaylist>>((ref) {
  final songsAsync = ref.watch(songsProvider);
  final songs = songsAsync.value ?? [];
  if (songs.isEmpty) return [];
  
  final dayNames = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
  final dayDescriptions = [
    'Semangat awal pekan dengan irama yang disesuaikan untuk Senin Anda.',
    'Menjaga produktivitas hari Selasa dengan musik pilihan khusus.',
    'Harmoni tengah pekan untuk menemani rutinitas Rabu Anda.',
    'Alunan musik santai bersiap menyambut akhir pekan di hari Kamis.',
    'Waktunya rileks dan nikmati akhir pekan yang menyenangkan mulai Jumat.',
    'Daftar putar dinamis untuk menemani aktivitas hari Sabtu Anda.',
    'Kedamaian hari Minggu dengan lagu-lagu tenang penyejuk jiwa.'
  ];
  
  final now = DateTime.now();
  final weekOfYear = (now.day + 7) ~/ 7;
  final weekSeed = now.year * 100 + weekOfYear;

  final Map<int, List<SongModel>> clusters = {};
  for (var song in songs) {
    if (song.clusterId != null) {
      clusters.putIfAbsent(song.clusterId!, () => []).add(song);
    }
  }

  final List<NamedPlaylist> list = [];
  for (int i = 0; i < 7; i++) {
    final clusterSongs = clusters[i] ?? [];
    final rng = math.Random(weekSeed + (i * 37));
    
    final List<SongModel> mixSongs;
    if (clusterSongs.isNotEmpty && clusterSongs.length >= 3) {
      mixSongs = List<SongModel>.from(clusterSongs)..shuffle(rng);
    } else {
      final shuffledAll = List<SongModel>.from(songs)..shuffle(rng);
      final count = math.min(15, math.max(3, (songs.length / 3).ceil()));
      mixSongs = shuffledAll.take(count).toList();
    }

    if (mixSongs.isNotEmpty) {
      list.add(NamedPlaylist(
        id: 'daily_mix_$i',
        name: 'Daily Mix ${dayNames[i]}',
        description: dayDescriptions[i],
        songs: mixSongs,
      ));
    }
  }
  return list;
});

final songErasProvider = Provider<List<NamedPlaylist>>((ref) {
  final songsAsync = ref.watch(songsProvider);
  final songs = songsAsync.value ?? [];
  
  final Map<String, List<SongModel>> eras = {};
  for (var song in songs) {
    int? year = song.releaseYear;
    
    // Fallback to file modification year if ID3 tag fails
    if (year == null || year <= 0) {
      try {
        final stat = FileStat.statSync(song.uri);
        year = stat.modified.year;
      } catch (_) {
        year = 2024; // Ultimate fallback
      }
    }
    
    if (year > 0) {
      final decade = (year ~/ 10) * 10;
      final key = '${decade}s';
      eras.putIfAbsent(key, () => []).add(song);
    }
  }
  
  final sortedKeys = eras.keys.toList()..sort((a, b) => a.compareTo(b));
    
  return sortedKeys.map((key) {
    final songsInEra = eras[key]!;
    return NamedPlaylist(
      id: 'era_mix_${key.toLowerCase()}',
      name: '$key Mix',
      description: 'Koleksi lagu terbaik Anda dari era $key.',
      songs: songsInEra,
    );
  }).toList();
});

// ─── Download State ───────────────────────────────────────────────────────────

/// Pesan di chat yang berasal dari sistem downloader (bukan AI).
class DownloadChatMessage {
  final String content;
  final bool isSystem;         // true = dari sistem, bukan user
  final bool isProgress;       // true = pesan progress yang akan di-update in-place
  final DownloadProgress? progress;

  const DownloadChatMessage({
    required this.content,
    this.isSystem = true,
    this.isProgress = false,
    this.progress,
  });

  DownloadChatMessage copyWithProgress(DownloadProgress p, String text) {
    return DownloadChatMessage(
      content: text,
      isSystem: true,
      isProgress: true,
      progress: p,
    );
  }
}

class DownloadState {
  /// true = sedang menunggu user memasukkan Spotify URL
  final bool awaitingUrl;
  /// true = download sedang berjalan di background
  final bool isDownloading;
  /// Progress terkini dari downloader.py
  final DownloadProgress progress;
  /// Pesan yang tampil di chat (system messages, bukan AI)
  final List<DownloadChatMessage> messages;
  /// URL terakhir yang gagal (untuk fitur Retry)
  final String? lastFailedUrl;
  /// Judul lagu terakhir yang dicoba (untuk konteks Retry)
  final String? lastFailedTitle;

  const DownloadState({
    this.awaitingUrl = false,
    this.isDownloading = false,
    this.progress = const DownloadProgress(),
    this.messages = const [],
    this.lastFailedUrl,
    this.lastFailedTitle,
  });

  DownloadState copyWith({
    bool? awaitingUrl,
    bool? isDownloading,
    DownloadProgress? progress,
    List<DownloadChatMessage>? messages,
    String? lastFailedUrl,
    String? lastFailedTitle,
    bool clearFailed = false,
  }) {
    return DownloadState(
      awaitingUrl: awaitingUrl ?? this.awaitingUrl,
      isDownloading: isDownloading ?? this.isDownloading,
      progress: progress ?? this.progress,
      messages: messages ?? this.messages,
      lastFailedUrl: clearFailed ? null : (lastFailedUrl ?? this.lastFailedUrl),
      lastFailedTitle: clearFailed ? null : (lastFailedTitle ?? this.lastFailedTitle),
    );
  }
}

class DownloadNotifier extends Notifier<DownloadState> {
  Timer? _pollTimer;

  @override
  DownloadState build() {
    // BUG-3 FIX: Cancel polling timer jika provider di-dispose (navigasi keluar)
    ref.onDispose(() {
      debugPrint('[DownloadNotifier] disposed — stopping poll timer');
      _stopPolling();
    });
    return const DownloadState();
  }

  /// User menekan chip "Download Music" — masuk mode menunggu URL.
  void requestUrl() {
    const botMsg = DownloadChatMessage(
      content: '**Download Music**\n\n'
          'Oke! Paste link Spotify kamu di sini ya.\n'
          'Format yang didukung:\n'
          '• Track: `https://open.spotify.com/track/...`\n'
          '• Playlist: `https://open.spotify.com/playlist/...`\n\n'
          'Lagu akan disimpan di:\n'
          '`Download/Ibnutify/`\n'
          '_(Playlist akan disimpan di subfolder sesuai nama playlist)_',
    );
    state = state.copyWith(
      awaitingUrl: true,
      messages: [...state.messages, botMsg],
    );
  }

  /// User mengirim teks saat mode awaitingUrl — langsung proses sebagai URL.
  Future<void> handleUserInput(String input) async {
    debugPrint('[DownloadNotifier] handleUserInput: "$input"');

    // [REQ-1.3 FIX] Tampilkan pesan input pengguna di obrolan chat sebelum unduhan
    final userMsg = DownloadChatMessage(
      content: input,
      isSystem: false,
    );
    state = state.copyWith(messages: [...state.messages, userMsg]);

    // Routing: cek playlist dulu, lalu track, lalu error
    if (DownloadService.isSpotifyPlaylistUrl(input)) {
      debugPrint('[DownloadNotifier] Intent: PLAYLIST download');
      await _handlePlaylistDownload(input);
      return;
    }

    if (!DownloadService.isSpotifyTrackUrl(input)) {
      const errMsg = DownloadChatMessage(
        content: '**URL tidak valid.**\n\nMasukkan link Spotify track atau playlist yang benar.\n'
            'Contoh track: `https://open.spotify.com/track/6xrP29Jvv...`\n'
            'Contoh playlist: `https://open.spotify.com/playlist/...`',
      );
      state = state.copyWith(messages: [...state.messages, errMsg]);
      debugPrint('[DownloadNotifier] URL validation failed — not a Spotify URL');
      return;
    }

    debugPrint('[DownloadNotifier] Intent: TRACK download');
    const fetchingMsg = DownloadChatMessage(
      content: 'Mencari informasi lagu dari Spotify...',
    );
    state = state.copyWith(
      awaitingUrl: false,
      messages: [...state.messages, fetchingMsg],
      clearFailed: true,
    );

    // Ambil metadata dulu untuk preview
    final service = DownloadService.instance;
    debugPrint('[DownloadNotifier] Fetching track metadata...');
    final meta = await service.getTrackMetadata(input);

    if (meta != null) {
      debugPrint('[DownloadNotifier] Metadata OK: "${meta.title}" by "${meta.artist}"');
      final previewMsg = DownloadChatMessage(
        content: '**${meta.title}**\n'
            'Artist: ${meta.artist}\n'
            'Album: ${meta.album}${meta.year.isNotEmpty ? ' (${meta.year})' : ''}'
            '${meta.genre.isNotEmpty ? '\nGenre: ${meta.genre}' : ''}\n\n'
            'Memulai proses unduhan...',
      );
      state = state.copyWith(messages: [...state.messages, previewMsg]);
    } else {
      debugPrint('[DownloadNotifier] Metadata fetch returned null — continuing without preview');
      const startMsg = DownloadChatMessage(
        content: 'Memulai unduhan...',
      );
      state = state.copyWith(messages: [...state.messages, startMsg]);
    }

    const progressMsg = DownloadChatMessage(
      content: 'Menghubungi YouTube...',
      isProgress: true,
      progress: DownloadProgress(),
    );
    final msgs = [...state.messages, progressMsg];
    state = state.copyWith(isDownloading: true, messages: msgs);

    // Start download di background + polling timer
    _startPolling();

    debugPrint('[DownloadNotifier] Starting downloadTrack...');
    final result = await service.downloadTrack(input);
    _stopPolling();
    debugPrint('[DownloadNotifier] downloadTrack finished. success=${result.success} status=${result.status}');

    // Trigger local scan if successfully downloaded new song
    if (result.success && result.status != 'skipped') {
      // Scan terlebih dahulu agar lagu baru masuk ke DB
      await ref.read(songsProvider.notifier).scanDeviceSongs();

      // [REQ-1.4 FIX] Fallback album art: cari artwork via AlbumArtService & simpan .jpg di Download/Ibnutify/
      Future.microtask(() async {
        try {
          final allSongs = ref.read(songsProvider).value ?? [];
          final newSong = allSongs.where((s) =>
            s.title.toLowerCase().contains(result.title.toLowerCase()) &&
            s.artist.toLowerCase().contains(result.artist.toLowerCase())
          ).firstOrNull;

          if (newSong != null && newSong.albumArtPath == null) {
            debugPrint('[DownloadNotifier] Cover art missing for "${newSong.title}" — triggering fallback [REQ-1.4]');
            final datasource = ref.read(musicLocalDatasourceProvider);
            final bytes = await AlbumArtService.instance.getArtworkBytes(newSong.id, datasource);
            if (bytes != null && bytes.isNotEmpty) {
              final downloadDir = await DownloadService.instance.getDownloadDir();
              final safeTitle = newSong.title.replaceAll(RegExp(r'[\\/*?:"<>|]'), '');
              final coverFile = File('$downloadDir/$safeTitle.jpg');
              await coverFile.writeAsBytes(bytes);
              debugPrint('[DownloadNotifier] Saved fallback cover .jpg: ${coverFile.path}');
              await datasource.updateSongMetadata(
                newSong.id,
                albumArtPath: coverFile.path,
              );
              await ref.read(songsProvider.notifier).scanDeviceSongs();
            }
          }
        } catch (e) {
          debugPrint('[DownloadNotifier] Cover art fallback error: $e');
        }
      });
    } else if (!result.success) {
      // no-op: jangan scan jika download benar-benar gagal
    }

    // Update pesan progress terakhir menjadi hasil akhir
    final updatedMsgs = List<DownloadChatMessage>.from(state.messages);
    if (updatedMsgs.isNotEmpty && updatedMsgs.last.isProgress) {
      updatedMsgs.removeLast();
    }

    DownloadChatMessage resultMsg;
    if (result.success) {
      if (result.status == 'skipped') {
        resultMsg = DownloadChatMessage(
          content: '**Lagu sudah ada!**\n\n'
              '`${result.title}` sudah tersimpan di folder Download/Ibnutify.\n'
              'Download dilewati.',
        );
      } else {
        resultMsg = DownloadChatMessage(
          content: '**Unduhan selesai!**\n\n'
              'Judul: ${result.title}\n'
              'Artist: ${result.artist}\n'
              'Album: ${result.album}\n\n'
              'Tersimpan di: `Download/Ibnutify/`',
        );
      }
      state = state.copyWith(
        isDownloading: false,
        messages: [...updatedMsgs, resultMsg],
        clearFailed: true,
      );
    } else {
      debugPrint('[DownloadNotifier] Download FAILED: ${result.error}');
      resultMsg = DownloadChatMessage(
        content: '**Unduhan gagal**\n\n${result.error}\n\n'
            'Ketuk tombol **Coba Lagi** atau paste link Spotify yang lain.',
      );
      // BUG-5 FIX: Simpan URL yang gagal untuk fitur Retry
      state = state.copyWith(
        isDownloading: false,
        messages: [...updatedMsgs, resultMsg],
        lastFailedUrl: input,
        lastFailedTitle: meta?.title,
      );
    }
  }

  /// BUG-5 FIX: Ulangi download dengan URL yang terakhir gagal.
  Future<void> retryLastDownload() async {
    final url = state.lastFailedUrl;
    if (url == null || url.isEmpty) return;
    debugPrint('[DownloadNotifier] Retry download: $url');
    const retryMsg = DownloadChatMessage(
      content: '🔄 Mencoba ulang unduhan...',
    );
    state = state.copyWith(
      messages: [...state.messages, retryMsg],
      clearFailed: true,
    );
    await handleUserInput(url);
  }

  /// Batalkan proses unduhan yang sedang berjalan [REQ-1.3]
  Future<void> cancelCurrentDownload() async {
    debugPrint('[DownloadNotifier] Membatalkan unduhan aktif...');
    await DownloadService.instance.cancelDownload();
    _stopPolling();
    const cancelMsg = DownloadChatMessage(
      content: '**Unduhan dibatalkan oleh pengguna.**',
      isSystem: true,
    );
    final updatedMsgs = List<DownloadChatMessage>.from(state.messages);
    if (updatedMsgs.isNotEmpty && updatedMsgs.last.isProgress) {
      updatedMsgs.removeLast();
    }
    state = state.copyWith(
      isDownloading: false,
      messages: [...updatedMsgs, cancelMsg],
    );
  }

  /// Handle download seluruh playlist Spotify.
  Future<void> _handlePlaylistDownload(String url) async {
    const fetchingMsg = DownloadChatMessage(
      content: '🎵 Mengambil daftar lagu dari playlist Spotify...\n'
          '_Ini mungkin butuh beberapa detik tergantung jumlah track._',
    );
    state = state.copyWith(
      awaitingUrl: false,
      messages: [...state.messages, fetchingMsg],
    );

    final service = DownloadService.instance;

    // Tampilkan progress bubble sementara
    const progressMsg = DownloadChatMessage(
      content: 'Membaca informasi playlist...',
      isProgress: true,
      progress: DownloadProgress(),
    );
    final msgsWithProgress = [...state.messages, progressMsg];
    state = state.copyWith(isDownloading: true, messages: msgsWithProgress);

    _startPolling();

    // Panggil download_playlist (all-in-one: scrape + download semua track)
    final result = await service.downloadPlaylist(url);
    _stopPolling();

    // Trigger local library scan jika ada yang berhasil
    if (result.success) {
      ref.read(songsProvider.notifier).scanDeviceSongs();
    }

    // Hapus progress bubble terakhir
    final updatedMsgs = List<DownloadChatMessage>.from(state.messages);
    if (updatedMsgs.isNotEmpty && updatedMsgs.last.isProgress) {
      updatedMsgs.removeLast();
    }

    DownloadChatMessage resultMsg;
    if (result.success) {
      final failedInfo = result.failed.isNotEmpty
          ? '\n\n⚠️ ${result.failed.length} track gagal:\n- ${result.failed.join('\n- ')}'
          : '';
      resultMsg = DownloadChatMessage(
        content: '**✅ Playlist selesai diunduh!**\n\n'
            'Playlist: **${result.playlistName}**\n'
            'Total: ${result.total} lagu\n'
            'Berhasil: ${result.successful} lagu$failedInfo\n\n'
            'Tersimpan di:\n'
            '`Download/Ibnutify/${result.playlistName}/`',
      );
    } else {
      resultMsg = DownloadChatMessage(
        content: '**❌ Gagal mengunduh playlist**\n\n'
            '${result.error.isNotEmpty ? result.error : 'Terjadi error tidak diketahui.'}\n\n'
            'Pastikan URL playlist Spotify valid dan koneksi internet stabil.',
      );
    }

    state = state.copyWith(
      isDownloading: false,
      messages: [...updatedMsgs, resultMsg],
    );
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 800), (_) async {
      final progress = await DownloadService.instance.pollProgress();
      debugPrint('[DownloadNotifier.Poll] status=${progress.status.name} pct=${progress.percent.toStringAsFixed(1)} title="${progress.currentTitle}"');
      final msgs = List<DownloadChatMessage>.from(state.messages);

      // Cari indeks progress bubble terakhir
      final progressIdx = msgs.lastIndexWhere((m) => m.isProgress);
      if (progressIdx >= 0) {
        final updated = _buildProgressText(progress);
        msgs[progressIdx] = msgs[progressIdx].copyWithProgress(progress, updated);
        state = state.copyWith(progress: progress, messages: msgs);
      } else {
        state = state.copyWith(progress: progress);
      }

      // Stop polling jika sudah selesai
      if (progress.status == DownloadStatus.done ||
          progress.status == DownloadStatus.error ||
          progress.status == DownloadStatus.skipped) {
        debugPrint('[DownloadNotifier.Poll] Terminal status reached — stopping poll');
        _stopPolling();
      }
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  String _buildProgressText(DownloadProgress p) {
    switch (p.status) {
      case DownloadStatus.fetchingMetadata:
        return 'Mengambil data dari Spotify...';
      case DownloadStatus.downloading:
        final pct = p.percent.toStringAsFixed(1);
        final eta = p.etaDisplay.isNotEmpty ? ' — Sisa Waktu: ${p.etaDisplay}' : '';
        final spd = p.speedStr.isNotEmpty ? ' — ${p.speedStr}' : '';
        return 'Mengunduh... **$pct%**$eta$spd';
      case DownloadStatus.converting:
        return 'Mengkonversi ke format audio...';
      case DownloadStatus.tagging:
        return 'Menambahkan metadata dan cover art...';
      case DownloadStatus.done:
        return 'Selesai!';
      case DownloadStatus.skipped:
        return 'Lagu sudah ada, download dilewati.';
      case DownloadStatus.error:
        return '**Gagal:** ${p.error}';
      default:
        return 'Menghubungi YouTube...';
    }
  }

  void clearMessages() {
    _stopPolling();
    debugPrint('[DownloadNotifier] clearMessages — resetting download state');
    state = const DownloadState();
  }
}

final downloadProvider =
    NotifierProvider<DownloadNotifier, DownloadState>(DownloadNotifier.new);

// ─── Chat History State ─────────────────────────────────────────────────────
// Provider untuk riwayat sesi chat AI Moods yang ditampilkan di sidebar.

class ChatHistoryNotifier extends AsyncNotifier<List<ChatSession>> {
  @override
  Future<List<ChatSession>> build() async {
    debugPrint('[ChatHistoryNotifier] Loading chat sessions...');
    return await ChatHistoryService.instance.loadAll();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = AsyncData(await ChatHistoryService.instance.loadAll());
  }

  Future<void> deleteSession(String id) async {
    await ChatHistoryService.instance.deleteSession(id);
    await refresh();
  }

  Future<void> clearAll() async {
    await ChatHistoryService.instance.clearAll();
    state = const AsyncData([]);
  }
}

final chatHistoryProvider =
    AsyncNotifierProvider<ChatHistoryNotifier, List<ChatSession>>(
        ChatHistoryNotifier.new);

// ─── Workout State ─────────────────────────────────────────────────────────────

/// Satu titik koordinat GPS
class LatLngPoint {
  final double lat;
  final double lng;
  const LatLngPoint(this.lat, this.lng);
}

class WorkoutState {
  final String sportMode;
  final int elapsedSeconds;
  final double distanceKm;
  final List<LatLngPoint> routePoints;
  final bool isRunning;
  final bool isPaused;
  final bool locationGranted;
  final int songsPlayed;
  /// Kecepatan saat ini dalam m/s dari GPS Doppler
  final double currentSpeedMs;
  /// Akurasi GPS saat ini dalam meter
  final double gpsAccuracy;

  // ── Sensor Fusion Fields ─────────────────────────────────────────────────
  /// Total langkah (dari akselerometer peak detection)
  final int stepCount;
  /// Cadence realtime dalam langkah/menit (window 10 detik)
  final double cadenceSpm;
  /// Aktivitas yang terdeteksi otomatis oleh classifier
  final String detectedActivity;
  /// Total elevasi naik dalam meter
  final double elevationGainM;
  /// Total elevasi turun dalam meter
  final double elevationLossM;
  /// Ketinggian saat ini (GPS + Kalman filter) dalam meter
  final double currentAltitudeM;
  /// Estimasi kalori terbakar (Keytel jika HR tersedia, MET sebagai fallback)
  final double estimatedCalories;

  // ── Heart Rate / Smartwatch Fields ──────────────────────────────────────
  /// HR saat ini dari smartwatch BLE (0 = tidak tersedia)
  final int heartRateBpm;
  /// Zona latihan berdasarkan HR
  final HrZone currentHrZone;
  /// Status koneksi smartwatch
  final bool isWatchConnected;
  /// Nama perangkat BLE yang terhubung
  final String watchDeviceName;
  /// Riwayat HR per update (untuk grafik zona)
  final List<int> hrHistory;

  const WorkoutState({
    this.sportMode = '',
    this.elapsedSeconds = 0,
    this.distanceKm = 0.0,
    this.routePoints = const [],
    this.isRunning = false,
    this.isPaused = false,
    this.locationGranted = false,
    this.songsPlayed = 0,
    this.currentSpeedMs = 0.0,
    this.gpsAccuracy = 0.0,
    // Sensor fusion
    this.stepCount = 0,
    this.cadenceSpm = 0.0,
    this.detectedActivity = 'Diam',
    this.elevationGainM = 0.0,
    this.elevationLossM = 0.0,
    this.currentAltitudeM = 0.0,
    this.estimatedCalories = 0.0,
    // Heart rate
    this.heartRateBpm = 0,
    this.currentHrZone = HrZone.rest,
    this.isWatchConnected = false,
    this.watchDeviceName = '',
    this.hrHistory = const [],
  });

  WorkoutState copyWith({
    String? sportMode,
    int? elapsedSeconds,
    double? distanceKm,
    List<LatLngPoint>? routePoints,
    bool? isRunning,
    bool? isPaused,
    bool? locationGranted,
    int? songsPlayed,
    double? currentSpeedMs,
    double? gpsAccuracy,
    // Sensor fusion
    int? stepCount,
    double? cadenceSpm,
    String? detectedActivity,
    double? elevationGainM,
    double? elevationLossM,
    double? currentAltitudeM,
    double? estimatedCalories,
    // Heart rate
    int? heartRateBpm,
    HrZone? currentHrZone,
    bool? isWatchConnected,
    String? watchDeviceName,
    List<int>? hrHistory,
  }) =>
      WorkoutState(
        sportMode: sportMode ?? this.sportMode,
        elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
        distanceKm: distanceKm ?? this.distanceKm,
        routePoints: routePoints ?? this.routePoints,
        isRunning: isRunning ?? this.isRunning,
        isPaused: isPaused ?? this.isPaused,
        locationGranted: locationGranted ?? this.locationGranted,
        songsPlayed: songsPlayed ?? this.songsPlayed,
        currentSpeedMs: currentSpeedMs ?? this.currentSpeedMs,
        gpsAccuracy: gpsAccuracy ?? this.gpsAccuracy,
        stepCount: stepCount ?? this.stepCount,
        cadenceSpm: cadenceSpm ?? this.cadenceSpm,
        detectedActivity: detectedActivity ?? this.detectedActivity,
        elevationGainM: elevationGainM ?? this.elevationGainM,
        elevationLossM: elevationLossM ?? this.elevationLossM,
        currentAltitudeM: currentAltitudeM ?? this.currentAltitudeM,
        estimatedCalories: estimatedCalories ?? this.estimatedCalories,
        heartRateBpm: heartRateBpm ?? this.heartRateBpm,
        currentHrZone: currentHrZone ?? this.currentHrZone,
        isWatchConnected: isWatchConnected ?? this.isWatchConnected,
        watchDeviceName: watchDeviceName ?? this.watchDeviceName,
        hrHistory: hrHistory ?? this.hrHistory,
      );

  /// Pace realtime dari GPS Doppler speed (pos.speed) atau avgPace sebagai fallback.
  String get currentPace {
    // Gunakan Doppler speed jika valid dan user bergerak (> 0.5 m/s = 1.8 km/h)
    if (currentSpeedMs > 0.5) {
      final secsPerKm = (1000 / currentSpeedMs).round();
      if (secsPerKm > 0 && secsPerKm < 3600) {
        final m = secsPerKm ~/ 60;
        final s = secsPerKm % 60;
        return "$m'${s.toString().padLeft(2, '0')}\"/km";
      }
    }
    // Fallback: Tampilkan average pace jika sudah bergerak atau ada jarak & waktu
    if (distanceKm > 0.005 && elapsedSeconds > 0) {
      return avgPace;
    }
    return '--\'--"/km';
  }

  String get avgPace {
    if (distanceKm <= 0.01) return '--\'--"/km';
    final secsPerKm = (elapsedSeconds / distanceKm).round();
    final m = secsPerKm ~/ 60;
    final s = secsPerKm % 60;
    return "$m'${s.toString().padLeft(2, '0')}\"/km";
  }

  String get formattedDuration {
    final h = elapsedSeconds ~/ 3600;
    final m = (elapsedSeconds % 3600) ~/ 60;
    final s = elapsedSeconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  ActivityModel toActivity() {
    final routeJson = jsonEncode(
      routePoints.map((p) => {'lat': p.lat, 'lng': p.lng}).toList(),
    );
    return ActivityModel(
      sportMode: sportMode,
      duration: elapsedSeconds,
      distance: distanceKm,
      routePoints: routeJson,
      createdAt: DateTime.now().toIso8601String(),
      stepCount: stepCount,
      elevationGainM: elevationGainM,
      estimatedCalories: estimatedCalories,
      avgHeartRateBpm: hrHistory.isEmpty
          ? 0
          : (hrHistory.reduce((a, b) => a + b) / hrHistory.length).round(),
    );
  }
}

class WorkoutNotifier extends Notifier<WorkoutState> {
  // Bug 4 fix: listener untuk tracking berapa lagu yang diputar
  StreamSubscription? _songTrackingSub;

  // Local 1-second fallback timer di main isolate untuk menjamin UI timer selalu berjalan
  Timer? _localTimer;

  // Stream GPS di main isolate untuk tracking foreground real-time
  StreamSubscription<Position>? _mainLocationSub;

  // Callback yang terdaftar untuk menerima data dari task isolate
  DataCallback? _taskDataCallback;

  // Route points yang di-track di main isolate (sync dari task isolate)
  final List<LatLngPoint> _routePoints = [];
  LatLngPoint? _lastKnownPoint;

  // Completer untuk menunggu final state saat stopWorkout()
  Completer<Map<String, dynamic>>? _finalStateCompleter;

  // ── BLE Heart Rate ────────────────────────────────────────────────────────
  StreamSubscription<int>? _hrSub;
  StreamSubscription<WatchState>? _watchStateSub;

  @override
  WorkoutState build() => const WorkoutState();

  List<SongModel> _buildBpmQueue(String sportMode) {
    final allSongs = ref.read(songsProvider).value ?? [];
    final shuffled = List<SongModel>.from(allSongs)..shuffle();
    final withBpm = shuffled.where((s) => s.bpm != null).toList();

    List<SongModel> filtered;
    if (sportMode == 'Berjalan') {
      filtered = withBpm.where((s) => s.bpm! >= 80 && s.bpm! <= 120).toList();
    } else if (sportMode == 'Mendaki') {
      filtered = withBpm.where((s) => s.bpm! < 80).toList();
    } else {
      // Berlari / Sepeda: BPM >= 120
      filtered = withBpm.where((s) => s.bpm! >= 120).toList();
    }
    if (filtered.isEmpty) return shuffled;
    return filtered;
  }

  /// [Bug 1 Fix] Tambah parameter useCurrentQueue:
  /// - true  → gunakan antrean musik yang sedang aktif
  /// - false → buat antrean BPM baru
  Future<bool> startWorkout(String sportMode, {bool useCurrentQueue = false}) async {
    final granted = await LocationService.instance.requestPermission();
    if (!granted) {
      state = state.copyWith(locationGranted: false);
      return false;
    }

    // [REQ-3.3] Minta izin Activity Recognition di runtime untuk sensor pedometer & kalori
    try {
      if (await Permission.activityRecognition.isDenied) {
        await Permission.activityRecognition.request();
      }
    } catch (_) {}

    final currentPlayerState = ref.read(playerProvider);
    final initialSongsPlayed = (useCurrentQueue && currentPlayerState.currentSong != null) ? 1 : 0;

    // ── 1. Reset state & nyalakan Local 1-second UI Timer DULU ────────────
    _localTimer?.cancel();
    _routePoints.clear();
    _lastKnownPoint = null;

    state = WorkoutState(
      sportMode: sportMode,
      isRunning: true,
      isPaused: false,
      locationGranted: true,
      elapsedSeconds: 0,
      distanceKm: 0,
      routePoints: const [],
      songsPlayed: initialSongsPlayed,
    );

    // Dual-Timer: Main isolate timer memastikan UI timer (00:00:01...) langsung berjalan mulus
    _localTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.isRunning && !state.isPaused) {
        state = state.copyWith(elapsedSeconds: state.elapsedSeconds + 1);
      }
    });

    // ── 2. Mulai/pertahankan pemutaran musik ──────────────────────────────
    if (!useCurrentQueue) {
      final bpmQueue = _buildBpmQueue(sportMode);
      if (bpmQueue.isNotEmpty) {
        unawaited(ref.read(playerProvider.notifier).playSong(bpmQueue.first, bpmQueue));
        state = state.copyWith(songsPlayed: 1);
      }
    }

    // ── 3. Track pergantian lagu via mediaItem stream ─────────────────────
    _songTrackingSub?.cancel();
    String? lastTrackedMediaId;
    _songTrackingSub = ref.read(audioHandlerProvider).mediaItem.listen((item) {
      if (!state.isRunning) return;
      final newId = item?.id;
      if (newId != null && newId != lastTrackedMediaId) {
        lastTrackedMediaId = newId;
        if (state.songsPlayed > 0) {
          state = state.copyWith(songsPlayed: state.songsPlayed + 1);
        } else {
          state = state.copyWith(songsPlayed: 1);
        }
      }
    });

    // ── 4. Ambil posisi awal secara instan (lastKnown) tanpa blocking UI ──
    double? initLat, initLng;
    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        initLat = lastKnown.latitude;
        initLng = lastKnown.longitude;
        if (state.isRunning) {
          final initPoint = LatLngPoint(initLat, initLng);
          _routePoints.add(initPoint);
          _lastKnownPoint = initPoint;
          state = state.copyWith(
            currentSpeedMs: lastKnown.speed < 0 ? 0.0 : lastKnown.speed,
            gpsAccuracy: lastKnown.accuracy,
            routePoints: [initPoint],
          );
        }
      }
    } catch (_) {}

    // ── 4b. Mulai continuous GPS tracking stream langsung di main isolate ──
    _mainLocationSub?.cancel();
    _mainLocationSub = LocationService.instance.startTracking(
      onPosition: _onMainGpsPosition,
    );

    // ── 5. Simpan initial data ke storage untuk task isolate baca ─────────
    await FlutterForegroundTask.saveData(key: 'sportMode', value: sportMode);
    await FlutterForegroundTask.saveData(key: 'elapsedSeconds', value: 0);
    await FlutterForegroundTask.saveData(key: 'distanceKm', value: 0.0);
    await FlutterForegroundTask.saveData(key: 'isPaused', value: false);
    if (initLat != null && initLng != null) {
      await FlutterForegroundTask.saveData(
        key: 'routePoints',
        value: jsonEncode([{'lat': initLat, 'lng': initLng}]),
      );
    }

    // Request notification permission for Android 13+
    await FlutterForegroundTask.requestNotificationPermission();

    // Re-initialize communication port to ensure port mapping is active
    FlutterForegroundTask.initCommunicationPort();

    // ── 6. Cleanup & Register callback untuk terima update dari task isolate ────────
    if (_taskDataCallback != null) {
      FlutterForegroundTask.removeTaskDataCallback(_taskDataCallback!);
    }
    _taskDataCallback = _onTaskData;
    FlutterForegroundTask.addTaskDataCallback(_taskDataCallback!);

    // ── 7. Start Android Foreground Service ───────────────────────────────
    // Pastikan service terdahulu di-stop agar isolate baru ter-spawn dengan bersih
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
      await Future.delayed(const Duration(milliseconds: 500));
    }

    await FlutterForegroundTask.startService(
      serviceId: 1001, // ID unik untuk workout service
      serviceTypes: [
        ForegroundServiceTypes.location,
        ForegroundServiceTypes.health,
      ],
      notificationTitle: sportMode,
      notificationText: '00:00 • 0.00km',
      callback: workoutTaskEntryPoint,
    );

    // ── 8. BLE Auto-reconnect ke smartwatch terakhir ───────────────────────
    _subscribeWatchState();
    unawaited(WatchService.instance.autoConnect());

    // ── 9. [BUG-5 FIX] Acquire native WakeLock agar GPS tetap jalan saat layar mati ──
    // flutter_foreground_task.allowWakeLock tidak cukup di Samsung OneUI/Xiaomi MIUI.
    try {
      const mlChannel = MethodChannel('com.ibnutify.ml/audio');
      await mlChannel.invokeMethod('acquireWakeLock');
      debugPrint('[WorkoutNotifier] Native WakeLock acquired');
    } catch (e) {
      debugPrint('[WorkoutNotifier] WakeLock acquire failed (non-fatal): $e');
    }

    return true;
  }


  /// Subscribe ke WatchService untuk sinkronisasi HR ke state dan task isolate.
  void _subscribeWatchState() {
    // Watch connection state → update isWatchConnected
    _watchStateSub?.cancel();
    _watchStateSub = WatchService.instance.stateStream.listen((ws) {
      state = state.copyWith(
        isWatchConnected: ws.isConnected,
        watchDeviceName: ws.deviceName,
      );
      if (!ws.isConnected) {
        state = state.copyWith(heartRateBpm: 0);
      }
    });

    // HR stream → update state + forward ke task isolate
    _hrSub?.cancel();
    _hrSub = WatchService.instance.hrStream.listen((bpm) {
      if (!state.isRunning) return;
      final newHistory = [...state.hrHistory, bpm];
      if (newHistory.length > 120) newHistory.removeAt(0); // keep 2h of data
      state = state.copyWith(
        heartRateBpm: bpm,
        currentHrZone: classifyHrZone(bpm),
        hrHistory: newHistory,
      );
      // Forward HR ke task isolate untuk notifikasi dan kalori
      FlutterForegroundTask.sendDataToTask({'cmd': 'heartRate', 'bpm': bpm});
    });
  }

  /// Handler posisi GPS dari main isolate (foreground streaming langsung)
  void _onMainGpsPosition(Position pos) {
    if (!state.isRunning || state.isPaused) return;

    final accuracy = pos.accuracy;
    final speedMs = pos.speed < 0 ? 0.0 : pos.speed;

    // Abaikan posisi dengan akurasi sangat buruk (> 100 meter)
    if (accuracy > 100.0) {
      state = state.copyWith(
        currentSpeedMs: speedMs,
        gpsAccuracy: accuracy,
      );
      return;
    }

    final newPoint = LatLngPoint(pos.latitude, pos.longitude);
    double newDist = state.distanceKm;

    if (_lastKnownPoint != null) {
      final dKm = LocationService.haversineDistance(
        _lastKnownPoint!.lat,
        _lastKnownPoint!.lng,
        newPoint.lat,
        newPoint.lng,
      );
      // Valid step/movement: minimal 2 meter (0.002 km) dan maksimal 500 meter (anti-teleport)
      if (dKm >= 0.002 && dKm < 0.5) {
        newDist += dKm;
        _lastKnownPoint = newPoint;
        _routePoints.add(newPoint);
      }
    } else {
      _lastKnownPoint = newPoint;
      _routePoints.add(newPoint);
    }

    state = state.copyWith(
      distanceKm: newDist,
      currentSpeedMs: speedMs,
      gpsAccuracy: accuracy,
      routePoints: List.unmodifiable(_routePoints),
    );

    // Forward koordinat ke task isolate agar background isolate & notifikasi tetap sinkron
    FlutterForegroundTask.sendDataToTask({
      'cmd': 'mainGpsPosition',
      'lat': pos.latitude,
      'lng': pos.longitude,
      'speed': speedMs,
      'accuracy': accuracy,
      'altitude': pos.altitude,
    });
  }

  /// Callback dipanggil setiap detik oleh task isolate via FlutterForegroundTask
  void _onTaskData(Object data) {
    if (data is! Map) return;
    final type = data['type'] as String?;
    if (type != 'workoutUpdate') return;

    final isFinal = data['isFinal'] as bool? ?? false;
    final elapsedSecs = data['elapsedSeconds'] as int? ?? state.elapsedSeconds;
    final distKm = (data['distanceKm'] as num?)?.toDouble() ?? state.distanceKm;
    final speedMs = (data['currentSpeedMs'] as num?)?.toDouble() ?? state.currentSpeedMs;
    final accuracy = (data['gpsAccuracy'] as num?)?.toDouble() ?? state.gpsAccuracy;
    final isPaused = data['isPaused'] as bool? ?? state.isPaused;
    final lastLat = (data['lastLat'] as num?)?.toDouble();
    final lastLng = (data['lastLng'] as num?)?.toDouble();
    final routeLength = data['routeLength'] as int? ?? 0;

    // Sensor fusion data dari task isolate
    final stepCount = data['stepCount'] as int? ?? state.stepCount;
    final cadenceSpm = (data['cadenceSpm'] as num?)?.toDouble() ?? state.cadenceSpm;
    final detectedActivity = data['detectedActivity'] as String? ?? state.detectedActivity;
    final elevationGainM = (data['elevationGainM'] as num?)?.toDouble() ?? state.elevationGainM;
    final elevationLossM = (data['elevationLossM'] as num?)?.toDouble() ?? state.elevationLossM;
    final currentAltM = (data['currentAltitudeM'] as num?)?.toDouble() ?? state.currentAltitudeM;
    final calories = (data['estimatedCalories'] as num?)?.toDouble() ?? state.estimatedCalories;

    // Sync route points dari task isolate ke main isolate jika task isolate memiliki titik baru
    if (lastLat != null && lastLng != null) {
      final newPoint = LatLngPoint(lastLat, lastLng);
      if (_lastKnownPoint == null ||
          _lastKnownPoint!.lat != newPoint.lat ||
          _lastKnownPoint!.lng != newPoint.lng) {
        if (_routePoints.length < routeLength) {
          _lastKnownPoint = newPoint;
          _routePoints.add(newPoint);
        }
      }
    }

    if (isFinal) {
      final routeJson = data['routePoints'] as String?;
      if (routeJson != null) {
        try {
          final decoded = jsonDecode(routeJson) as List;
          _routePoints
            ..clear()
            ..addAll(decoded.map((e) {
              final lat = (e['lat'] as num).toDouble();
              final lng = (e['lng'] as num).toDouble();
              return LatLngPoint(lat, lng);
            }));
        } catch (_) {}
      }
      _finalStateCompleter?.complete({
        'elapsedSeconds': elapsedSecs,
        'distanceKm': distKm,
        'stepCount': stepCount,
        'elevationGainM': elevationGainM,
        'estimatedCalories': calories,
      });
      return;
    }

    // Update state UI setiap detik (gunakan nilai elapsedSecs dan distanceKm terbesar dari task isolate atau local state)
    final syncedElapsedSecs = math.max(elapsedSecs, state.elapsedSeconds);
    final syncedDist = math.max(distKm, state.distanceKm);

    state = state.copyWith(
      elapsedSeconds: syncedElapsedSecs,
      distanceKm: syncedDist,
      currentSpeedMs: speedMs > 0 ? speedMs : state.currentSpeedMs,
      gpsAccuracy: accuracy > 0 ? accuracy : state.gpsAccuracy,
      isPaused: isPaused,
      routePoints: List.unmodifiable(_routePoints),
      stepCount: stepCount,
      cadenceSpm: cadenceSpm,
      detectedActivity: detectedActivity,
      elevationGainM: elevationGainM,
      elevationLossM: elevationLossM,
      currentAltitudeM: currentAltM,
      estimatedCalories: calories,
    );
  }

  void pauseWorkout() {
    state = state.copyWith(isPaused: true);
    // Kirim command pause ke task isolate
    FlutterForegroundTask.sendDataToTask({'cmd': 'pause'});
    // Pause musik
    final playerState = ref.read(playerProvider);
    if (playerState.isPlaying) {
      ref.read(playerProvider.notifier).togglePlay();
    }
  }

  void resumeWorkout() {
    state = state.copyWith(isPaused: false);
    // Kirim command resume ke task isolate
    FlutterForegroundTask.sendDataToTask({'cmd': 'resume'});
    // Resume musik
    final playerState = ref.read(playerProvider);
    if (!playerState.isPlaying) {
      ref.read(playerProvider.notifier).togglePlay();
    }
  }

  Future<WorkoutState> stopWorkout() async {
    // Stop local timer & GPS tracking di main isolate
    _localTimer?.cancel();
    _localTimer = null;
    await _mainLocationSub?.cancel();
    _mainLocationSub = null;
    await LocationService.instance.stopTracking();

    // Ambil snapshot state saat ini sebelum di-reset
    final currentState = state;

    // Kirim command stop ke task isolate → task akan kirim final state
    _finalStateCompleter = Completer<Map<String, dynamic>>();
    FlutterForegroundTask.sendDataToTask({'cmd': 'stop'});

    // Tunggu final state dari task isolate (max 3 detik)
    Map<String, dynamic>? finalData;
    try {
      finalData = await _finalStateCompleter!.future.timeout(
        const Duration(seconds: 3),
      );
    } catch (_) {
      // Timeout — gunakan state terakhir yang kita punya
      finalData = null;
    }

    // Stop foreground service
    unawaited(FlutterForegroundTask.stopService());

    // Cleanup
    if (_taskDataCallback != null) {
      FlutterForegroundTask.removeTaskDataCallback(_taskDataCallback!);
      _taskDataCallback = null;
    }
    await _songTrackingSub?.cancel();
    _songTrackingSub = null;
    await _hrSub?.cancel();
    _hrSub = null;
    await _watchStateSub?.cancel();
    _watchStateSub = null;
    await FlutterForegroundTask.clearAllData();

    // Buat snapshot final dengan data terlengkap
    final finalElapsed = finalData?['elapsedSeconds'] as int? ?? currentState.elapsedSeconds;
    final finalDist = (finalData?['distanceKm'] as num?)?.toDouble() ?? currentState.distanceKm;
    final finalSteps = finalData?['stepCount'] as int? ?? currentState.stepCount;
    final finalElevGain = (finalData?['elevationGainM'] as num?)?.toDouble() ?? currentState.elevationGainM;
    final finalCalories = (finalData?['estimatedCalories'] as num?)?.toDouble() ?? currentState.estimatedCalories;
    final finalRoute = List<LatLngPoint>.unmodifiable(_routePoints);

    final snapshot = currentState.copyWith(
      elapsedSeconds: finalElapsed,
      distanceKm: finalDist,
      routePoints: finalRoute,
      isRunning: false,
      stepCount: finalSteps,
      elevationGainM: finalElevGain,
      estimatedCalories: finalCalories,
    );

    // Disconnect watch gracefully
    unawaited(WatchService.instance.disconnect());

    // [BUG-5 FIX] Release native WakeLock saat workout selesai
    try {
      const mlChannel = MethodChannel('com.ibnutify.ml/audio');
      await mlChannel.invokeMethod('releaseWakeLock');
      debugPrint('[WorkoutNotifier] Native WakeLock released');
    } catch (e) {
      debugPrint('[WorkoutNotifier] WakeLock release failed (non-fatal): $e');
    }

    // Reset state
    _routePoints.clear();
    _lastKnownPoint = null;
    state = const WorkoutState();

    return snapshot;
  }


  Future<void> saveActivity(WorkoutState snapshot) async {
    final activity = snapshot.toActivity();
    await DatabaseHelper.instance.insertActivity(activity.toMap());
    ref.invalidate(activitiesProvider);
    // Sync ke Android Health Connect (silent fail jika tidak tersedia)
    unawaited(HealthConnectService.instance.writeWorkout(activity));
  }
}

final workoutProvider =
    NotifierProvider<WorkoutNotifier, WorkoutState>(WorkoutNotifier.new);

// ─── Watch Provider ───────────────────────────────────────────────────────────

/// Provides current WatchState for UI (connection status, device name, battery).
final watchStateProvider = StreamProvider<WatchState>((ref) {
  return WatchService.instance.stateStream;
});

/// Provides current heart rate from BLE watch as a stream.
final watchHrProvider = StreamProvider<int>((ref) {
  return WatchService.instance.hrStream;
});

// ─── Activities Provider ──────────────────────────────────────────────────────

final activitiesProvider = FutureProvider<List<ActivityModel>>((ref) async {
  final maps = await DatabaseHelper.instance.getAllActivities();
  return maps.map(ActivityModel.fromMap).toList();
});
