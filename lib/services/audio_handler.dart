import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:ibnutify/data/datasources/music_local_datasource.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:path_provider/path_provider.dart';

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
  final _localDatasource = MusicLocalDatasource();
  
  // Tracking state
  int? _trackingSongId;
  int _durationPlayedSecs = 0;
  int _totalDurationSecs = 0;
  bool _hasLoggedCurrentSong = false;
  int _lastPositionSecs = 0;

  int _manualQueueCount = 0;
  int _lastIndex = -1;

  IbnuTifyAudioHandler() {
    // Synchronize playbackState (seekbar, controls, play/pause toggle) with audio_service
    _player.playbackEventStream.listen((event) => _broadcastState(event));
    _player.playerStateStream.listen((_) => _broadcastState());

    // Update mediaItem duration as soon as just_audio resolves audio duration
    _player.durationStream.listen((dur) {
      if (dur != null && mediaItem.value != null && mediaItem.value!.duration != dur) {
        mediaItem.add(mediaItem.value!.copyWith(duration: dur));
      }
    });

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

    _player.positionStream.listen((position) {
      if (_trackingSongId != null && !_hasLoggedCurrentSong) {
        final posSecs = position.inSeconds;
        // Simple accumulator to handle seeks gracefully
        if (posSecs > _lastPositionSecs && (posSecs - _lastPositionSecs) < 2) {
           _durationPlayedSecs++;
        }
        _lastPositionSecs = posSecs;
      }
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
    _handleSongChangeForTracking(item);
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
      _handleSongChangeForTracking(item);
    }
  }

  // ─── Playback Controls ─────────────────────────────────────────────────────

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    _recordPlayLogIfNeeded();
    await _player.stop();
    return super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    await _player.seekToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    await _player.seekToPrevious();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    await _player.seek(Duration.zero, index: index);
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

  Future<void> playQueue(
    List<MediaItem> items, {
    int initialIndex = 0,
    Map<int, Uint8List>? artBytesMap,
  }) async {
    _manualQueueCount = 0;
    _lastIndex = initialIndex;

    if (initialIndex < items.length) {
      var initialItem = items[initialIndex];
      final songId = initialItem.extras?['songId'] as int?;
      if (songId != null && _artworksCache.containsKey(songId)) {
        initialItem = initialItem.copyWith(artUri: Uri.file(_artworksCache[songId]!));
      }
      mediaItem.add(initialItem);
    }
    queue.add(items);

    final sources = items.map((item) {
      return AudioSource.uri(
        Uri.parse(item.extras!['uri'] as String),
        tag: item,
      );
    }).toList();
    
    _audioSource = ConcatenatingAudioSource(
      children: sources,
    );

    await _player.setAudioSource(
      _audioSource!,
      initialIndex: initialIndex,
      initialPosition: Duration.zero,
    );

    _forceEmitFromSources(initialIndex, sources);

    await _player.play();

    if (artBytesMap != null && artBytesMap.isNotEmpty) {
      _updateArtworkInBackground(artBytesMap);
    }
  }

  void _updateArtworkInBackground(Map<int, Uint8List> artBytesMap) async {
    try {
      final dir = await getTemporaryDirectory();
      final src = _audioSource;
      if (src == null) return;

      final pathMap = <int, String>{};
      for (final entry in artBytesMap.entries) {
        final file = File('${dir.path}/ibnutify_art_${entry.key}.jpg');
        try {
          if (!await file.exists()) {
            await file.writeAsBytes(entry.value, flush: true);
          }
          pathMap[entry.key] = file.path;
          _artworksCache[entry.key] = file.path;
        } catch (_) {}
      }

      final currentQueue = List<MediaItem>.from(queue.value);
      bool queueChanged = false;

      for (int i = 0; i < currentQueue.length; i++) {
        final item = currentQueue[i];
        final songId = item.extras?['songId'] as int?;
        if (songId == null) continue;
        final path = pathMap[songId];
        if (path == null) continue;
        if (item.artUri?.toFilePath() == path) continue;

        final updated = item.copyWith(artUri: Uri.file(path));
        currentQueue[i] = updated;
        queueChanged = true;

        final curIdx = _player.currentIndex;
        if (curIdx == i) {
          mediaItem.add(updated);
        }
      }

      if (queueChanged) queue.add(currentQueue);
    } catch (_) {}
  }

  Future<void> clearQueue() async {
    _recordPlayLogIfNeeded();
    await _player.stop();
    _audioSource = null;
    _manualQueueCount = 0;
    _lastIndex = -1;

    queue.add([]);
    mediaItem.add(null);
  }

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

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    final src = _audioSource;
    if (src == null) return;
    
    // Perform reorder on concatenating audio source
    await src.move(oldIndex, newIndex);
    
    // Update queue state with casted UriAudioSource elements
    queue.add(src.children.map((s) => (s as UriAudioSource).tag as MediaItem).toList());
  }

  Future<void> injectCustomQueue(List<int> optimizedIndices) async {
    final src = _audioSource;
    if (src == null || optimizedIndices.isEmpty) return;
    
    final currentChildren = List<AudioSource>.from(src.children);
    final newChildren = <AudioSource>[];
    for (int idx in optimizedIndices) {
      if (idx >= 0 && idx < currentChildren.length) {
        newChildren.add(currentChildren[idx]);
      }
    }
    
    final position = _player.position;
    final wasPlaying = _player.playing;
    
    _audioSource = ConcatenatingAudioSource(children: newChildren);
    
    await _player.setAudioSource(
      _audioSource!,
      initialIndex: 0,
      initialPosition: position,
    );
    
    if (wasPlaying) {
      _player.play();
    }
    
    queue.add(newChildren.map((s) => (s as UriAudioSource).tag as MediaItem).toList());
  }

  // ─── Play Tracking Logic ──────────────────────────────────────────────────

  void _handleSongChangeForTracking(MediaItem newItem) {
    _recordPlayLogIfNeeded();

    final songId = newItem.extras?['songId'] as int?;
    _trackingSongId = songId;
    _durationPlayedSecs = 0;
    _lastPositionSecs = 0;
    _hasLoggedCurrentSong = false;
    _totalDurationSecs = newItem.duration?.inSeconds ?? 0;

    if (songId != null) {
      _localDatasource.incrementPlayCount(songId);
    }
  }

  void _recordPlayLogIfNeeded() {
    if (_trackingSongId == null || _hasLoggedCurrentSong || _totalDurationSecs <= 0) return;
    
    if (_durationPlayedSecs > 0) {
      _localDatasource.recordPlayLog(_trackingSongId!, _durationPlayedSecs, _totalDurationSecs);
    }
    _hasLoggedCurrentSong = true;
  }

  void _broadcastState([PlaybackEvent? event]) {
    final playing = _player.playing;
    final state = PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.play,
        MediaAction.pause,
        MediaAction.playPause,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
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
      queueIndex: _player.currentIndex ?? (_lastIndex >= 0 ? _lastIndex : null),
    );
    playbackState.add(state);
  }

  // ─── Getters ────────────────────────────────────────────────────────────────

  void updateArtwork(Map<int, Uint8List> artBytesMap) {
    _updateArtworkInBackground(artBytesMap);
  }

  AudioPlayer get player => _player;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;

  List<MediaItem> get currentQueueItems {
    return queue.value;
  }
}
