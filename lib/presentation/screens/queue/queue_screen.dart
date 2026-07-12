import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/song_model.dart';
import '../../providers/app_providers.dart';
import '../../widgets/common/song_artwork_widget.dart';

/// Queue Screen — shows current song and the draggable next-in-queue list.
class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerProvider);
    final currentSong = playerState.currentSong;
    // Full queue (includes current song); next songs start after current.
    final fullQueue = playerState.queue;

    // The index of the current song in the queue
    final currentIdx = fullQueue.indexWhere((s) => s.id == currentSong?.id);
    // Songs that come AFTER the current one
    final nextSongs = currentIdx >= 0
        ? fullQueue.sublist(currentIdx + 1)
        : fullQueue.where((s) => s.id != currentSong?.id).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: AppColors.onSurface, size: 24),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text(
                        'Queue',
                        style: TextStyle(
                          color: AppColors.onSurface,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            const Divider(color: Colors.white10, height: 1),

            // ── Now Playing section (static, non-reorderable) ───────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 10),
                    child: Text(
                      'NOW PLAYING',
                      style: TextStyle(
                        color: AppColors.onSurfaceVariant,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  if (currentSong != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppColors.primary.withOpacity(0.25)),
                      ),
                      child: Row(
                        children: [
                          Stack(
                            children: [
                              SongArtworkWidget(
                                  song: currentSong, size: 48, borderRadius: 6),
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.4),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Icon(
                                  Icons.graphic_eq_rounded,
                                  color: AppColors.primary,
                                  size: 22,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  currentSong.title,
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  currentSong.artist,
                                  style: const TextStyle(
                                    color: AppColors.onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── NEXT IN QUEUE header ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text(
                    'NEXT IN QUEUE',
                    style: TextStyle(
                      color: AppColors.onSurfaceVariant,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                  const Spacer(),
                  if (nextSongs.isNotEmpty)
                    TextButton(
                      onPressed: () {
                        ref.read(playerProvider.notifier).clearQueue();
                        Navigator.of(context).pop();
                      },
                      child: const Text(
                        'CLEAR',
                        style: TextStyle(
                          color: AppColors.onSurfaceVariant,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // ── Reorderable next-in-queue list ────────────────────────────
            Expanded(
              child: nextSongs.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.queue_music_rounded,
                                color: AppColors.onSurfaceVariant, size: 48),
                            SizedBox(height: 16),
                            Text(
                              'Queue is empty',
                              style: TextStyle(
                                color: AppColors.onSurfaceVariant,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Tap a song to start playing',
                              style: TextStyle(
                                color: AppColors.onSurfaceVariant,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ReorderableListView.builder(
                      padding:
                          const EdgeInsets.only(top: 4, bottom: 120),
                      itemCount: nextSongs.length,
                      // Offset: reorder uses absolute queue indices.
                      // Next songs start at currentIdx + 1 in fullQueue.
                      onReorder: (oldRel, newRel) {
                        final offset = currentIdx + 1;
                        ref
                            .read(playerProvider.notifier)
                            .reorderQueue(oldRel + offset, newRel + offset);
                      },
                      itemBuilder: (ctx, i) {
                        final song = nextSongs[i];
                        return _QueueTile(
                          key: ValueKey(song.id),
                          song: song,
                          onTap: () {
                            ref
                                .read(playerProvider.notifier)
                                .playSong(song, fullQueue);
                            Navigator.of(context).pop();
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueueTile extends StatelessWidget {
  final SongModel song;
  final VoidCallback onTap;

  const _QueueTile({super.key, required this.song, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
        child: Row(
          children: [
            // Drag handle — shown automatically by ReorderableListView
            const Icon(Icons.drag_handle_rounded,
                color: AppColors.onSurfaceVariant, size: 18),
            const SizedBox(width: 8),
            SongArtworkWidget(song: song, size: 48, borderRadius: 6),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    style: const TextStyle(
                      color: AppColors.onSurface,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    song.artist,
                    style: const TextStyle(
                      color: AppColors.onSurfaceVariant,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
