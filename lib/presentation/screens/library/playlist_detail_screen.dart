import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ibnutify/core/theme/app_theme.dart';
import 'package:ibnutify/data/models/song_model.dart';
import 'package:ibnutify/presentation/providers/app_providers.dart';
import 'package:ibnutify/presentation/widgets/common/song_list_tile.dart';
import 'package:ibnutify/presentation/screens/library/add_songs_to_playlist_screen.dart';

class PlaylistDetailScreen extends ConsumerStatefulWidget {
  final String title;
  final String description;
  final List<SongModel> initialSongs;
  final String? playlistId;

  const PlaylistDetailScreen({
    super.key,
    required this.title,
    required this.description,
    required this.initialSongs,
    this.playlistId,
  });

  @override
  ConsumerState<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends ConsumerState<PlaylistDetailScreen> {
  List<SongModel>? _liveSongs;

  @override
  void initState() {
    super.initState();
    if (widget.playlistId != null) {
      _loadLiveSongs();
    }
  }

  Future<void> _loadLiveSongs() async {
    final playlistsAsync = ref.read(playlistsProvider);
    final current = playlistsAsync.value?.where((p) => p.id == widget.playlistId).firstOrNull;
    if (current != null) {
      final songs = await ref.read(musicRepositoryProvider).getSongsForPlaylist(current);
      if (mounted) {
        setState(() {
          _liveSongs = songs;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen to playlistsProvider changes to auto-refresh
    ref.listen(playlistsProvider, (previous, next) {
      if (widget.playlistId != null) {
        _loadLiveSongs();
      }
    });

    final List<SongModel> displaySongs;
    final Set<int> existingSongIds;
    
    if (widget.playlistId != null) {
      final playlistsAsync = ref.watch(playlistsProvider);
      final current = playlistsAsync.value?.where((p) => p.id == widget.playlistId).firstOrNull;
      
      displaySongs = _liveSongs ?? widget.initialSongs;
      existingSongIds = current != null ? Set<int>.from(current.songIds) : {};
    } else {
      displaySongs = widget.initialSongs;
      existingSongIds = Set<int>.from(widget.initialSongs.map((s) => s.id));
    }

    final isEditable = widget.playlistId != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          // Add songs button (editable playlists only)
          if (isEditable)
            IconButton(
              icon: const Icon(Icons.add_rounded, color: AppColors.primary),
              tooltip: 'Add songs',
              onPressed: () => _openAddSongs(context, existingSongIds),
            ),
          if (isEditable)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              onPressed: () => _confirmDelete(context, ref),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    color: AppColors.onSurface,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (widget.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    widget.description,
                    style: const TextStyle(
                      color: AppColors.onSurfaceVariant,
                      fontSize: 14,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    Text(
                      '${displaySongs.length} songs',
                      style: const TextStyle(
                        color: AppColors.onSurfaceVariant,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    if (displaySongs.isNotEmpty) ...[
                      GestureDetector(
                        onTap: () async {
                          for (final song in displaySongs) {
                            await ref.read(playerProvider.notifier).addToQueue(song);
                          }
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '${displaySongs.length} lagu ditambahkan ke antrean',
                                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700),
                                ),
                                backgroundColor: AppColors.primary,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: const BoxDecoration(
                            color: AppColors.surfaceContainerHigh,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.queue_music_rounded,
                              color: AppColors.primary, size: 28),
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () {
                          ref
                              .read(playerProvider.notifier)
                              .playSong(displaySongs.first, displaySongs,
                                  source: 'Playlist: ${widget.title}');
                        },
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.play_arrow_rounded,
                              color: AppColors.background, size: 32),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          const Divider(color: Colors.white10, height: 1),

          // Song list
          Expanded(
            child: displaySongs.isEmpty
                ? _EmptyPlaylist(
                    isEditable: isEditable,
                    onAddSongs: isEditable
                        ? () => _openAddSongs(context, existingSongIds)
                        : null,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(top: 8, bottom: 120),
                    itemCount: displaySongs.length,
                    itemBuilder: (ctx, i) {
                      final song = displaySongs[i];
                      return SongListTile(
                        song: song,
                        queue: displaySongs,
                        queueSource: 'Playlist: ${widget.title}',
                        trailing: isEditable
                            ? IconButton(
                                icon: const Icon(
                                  Icons.remove_circle_outline_rounded,
                                  color: AppColors.onSurfaceVariant,
                                  size: 20,
                                ),
                                onPressed: () async {
                                  await ref
                                      .read(playlistsProvider.notifier)
                                      .removeSong(widget.playlistId!, song.id);
                                  await _loadLiveSongs();
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          '"${song.title}" dihapus dari playlist',
                                          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700),
                                        ),
                                        backgroundColor: AppColors.primary,
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                },
                              )
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),

      // FAB shortcut to add songs (editable only)
      floatingActionButton: isEditable
          ? FloatingActionButton(
              onPressed: () => _openAddSongs(context, existingSongIds),
              backgroundColor: AppColors.primary,
              tooltip: 'Add songs',
              child: const Icon(Icons.add_rounded, color: AppColors.background),
            )
          : null,
    );
  }

  void _openAddSongs(BuildContext context, Set<int> existing) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddSongsToPlaylistScreen(
          playlistId: widget.playlistId!,
          playlistName: widget.title,
          existingSongIds: existing,
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        title: const Text('Delete Playlist?',
            style: TextStyle(color: AppColors.onSurface)),
        content: const Text(
          'This action cannot be undone.',
          style: TextStyle(color: AppColors.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.primary)),
          ),
          TextButton(
            onPressed: () {
              ref.read(playlistsProvider.notifier).delete(widget.playlistId!);
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: const Text('Delete',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}

class _EmptyPlaylist extends StatelessWidget {
  final bool isEditable;
  final VoidCallback? onAddSongs;

  const _EmptyPlaylist({required this.isEditable, this.onAddSongs});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHigh,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.3), blurRadius: 20),
              ],
            ),
            child: const Icon(Icons.queue_music_rounded,
                color: AppColors.primary, size: 36),
          ),
          const SizedBox(height: 20),
          const Text(
            'No songs yet',
            style: TextStyle(
              color: AppColors.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isEditable
                ? 'Tap + to add songs to this playlist'
                : 'This playlist is empty',
            style: const TextStyle(
              color: AppColors.onSurfaceVariant,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          if (isEditable && onAddSongs != null) ...[
            const SizedBox(height: 28),
            GestureDetector(
              onTap: onAddSongs,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded,
                        color: AppColors.background, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Add Songs',
                      style: TextStyle(
                        color: AppColors.background,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
