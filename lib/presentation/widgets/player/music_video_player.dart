import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/app_providers.dart';

class MusicVideoPlayer extends ConsumerStatefulWidget {
  final String youtubeUrl;

  const MusicVideoPlayer({Key? key, required this.youtubeUrl}) : super(key: key);

  @override
  ConsumerState<MusicVideoPlayer> createState() => _MusicVideoPlayerState();
}

class _MusicVideoPlayerState extends ConsumerState<MusicVideoPlayer> {
  VideoPlayerController? _controller;
  late YoutubeExplode _yt;
  bool _isPlayerReady = false;
  bool _isLoading = true;
  bool _isSeeking = false;
  bool _intendedPlayState = false;
  DateTime _lastSeekTime = DateTime.now();
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _yt = YoutubeExplode();
    _initVideo();
  }

  @override
  void didUpdateWidget(covariant MusicVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.youtubeUrl != widget.youtubeUrl) {
      _initVideo();
    }
  }

  Future<void> _initVideo() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final oldController = _controller;

      var videoId = VideoId(widget.youtubeUrl);
      var manifest = await _yt.videos.streamsClient.getManifest(videoId);
      
      // Get all muxed streams (progressive MP4/WebM with both audio/video) and sort by video quality
      final sortedStreams = manifest.muxed.sortByVideoQuality().toList();
      
      MuxedStreamInfo? streamInfoVar;
      // Prefer 360p or 480p for stable playback
      for (var stream in sortedStreams) {
        final h = stream.videoResolution.height;
        if (h == 360 || h == 480) {
          streamInfoVar = stream;
          break; // Found stable resolution
        }
      }
      
      // Fallback: If 360/480 not found, pick the lowest to guarantee no lag
      streamInfoVar ??= sortedStreams.isNotEmpty ? sortedStreams.first : manifest.muxed.withHighestBitrate();

      _controller = VideoPlayerController.network(
        streamInfoVar.url.toString(),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      
      await _controller!.initialize();
      await _controller!.setVolume(0.0); // Muted
      await _controller!.setLooping(true);

      if (mounted) {
        setState(() {
          _isPlayerReady = true;
          _isLoading = false;
        });
      }
      
      if (oldController != null) {
        await oldController.dispose();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _yt.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_errorMessage != null) {
      final isOffline = _errorMessage!.toLowerCase().contains('socket') || _errorMessage!.toLowerCase().contains('network') || _errorMessage!.toLowerCase().contains('host');
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isOffline ? Icons.wifi_off_rounded : Icons.error_outline_rounded, color: Colors.white54, size: 48),
            const SizedBox(height: 16),
            Text(
              isOffline ? 'Koneksi internet terputus.' : 'Gagal memuat video.',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            if (!isOffline)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                ),
              ),
          ],
        ),
      );
    }

    ref.listen(playerProvider, (prev, next) {
      if (!_isPlayerReady || _controller == null || _isSeeking) return;

      // Sync play/pause only if there's an actual change in intention
      if (next.isPlaying && !_intendedPlayState) {
        _intendedPlayState = true;
        _controller!.play();
      } else if (!next.isPlaying && _intendedPlayState) {
        _intendedPlayState = false;
        _controller!.pause();
      }
      // Sync position if out of sync by > 4000 ms (allows natural buffering)
      final ytPosition = _controller!.value.position;
      final diff = (ytPosition.inMilliseconds - next.position.inMilliseconds).abs();
      
      if (diff > 4000 && DateTime.now().difference(_lastSeekTime).inSeconds > 5) {
        _isSeeking = true;
        _lastSeekTime = DateTime.now();
        _controller!.seekTo(next.position).then((_) {
          _isSeeking = false;
          // Ensure it resumes playing after seek if the audio is playing
          if (ref.read(playerProvider).isPlaying) {
            _controller!.play();
          }
        });
      }
    });

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        color: Colors.black,
        child: SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _controller!.value.size.width,
              height: _controller!.value.size.height,
              child: VideoPlayer(_controller!),
            ),
          ),
        ),
      ),
    );
  }
}
