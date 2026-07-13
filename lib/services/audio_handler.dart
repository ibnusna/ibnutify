import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ibnutify/services/smart_shuffle_order.dart';

/// AudioHandler yang menjembatani just_audio dengan sistem notifikasi media Android.
///
/// Perbaikan notifikasi vs versi sebelumnya:
///
/// 1. FORCE-EMIT mediaItem sebelum dan sesudah setAudioSource — mengatasi
///    race condition di mana currentIndexStream tidak fire untuk initialIndex=0.
///
/// 2. playQueue() TIDAK menunggu artwork — metadata teks (title, artist, duration)
///    langsung tampil di notifikasi, artwork diupdate asinkron di background.
///
/// 3. _updateArtworkAsync() meng-patch MediaItem di queue + re-emit mediaItem
///    untuk lagu aktif setelah artwork siap.
///
/// 4. Hanya currentIndexStream yang update mediaItem (bukan sequenceStateStream)
///    untuk mencegah metadata-flip saat pause.
class IbnuTifyAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final AudioPlayer _player = AudioPlayer(
    handleInterruptions: false,
    handleAudioSessionActivation: false,
  );
  ConcatenatingAudioSource? _audioSource;
  final Map<int, String> _artworksCache = {};
  
  SmartShuffleOrder _smartShuffleOrder = SmartShuffleOrder();

  int _manualQueueCount = 0;
  int _lastIndex = -1;

  IbnuTifyAudioHandler() {
    // Pipe playbackState (seekbar, controls) ke audio_service
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);

    // currentIndexStream → sole authority untuk update mediaItem
    _player.currentIndexStream.listen(_onIndexChanged);

    // sequenceStateStream → HANYA update queue list, TIDAK update mediaItem
    _player.sequenceStateStream.listen((state) {
      if (state == null) return;
      queue.add(
        state.effectiveSequence.map((s) {
          var item = s.tag as MediaItem;
          final songId = item.extras?['songId'] as int?;
          if (songId != null && _artworksCache.containsKey(songId)) {
            item = item.copyWith(artUri: Uri.file(_artworksCache[songId]!));
          }
          return item;
        }).toList(),
      );
    });
  }

  // ─── Internal helpers ──────────────────────────────────────────────────────

  void _onIndexChanged(int? index) {
    if (index == null) return;
    
    if (_lastIndex != -1 && index > _lastIndex) {
      final diff = index - _lastIndex;
      _manualQueueCount = (_manualQueueCount - diff).clamp(0, 9999);
    }
    _lastIndex = index;

    final seq = _player.sequenceState;
    if (seq == null || seq.sequence.isEmpty) return;
    if (index >= seq.sequence.length) return;
    var item = seq.sequence[index].tag as MediaItem;
    final songId = item.extras?['songId'] as int?;
    if (songId != null && _artworksCache.containsKey(songId)) {
      item = item.copyWith(artUri: Uri.file(_artworksCache[songId]!));
    }
    mediaItem.add(item);
  }

  void _forceEmitFromSources(int index, List<UriAudioSource> sources) {
    if (index >= sources.length) return;
    var item = sources[index].tag as MediaItem?;
    if (item != null) {
      final songId = item.extras?['songId'] as int?;
      if (songId != null && _artworksCache.containsKey(songId)) {
        item = item.copyWith(artUri: Uri.file(_artworksCache[songId]!));
      }
      mediaItem.add(item);
    }
  }

  // ─── Playback Controls ─────────────────────────────────────────────────────

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    return super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    await _player.seekToNext();
    _onIndexChanged(_player.currentIndex);
  }

  @override
  Future<void> skipToPrevious() async {
    await _player.seekToPrevious();
    _onIndexChanged(_player.currentIndex);
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    await _player.seek(Duration.zero, index: index);
    _onIndexChanged(index);
    await _player.play();
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    await _player.setShuffleModeEnabled(
      shuffleMode == AudioServiceShuffleMode.all,
    );
    super.setShuffleMode(shuffleMode);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    final loopMode = switch (repeatMode) {
      AudioServiceRepeatMode.one => LoopMode.one,
      AudioServiceRepeatMode.all => LoopMode.all,
      _ => LoopMode.off,
    };
    await _player.setLoopMode(loopMode);
    super.setRepeatMode(repeatMode);
  }

  // ─── Queue Management ──────────────────────────────────────────────────────

  /// Memulai pemutaran queue baru.
  ///
  /// STRATEGI NOTIFIKASI STABIL:
  /// 1. emit mediaItem SEBELUM setAudioSource → notifikasi langsung update
  /// 2. setAudioSource + play() → audio mulai
  /// 3. emit lagi SETELAH setAudioSource → pastikan index ter-resolved
  /// 4. artwork diupdate asinkron di background (tidak memblokir playback)
  ///
  /// [items] harus berisi title, artist, duration, extras['uri'], extras['songId'].
  /// [artBytesMap] adalah opsional: songId → JPEG bytes untuk update art asinkron.
  Future<void> playQueue(
    List<MediaItem> items, {
    int initialIndex = 0,
    Map<int, Uint8List>? artBytesMap,
  }) async {
    _manualQueueCount = 0;
    _lastIndex = initialIndex;


    // ── Langkah 1: Emit mediaItem SEGERA sebelum audio dimuat ───────────────
    // Ini yang memastikan notifikasi menampilkan metadata yang benar
    // bahkan sebelum just_audio selesai loading.
    if (initialIndex < items.length) {
      var initialItem = items[initialIndex];
      final songId = initialItem.extras?['songId'] as int?;
      if (songId != null && _artworksCache.containsKey(songId)) {
        initialItem = initialItem.copyWith(artUri: Uri.file(_artworksCache[songId]!));
      }
      mediaItem.add(initialItem);
    }
    queue.add(items);

    // ── Langkah 2: Bangun AudioSources ──────────────────────────────────────
    final sources = items.map((item) {
      return AudioSource.uri(
        Uri.parse(item.extras!['uri'] as String),
        tag: item,
      );
    }).toList();
    
    _smartShuffleOrder = SmartShuffleOrder();

    _audioSource = ConcatenatingAudioSource(
      children: sources,
      shuffleOrder: _smartShuffleOrder,
    );

    // ── Langkah 3: Set source + play ─────────────────────────────────────────
    await _player.setAudioSource(
      _audioSource!,
      initialIndex: initialIndex,
      initialPosition: Duration.zero,
    );

    // ── Langkah 4: Force-emit lagi setelah sequence settled ──────────────────
    _forceEmitFromSources(initialIndex, sources);

    await _player.play();

    // ── Langkah 5: Update artwork di background (non-blocking) ───────────────
    if (artBytesMap != null && artBytesMap.isNotEmpty) {
      _updateArtworkInBackground(artBytesMap);
    }
  }

  /// Menyimpan artwork ke temp files dan meng-patch MediaItem di queue.
  /// Berjalan asinkron — audio tidak terganggu.
  void _updateArtworkInBackground(Map<int, Uint8List> artBytesMap) async {
    try {
      final dir = await getTemporaryDirectory();
      final src = _audioSource;
      if (src == null) return;

      // Tulis semua file artwork yang belum ada
      final pathMap = <int, String>{};
      for (final entry in artBytesMap.entries) {
        final file = File('${dir.path}/ibnutify_art_${entry.key}.jpg');
        try {
          if (!await file.exists()) {
            await file.writeAsBytes(entry.value, flush: true);
          }
          pathMap[entry.key] = file.path;
          _artworksCache[entry.key] = file.path; // Update global cache
        } catch (_) {}
      }

      // Patch queue items dengan artUri
      final currentQueue = List<MediaItem>.from(queue.value);
      bool queueChanged = false;

      for (int i = 0; i < currentQueue.length; i++) {
        final item = currentQueue[i];
        final songId = item.extras?['songId'] as int?;
        if (songId == null) continue;
        final path = pathMap[songId];
        if (path == null) continue;
        if (item.artUri?.toFilePath() == path) continue; // already updated

        final updated = item.copyWith(artUri: Uri.file(path));
        currentQueue[i] = updated;
        queueChanged = true;

        // Re-emit mediaItem jika ini lagu yang sedang diputar
        final curIdx = _player.currentIndex;
        if (curIdx == i) {
          mediaItem.add(updated);
        }
      }

      if (queueChanged) queue.add(currentQueue);
    } catch (_) {
      // Artwork update gagal — text metadata tetap tampil, tidak crash
    }
  }

  /// Menghapus queue dan menghentikan pemutaran.
  Future<void> clearQueue() async {
    await _player.stop();
    _audioSource = null;
    _manualQueueCount = 0;
    _lastIndex = -1;

    queue.add([]);
    mediaItem.add(null);
  }

  /// Memasukkan lagu ke antrean (Add to Queue) setelah lagu yang sedang diputar
  /// dan lagu-lagu antrean manual lainnya.
  Future<void> addNextToQueue(MediaItem item) async {
    final src = _audioSource;
    if (src == null) return;
    
    final currentIndex = _player.currentIndex;
    final insertIndex = currentIndex == null 
        ? src.length 
        : currentIndex + 1 + _manualQueueCount;
        
    final safeIndex = insertIndex > src.length ? src.length : insertIndex;
    
    final audioSource = AudioSource.uri(
      Uri.parse(item.extras!['uri'] as String),
      tag: item,
    );
    
    await src.insert(safeIndex, audioSource);
    _manualQueueCount++;
  }

  /// Memindahkan item queue dari [oldIndex] ke [newIndex].
  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    final src = _audioSource;
    if (src == null) return;
    await src.move(oldIndex, newIndex);
    // sequenceStateStream akan fire dan update queue BehaviorSubject otomatis.
  }
  
  /// Mengupdate indeks shuffle secara dinamis untuk injeksi Smart Shuffle.
  Future<void> updateShuffleIndices(List<int> indices) async {
    _smartShuffleOrder.updateIndices(indices);
    // Instruct just_audio to apply the new shuffle order
    await _player.shuffle();
  }

  // ─── Stream Transformation ─────────────────────────────────────────────────

  PlaybackState _transformEvent(PlaybackEvent event) {
    final playing = _player.playing;
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    );
  }

  // ─── Getters ────────────────────────────────────────────────────────────────

  /// Public entry point for artwork updates from PlayerNotifier.
  /// Delegates to [_updateArtworkInBackground].
  void updateArtwork(Map<int, Uint8List> artBytesMap) {
    _updateArtworkInBackground(artBytesMap);
  }

  AudioPlayer get player => _player;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;

  List<MediaItem> get currentQueueItems {
    final state = _player.sequenceState;
    if (state == null) return [];
    return state.effectiveSequence.map((s) => s.tag as MediaItem).toList();
  }
}
