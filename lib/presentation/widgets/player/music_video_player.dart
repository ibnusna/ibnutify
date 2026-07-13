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
  final YoutubeExplode _yt = YoutubeExplode();
  bool _isPlayerReady = false;
  bool _isLoading = true;
  bool _isSeeking = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
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
      
      // Get all muxed streams and sort by video quality (ascending/descending doesn't matter since we search manually)
      final sortedStreams = manifest.muxed.sortByVideoQuality().toList();
      
      MuxedStreamInfo? streamInfo;
      // Prefer 360p or 480p for stable playback
      for (var stream in sortedStreams) {
        final h = stream.videoResolution.height;
        if (h == 360 || h == 480) {
          streamInfo = stream;
          break; // Found stable resolution
        }
      }
      
      // Fallback: If 360/480 not found, pick the lowest to guarantee no lag
      streamInfo ??= sortedStreams.isNotEmpty ? sortedStreams.first : manifest.muxed.withHighestBitrate();

      _controller = VideoPlayerController.network(
        streamInfo.url.toString(),
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
      return Center(
        child: Text(
          'Failed to load video:\n$_errorMessage',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }

    ref.listen(playerProvider, (prev, next) {
      if (!_isPlayerReady || _controller == null || _isSeeking) return;

      // Sync play/pause
      if (next.isPlaying && !_controller!.value.isPlaying) {
        _controller!.play();
      } else if (!next.isPlaying && _controller!.value.isPlaying) {
        _controller!.pause();
      }
      
      // Sync position if out of sync by > 2000 ms
      final ytPosition = _controller!.value.position;
      final diff = (ytPosition.inMilliseconds - next.position.inMilliseconds).abs();
      
      if (diff > 2000) {
        _isSeeking = true;
        _controller!.seekTo(next.position).then((_) {
          _isSeeking = false;
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
