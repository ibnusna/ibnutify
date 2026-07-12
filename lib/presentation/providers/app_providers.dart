import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:ibnutify/data/datasources/music_local_datasource.dart';
import 'package:ibnutify/data/datasources/gemini_datasource.dart';
import 'package:ibnutify/data/repositories/music_repository.dart';
import 'package:ibnutify/data/models/song_model.dart';
import 'package:ibnutify/data/models/playlist_model.dart';
import 'package:ibnutify/services/audio_handler.dart';
import 'package:ibnutify/services/album_art_service.dart';
import 'package:ibnutify/services/ml_service.dart';
import 'package:ibnutify/services/download_service.dart';
import 'package:ibnutify/services/smart_shuffle_service.dart';

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
    await refresh();
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

  const PlayerState({
    this.currentSong,
    this.queue = const [],
    this.isPlaying = false,
    this.isShuffle = false,
    this.repeatMode = RepeatMode.off,
    this.position = Duration.zero,
    this.duration = Duration.zero,
  });

  PlayerState copyWith({
    SongModel? currentSong,
    List<SongModel>? queue,
    bool? isPlaying,
    bool? isShuffle,
    RepeatMode? repeatMode,
    Duration? position,
    Duration? duration,
  }) {
    return PlayerState(
      currentSong: currentSong ?? this.currentSong,
      queue: queue ?? this.queue,
      isPlaying: isPlaying ?? this.isPlaying,
      isShuffle: isShuffle ?? this.isShuffle,
      repeatMode: repeatMode ?? this.repeatMode,
      position: position ?? this.position,
      duration: duration ?? this.duration,
    );
  }
}

class PlayerNotifier extends Notifier<PlayerState> {
  int? _trackingId;
  Duration _lastDur = Duration.zero;
  bool _playLogRecorded = false;

  @override
  PlayerState build() {
    final handler = ref.read(audioHandlerProvider);

    handler.positionStream.listen((pos) {
      state = state.copyWith(position: pos);
    });

    handler.durationStream.listen((dur) {
      if (dur != null) {
        state = state.copyWith(duration: dur);
        _lastDur = dur;
      }
    });

    handler.playbackState.listen((ps) {
      state = state.copyWith(isPlaying: ps.playing);
    });

    handler.mediaItem.listen((item) {
      if (item != null) {
        final songId = item.extras?['songId'] as int?;
        if (songId != null) {
          // Log current song before switching if it was tracking
          _recordPlayLogIfNeeded();

          // Reset tracking for new song
          _trackingId = songId;
          _playLogRecorded = false;
          _syncCurrentSongFromCache(songId);
        }
      }
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

  void _recordPlayLogIfNeeded() {
    if (_trackingId == null || _playLogRecorded || _lastDur.inMilliseconds <= 0) return;
    
    // We only record log when song finishes or user skips (changes song)
    final repo = ref.read(musicRepositoryProvider);
    final playedSecs = state.position.inSeconds;
    final totalSecs = _lastDur.inSeconds;
    
    repo.recordPlayLog(_trackingId!, playedSecs, totalSecs);
    _playLogRecorded = true;
    
    // Refresh dependencies implicitly
    ref.invalidate(recentlyPlayedProvider);
    ref.invalidate(topSongsProvider);
  }

  Future<void> playSong(SongModel song, List<SongModel> queue) async {
    final handler = ref.read(audioHandlerProvider);
    final repo = ref.read(musicRepositoryProvider);
    final datasource = ref.read(musicLocalDatasourceProvider);

    // Resolve artUri lagu aktif SEBELUM playQueue — notifikasi langsung punya cover.
    final artUri = await AlbumArtService.instance.getArtworkUri(song.id, datasource);

    // Bangun queue, patch lagu aktif dengan artUri yang sudah resolved.
    final mediaItems = queue.map((s) {
      final item = _toMediaItemSync(s);
      if (s.id == song.id && artUri != null) {
        return item.copyWith(artUri: artUri);
      }
      return item;
    }).toList();

    final index = queue.indexWhere((s) => s.id == song.id);
    final safeIndex = index < 0 ? 0 : index;

    await handler.playQueue(mediaItems, initialIndex: safeIndex);

    await repo.incrementPlayCount(song.id);
    _trackingId = song.id;
    _playLogRecorded = false;

    state = state.copyWith(
      currentSong: song,
      queue: queue,
    );

    // Update artwork sisa queue di background.
    _fetchAndSendArtwork(queue, handler);
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
      await handler.play();
    }
  }

  Future<void> nextTrack() async {
    final handler = ref.read(audioHandlerProvider);
    _recordPlayLogIfNeeded();
    await handler.skipToNext();
    _pushArtworkForCurrentSong(handler);
  }

  Future<void> previousTrack() async {
    final handler = ref.read(audioHandlerProvider);
    _recordPlayLogIfNeeded();
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
      
      await handler.updateShuffleIndices(newIndices);
    }

    await handler.setShuffleMode(
      newShuffle
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none,
    );

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

  Future<void> clearQueue() async {
    final handler = ref.read(audioHandlerProvider);
    _recordPlayLogIfNeeded();
    await handler.clearQueue();
    state = state.copyWith(
      queue: const [],
      currentSong: null,
      isPlaying: false,
      position: Duration.zero,
      duration: Duration.zero,
    );
    _trackingId = null;
    _playLogRecorded = false;
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

final searchResultsProvider = FutureProvider<List<SongModel>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  final repo = ref.watch(musicRepositoryProvider);
  return await repo.searchSongs(query);
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
  final List<AIChatMessage> messages;
  final bool isLoading;
  final List<SongModel>? pendingSongs;
  final String? pendingPlaylistName;

  const AIChatState({
    this.messages = const [],
    this.isLoading = false,
    this.pendingSongs,
    this.pendingPlaylistName,
  });

  AIChatState copyWith({
    List<AIChatMessage>? messages,
    bool? isLoading,
    List<SongModel>? pendingSongs,
    String? pendingPlaylistName,
    bool clearPending = false,
  }) {
    return AIChatState(
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
      messages: [
        const AIChatMessage(
          role: ChatRole.ai,
          content:
              'Halo! Saya IbnuTify AI.\n'
              'Ceritakan mood kamu atau lagu seperti apa yang kamu butuhkan sekarang?\n'
              'Contoh: "Lagi stres ngoding, butuh lagu yang menenangkan."',
        ),
      ],
    );
  }

  Future<void> sendMessage(String input) async {
    if (input.trim().isEmpty || state.isLoading) return;

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

    state = state.copyWith(
      messages: [...state.messages, aiMsg],
      isLoading: false,
      pendingSongs: aiMsg.recommendedSongs,
      pendingPlaylistName: aiMsg.pendingPlaylistName,
    );
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

  void clearChat() => state = build();
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

final duplicateSongsProvider = FutureProvider<Map<String, List<SongModel>>>((ref) async {
  ref.watch(songsProvider);
  return await ref.read(musicRepositoryProvider).getDuplicateSongs();
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
  
  final Map<int, List<SongModel>> clusters = {};
  for (var song in songs) {
    if (song.clusterId != null) {
      clusters.putIfAbsent(song.clusterId!, () => []).add(song);
    }
  }
  
  final List<NamedPlaylist> list = [];
  for (int i = 0; i < 7; i++) {
    final clusterSongs = clusters[i] ?? [];
    if (clusterSongs.isNotEmpty) {
      list.add(NamedPlaylist(
        id: 'daily_mix_$i',
        name: 'Daily Mix ${dayNames[i]}',
        description: dayDescriptions[i],
        songs: clusterSongs,
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

  const DownloadState({
    this.awaitingUrl = false,
    this.isDownloading = false,
    this.progress = const DownloadProgress(),
    this.messages = const [],
  });

  DownloadState copyWith({
    bool? awaitingUrl,
    bool? isDownloading,
    DownloadProgress? progress,
    List<DownloadChatMessage>? messages,
  }) {
    return DownloadState(
      awaitingUrl: awaitingUrl ?? this.awaitingUrl,
      isDownloading: isDownloading ?? this.isDownloading,
      progress: progress ?? this.progress,
      messages: messages ?? this.messages,
    );
  }
}

class DownloadNotifier extends Notifier<DownloadState> {
  Timer? _pollTimer;

  @override
  DownloadState build() => const DownloadState();

  /// User menekan chip "Download Music" — masuk mode menunggu URL.
  void requestUrl() {
    final botMsg = DownloadChatMessage(
      content: '**Download Music**\n\n'
          'Oke! Paste link Spotify kamu di sini ya.\n'
          'Format yang didukung:\n'
          '`https://open.spotify.com/track/...`\n\n'
          'Lagu akan disimpan di:\n'
          '`Download/Ibnutify/`',
    );
    state = state.copyWith(
      awaitingUrl: true,
      messages: [...state.messages, botMsg],
    );
  }

  /// User mengirim teks saat mode awaitingUrl — langsung proses sebagai URL.
  Future<void> handleUserInput(String input) async {
    if (!DownloadService.isSpotifyTrackUrl(input)) {
      final errMsg = DownloadChatMessage(
        content: '**URL tidak valid.**\n\nMasukkan link Spotify track yang benar.\n'
            'Contoh: `https://open.spotify.com/track/6xrP29Jvv...`',
      );
      state = state.copyWith(messages: [...state.messages, errMsg]);
      return;
    }

    final fetchingMsg = DownloadChatMessage(
      content: 'Mencari informasi lagu dari Spotify...',
    );
    state = state.copyWith(
      awaitingUrl: false,
      messages: [...state.messages, fetchingMsg],
    );

    // Ambil metadata dulu untuk preview
    final service = DownloadService.instance;
    final meta = await service.getTrackMetadata(input);

    if (meta != null) {
      final previewMsg = DownloadChatMessage(
        content: '**${meta.title}**\n'
            'Artist: ${meta.artist}\n'
            'Album: ${meta.album}${meta.year.isNotEmpty ? ' (${meta.year})' : ''}'
            '${meta.genre.isNotEmpty ? '\nGenre: ${meta.genre}' : ''}\n\n'
            'Memulai proses unduhan...',
      );
      state = state.copyWith(messages: [...state.messages, previewMsg]);
    } else {
      final startMsg = DownloadChatMessage(
        content: 'Memulai unduhan...',
      );
      state = state.copyWith(messages: [...state.messages, startMsg]);
    }

    final progressMsg = DownloadChatMessage(
      content: 'Menghubungi YouTube...',
      isProgress: true,
      progress: const DownloadProgress(),
    );
    final msgs = [...state.messages, progressMsg];
    state = state.copyWith(isDownloading: true, messages: msgs);

    // Start download di background + polling timer
    _startPolling();

    final result = await service.downloadTrack(input);
    _stopPolling();

    // Trigger local scan if successfully downloaded new song
    if (result.success && result.status != 'skipped') {
      ref.read(songsProvider.notifier).scanDeviceSongs();
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
    } else {
      resultMsg = DownloadChatMessage(
        content: '**Unduhan gagal**\n\n${result.error}\n\n'
            'Coba lagi dengan link Spotify yang berbeda.',
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
        final eta = p.etaDisplay.isNotEmpty ? ' — ETA: ${p.etaDisplay}' : '';
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
    state = const DownloadState();
  }
}

final downloadProvider =
    NotifierProvider<DownloadNotifier, DownloadState>(DownloadNotifier.new);
