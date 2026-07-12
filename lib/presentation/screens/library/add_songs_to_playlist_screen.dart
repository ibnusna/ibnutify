import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/song_model.dart';
import '../../providers/app_providers.dart';
import '../../widgets/common/song_artwork_widget.dart';

/// Full-screen song picker — lets users select multiple songs to add to a playlist.
/// Shows a searchable list with checkboxes. Confirms on "Add X songs" button.
class AddSongsToPlaylistScreen extends ConsumerStatefulWidget {
  final String playlistId;
  final String playlistName;
  /// Song IDs already in the playlist (to grey them out, not allow duplicates)
  final Set<int> existingSongIds;

  const AddSongsToPlaylistScreen({
    super.key,
    required this.playlistId,
    required this.playlistName,
    required this.existingSongIds,
  });

  @override
  ConsumerState<AddSongsToPlaylistScreen> createState() =>
      _AddSongsToPlaylistScreenState();
}

class _AddSongsToPlaylistScreenState
    extends ConsumerState<AddSongsToPlaylistScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  final Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.toLowerCase().trim());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<SongModel> _filteredSongs(List<SongModel> all) {
    if (_query.isEmpty) return all;
    return all.where((s) {
      return s.title.toLowerCase().contains(_query) ||
          s.artist.toLowerCase().contains(_query) ||
          s.album.toLowerCase().contains(_query);
    }).toList();
  }

  Future<void> _confirm() async {
    if (_selected.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    await ref
        .read(playlistsProvider.notifier)
        .addSongs(widget.playlistId, _selected.toList());
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added ${_selected.length} song${_selected.length == 1 ? '' : 's'} to ${widget.playlistName}'),
          backgroundColor: AppColors.surfaceVariant,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final songsAsync = ref.watch(songsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: AppColors.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Add Songs',
              style: TextStyle(
                color: AppColors.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              widget.playlistName,
              style: const TextStyle(
                color: AppColors.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          if (_selected.isNotEmpty)
            TextButton(
              onPressed: _confirm,
              child: Text(
                'Add ${_selected.length}',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(22),
              ),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: AppColors.onSurface, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search songs, artists…',
                  hintStyle: const TextStyle(
                    color: AppColors.onSurfaceVariant,
                    fontSize: 14,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: AppColors.onSurfaceVariant,
                    size: 20,
                  ),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded,
                              color: AppColors.onSurfaceVariant, size: 18),
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),

          // Song list
          Expanded(
            child: songsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
              error: (e, _) => Center(
                child: Text('Error: $e',
                    style: const TextStyle(color: AppColors.onSurfaceVariant)),
              ),
              data: (songs) {
                final all = songs.cast<SongModel>();
                final filtered = _filteredSongs(all);

                if (filtered.isEmpty) {
                  return const Center(
                    child: Text(
                      'No songs found',
                      style: TextStyle(color: AppColors.onSurfaceVariant),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(top: 4, bottom: 120),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) {
                    final song = filtered[i];
                    final alreadyAdded = widget.existingSongIds.contains(song.id);
                    final isSelected = _selected.contains(song.id);

                    return ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                      leading: SongArtworkWidget(
                        song: song,
                        size: 48,
                        borderRadius: 6,
                      ),
                      title: Text(
                        song.title,
                        style: TextStyle(
                          color: alreadyAdded
                              ? AppColors.onSurfaceVariant
                              : AppColors.onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${song.artist} • ${song.album}',
                        style: const TextStyle(
                          color: AppColors.onSurfaceVariant,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: alreadyAdded
                          ? const Padding(
                              padding: EdgeInsets.only(right: 4),
                              child: Text(
                                'Added',
                                style: TextStyle(
                                  color: AppColors.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                            )
                          : Checkbox(
                              value: isSelected,
                              activeColor: AppColors.primary,
                              checkColor: AppColors.background,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4)),
                              side: BorderSide(
                                  color: AppColors.onSurfaceVariant
                                      .withOpacity(0.5)),
                              onChanged: (v) {
                                setState(() {
                                  if (v == true) {
                                    _selected.add(song.id);
                                  } else {
                                    _selected.remove(song.id);
                                  }
                                });
                              },
                            ),
                      onTap: alreadyAdded
                          ? null
                          : () {
                              setState(() {
                                if (_selected.contains(song.id)) {
                                  _selected.remove(song.id);
                                } else {
                                  _selected.add(song.id);
                                }
                              });
                            },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),

      // Floating confirm button
      floatingActionButton: _selected.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _confirm,
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.add_rounded, color: AppColors.background),
              label: Text(
                'Add ${_selected.length} song${_selected.length == 1 ? '' : 's'}',
                style: const TextStyle(
                  color: AppColors.background,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
    );
  }
}
