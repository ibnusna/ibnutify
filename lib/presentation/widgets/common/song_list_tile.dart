import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/song_model.dart';
import '../../providers/app_providers.dart';
import '../../screens/player/player_screen.dart';
import '../common/song_artwork_widget.dart';
import '../player/more_options_sheet.dart';

/// Reusable song list tile — used in Library, Search results, Playlist screens.
class SongListTile extends ConsumerWidget {
  final SongModel song;
  final List<SongModel> queue;
  final bool showDuration;
  final Widget? trailing;
  final VoidCallback? onTap;

  const SongListTile({
    super.key,
    required this.song,
    required this.queue,
    this.showDuration = true,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerProvider);
    final currentSong = playerState.currentSong;
    final isCurrentSong = currentSong?.id == song.id;

    return InkWell(
      onTap: onTap ?? () {
        FocusManager.instance.primaryFocus?.unfocus();
        ref.read(playerProvider.notifier).playSong(song, queue);
        Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const PlayerScreen(),
            transitionsBuilder: (_, animation, __, child) => SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
              child: child,
            ),
            transitionDuration: const Duration(milliseconds: 350),
          ),
        );
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            // Artwork
            SongArtworkWidget(song: song, size: 56, borderRadius: 6),
            const SizedBox(width: 12),

            // Song info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    style: TextStyle(
                      color: isCurrentSong ? AppColors.primary : AppColors.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${song.artist} • ${song.album}',
                    style: const TextStyle(
                      color: AppColors.onSurfaceVariant,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Duration + more button
            if (showDuration)
              Text(
                _formatDuration(song.duration),
                style: const TextStyle(
                  color: AppColors.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            const SizedBox(width: 4),
            if (trailing != null)
              trailing!
            else
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(
                  Icons.more_vert_rounded,
                  color: AppColors.onSurfaceVariant,
                  size: 20,
                ),
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => MoreOptionsSheet(song: song),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(int ms) {
    final totalSecs = ms ~/ 1000;
    final mins = totalSecs ~/ 60;
    final secs = totalSecs % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }
}
