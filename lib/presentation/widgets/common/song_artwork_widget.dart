import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/song_model.dart';
import '../../providers/app_providers.dart';

/// Cached artwork widget — queries native album art once and caches in memory
class SongArtworkWidget extends ConsumerStatefulWidget {
  final SongModel song;
  final double size;
  final double borderRadius;
  final BoxFit fit;

  const SongArtworkWidget({
    super.key,
    required this.song,
    required this.size,
    this.borderRadius = 8,
    this.fit = BoxFit.cover,
  });

  @override
  ConsumerState<SongArtworkWidget> createState() => _SongArtworkWidgetState();
}

class _SongArtworkWidgetState extends ConsumerState<SongArtworkWidget> {
  Uint8List? _artworkBytes;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadArtwork();
  }

  @override
  void didUpdateWidget(SongArtworkWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id) {
      setState(() {
        _artworkBytes = null;
        _loaded = false;
      });
      _loadArtwork();
    }
  }

  Future<void> _loadArtwork() async {
    final repo = ref.read(musicRepositoryProvider);
    final bytes = await repo.queryArtwork(widget.song.id);
    if (mounted) {
      setState(() {
        _artworkBytes = bytes != null ? Uint8List.fromList(bytes) : null;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: _loaded
            ? (_artworkBytes != null && _artworkBytes!.isNotEmpty
                ? Image.memory(
                    _artworkBytes!,
                    fit: widget.fit,
                    errorBuilder: (_, __, ___) => _placeholder(),
                  )
                : _placeholder())
            : Container(color: AppColors.surfaceContainerHigh),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: AppColors.surfaceContainerHigh,
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          color: AppColors.primary.withOpacity(0.6),
          size: widget.size * 0.38,
        ),
      ),
    );
  }
}
