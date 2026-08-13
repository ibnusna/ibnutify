import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/song_model.dart';
import '../../providers/app_providers.dart';
import '../workout/sport_mode_picker.dart';
import '../common/song_artwork_widget.dart';
import 'edit_song_sheet.dart';

/// Bottom sheet with options for a song — mirrors MoreOptionsSheet.tsx
class MoreOptionsSheet extends ConsumerWidget {
  final SongModel song;

  const MoreOptionsSheet({super.key, required this.song});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLiked = song.isLiked;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
            ),

            // Song header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: [
                  SongArtworkWidget(song: song, size: 48, borderRadius: 6),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          style: const TextStyle(
                            color: AppColors.onSurface,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          song.artist,
                          style: const TextStyle(
                            color: AppColors.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      isLiked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: isLiked
                          ? AppColors.primary
                          : AppColors.onSurfaceVariant,
                    ),
                    onPressed: () {
                      ref.read(songsProvider.notifier).toggleLike(song.id);
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),

            const Divider(color: Colors.white10, height: 1),

            // Options
            _OptionTile(
              icon: Icons.queue_music_rounded,
              label: 'Tambahkan ke antrean',
              onTap: () {
                Navigator.pop(context);
                ref.read(playerProvider.notifier).addToQueue(song);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '"${song.title}" ditambahkan ke antrean',
                      style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700),
                    ),
                    backgroundColor: AppColors.primary,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
            _OptionTile(
              icon: Icons.playlist_add_rounded,
              label: 'Add to playlist',
              onTap: () {
                Navigator.pop(context);
                _showAddToPlaylistSheet(context, ref, song);
              },
            ),
            _OptionTile(
              icon: Icons.copy_rounded,
              label: 'Duplicate song',
              onTap: () async {
                Navigator.pop(context);
                final copy = await ref.read(songsProvider.notifier).duplicateSong(song);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '"${copy.title}" berhasil diduplikasi',
                        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700),
                      ),
                      backgroundColor: AppColors.primary,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
            ),
            _OptionTile(
              icon: Icons.album_rounded,
              label: 'View album',
              onTap: () => Navigator.pop(context),
            ),
            _OptionTile(
              icon: Icons.person_rounded,
              label: 'View artist',
              onTap: () => Navigator.pop(context),
            ),
            _OptionTile(
              icon: Icons.share_rounded,
              label: 'Share',
              onTap: () => Navigator.pop(context),
            ),
            _OptionTile(
              icon: Icons.directions_run_rounded,
              label: 'Mulai Mode Olahraga',
              onTap: () {
                Navigator.pop(context);
                showModalBottomSheet(
                  context: context,
                  backgroundColor: Colors.transparent,
                  builder: (_) => SportModePicker(initialSong: song),
                );
              },
            ),
            _OptionTile(
              icon: Icons.edit_rounded,
              label: 'Edit Lagu',
              onTap: () {
                Navigator.pop(context);
                _showEditSongSheet(context, ref, song);
              },
            ),
            _OptionTile(
              icon: Icons.delete_outline_rounded,
              label: 'Remove song',
              isDestructive: true,
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(context, ref, song);
              },
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
  /// K3: Confirmation dialog sebelum menghapus lagu dari storage.
  void _confirmDelete(BuildContext context, WidgetRef ref, SongModel song) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        title: const Text(
          'Delete from device?',
          style: TextStyle(color: AppColors.onSurface),
        ),
        content: Text(
          '"${song.title}" akan dihapus permanen dari storage device Anda.\n\nTindakan ini tidak dapat dibatalkan.',
          style: const TextStyle(color: AppColors.onSurfaceVariant, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await ref.read(songsProvider.notifier).deleteSong(song.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('"${song.title}" deleted'),
                    backgroundColor: AppColors.surfaceVariant,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text(
              'Delete',
              style: TextStyle(
                  color: Colors.redAccent, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  /// Shows an add-to-playlist bottom sheet using a proper ConsumerWidget
  /// so that ref.watch works correctly inside the Riverpod tree.
  void _showAddToPlaylistSheet(
      BuildContext context, WidgetRef ref, SongModel song) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddToPlaylistSheet(song: song),
    );
  }

  /// Opens EditSongSheet — full-featured metadata / YouTube / lyrics editor.
  void _showEditSongSheet(
      BuildContext context, WidgetRef ref, SongModel song) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EditSongSheet(song: song),
    );
  }
}

/// Separate widget so ref.watch(playlistsProvider) works in the Riverpod tree.
class _AddToPlaylistSheet extends ConsumerWidget {
  final SongModel song;
  const _AddToPlaylistSheet({required this.song});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(playlistsProvider);
    final playlists = playlistsAsync.value ?? [];

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Add to Playlist',
                      style: TextStyle(
                        color: AppColors.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  // Create new playlist shortcut
                  TextButton.icon(
                    onPressed: () => _showCreatePlaylistDialog(context, ref),
                    icon: const Icon(Icons.add_rounded,
                        color: AppColors.primary, size: 18),
                    label: const Text(
                      'New',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white10, height: 1),

            if (playlists.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(Icons.queue_music_rounded,
                        color: AppColors.onSurfaceVariant, size: 40),
                    SizedBox(height: 12),
                    Text(
                      'No playlists yet.\nTap New to create one.',
                      style: TextStyle(
                          color: AppColors.onSurfaceVariant, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: playlists.length,
                  itemBuilder: (_, i) {
                    final p = playlists[i];
                    final alreadyIn = p.songIds.contains(song.id);
                    return ListTile(
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.queue_music_rounded,
                            color: AppColors.onSurfaceVariant, size: 22),
                      ),
                      title: Text(
                        p.name,
                        style: TextStyle(
                          color: alreadyIn
                              ? AppColors.onSurfaceVariant
                              : AppColors.onSurface,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        '${p.songIds.length} songs${alreadyIn ? ' • Already added' : ''}',
                        style: const TextStyle(
                          color: AppColors.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      trailing: alreadyIn
                          ? const Icon(Icons.check_rounded,
                              color: AppColors.primary, size: 20)
                          : null,
                      onTap: alreadyIn
                          ? null
                          : () {
                              ref
                                  .read(playlistsProvider.notifier)
                                  .addSong(p.id, song.id);
                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Added to ${p.name}'),
                                  backgroundColor: AppColors.surfaceVariant,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showCreatePlaylistDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        title: const Text('New Playlist',
            style: TextStyle(color: AppColors.onSurface)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppColors.onSurface),
          decoration: const InputDecoration(
            hintText: 'Playlist name',
            hintStyle: TextStyle(color: AppColors.onSurfaceVariant),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.primary)),
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.primary, width: 2)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                await ref.read(playlistsProvider.notifier).create(name);
                final playlistsAsync = ref.read(playlistsProvider);
                final playlists = playlistsAsync.value ?? [];
                if (playlists.isNotEmpty) {
                  final newest = playlists.first; // sorted by createdAt desc
                  await ref
                      .read(playlistsProvider.notifier)
                      .addSong(newest.id, song.id);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  if (context.mounted) {
                    Navigator.of(context).pop(); // close sheet
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Added to $name'),
                        backgroundColor: AppColors.surfaceVariant,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                }
              }
            },
            child: const Text('Create & Add',
                style: TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  const _OptionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? Colors.redAccent : AppColors.onSurfaceVariant;
    return ListTile(
      leading: Icon(icon, color: color, size: 22),
      title: Text(
        label,
        style: TextStyle(
          color: isDestructive ? Colors.redAccent : AppColors.onSurface,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      dense: true,
    );
  }
}

