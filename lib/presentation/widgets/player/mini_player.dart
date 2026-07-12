import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../../providers/album_art_provider.dart';
import '../../screens/player/player_screen.dart';
import '../common/song_artwork_widget.dart';

/// Mini Player — appears above bottom nav when a song is playing.
/// Features Spotify-style adaptive background that reacts to album art colors.
class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key});

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  Color _fromColor = const Color(0xFF333333);
  Color _toColor = const Color(0xFF333333);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _animateTo(Color newColor) {
    _fromColor = Color.lerp(_fromColor, _toColor, _controller.value)!;
    _toColor = newColor;
    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerProvider);
    final currentSong = playerState.currentSong;

    // React to dominant color changes and animate the background
    ref.listen<AlbumArtState>(albumArtProvider, (prev, next) {
      if (prev?.dominantColor != next.dominantColor) {
        _animateTo(next.dominantColor);
      }
    });

    if (currentSong == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const PlayerScreen(),
          transitionsBuilder: (_, animation, __, child) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              )),
              child: child,
            );
          },
          transitionDuration: const Duration(milliseconds: 350),
        ),
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = Curves.easeInOut.transform(_controller.value);
          final current = Color.lerp(_fromColor, _toColor, t)!;
          final bgLeft = current.withOpacity(0.88);
          final bgRight = current.withOpacity(0.45);

          return Container(
            height: 64,
            margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [bgLeft, bgRight],
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: current.withOpacity(0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: child,
          );
        },
        child: Row(
          children: [
            // Artwork
            Padding(
              padding: const EdgeInsets.all(8),
              child: SongArtworkWidget(
                song: currentSong,
                size: 48,
                borderRadius: 6,
              ),
            ),

            // Song info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    currentSong.title,
                    style: const TextStyle(
                      color: AppColors.onSurface,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    currentSong.artist,
                    style: TextStyle(
                      color: AppColors.onSurface.withOpacity(0.7),
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Play / Pause with animated icon switch
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: IconButton(
                key: ValueKey(playerState.isPlaying),
                onPressed: () =>
                    ref.read(playerProvider.notifier).togglePlay(),
                icon: Icon(
                  playerState.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: AppColors.onSurface,
                  size: 28,
                ),
              ),
            ),

            // Next track
            IconButton(
              onPressed: () =>
                  ref.read(playerProvider.notifier).nextTrack(),
              icon: Icon(
                Icons.skip_next_rounded,
                color: AppColors.onSurface.withOpacity(0.8),
                size: 24,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
