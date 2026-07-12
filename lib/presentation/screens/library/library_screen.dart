import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ibnutify/core/theme/app_theme.dart';
import 'package:ibnutify/data/models/song_model.dart';
import 'package:ibnutify/presentation/providers/app_providers.dart';
import 'package:ibnutify/presentation/providers/online_art_provider.dart';
import 'package:ibnutify/presentation/widgets/common/song_list_tile.dart';
import 'package:ibnutify/presentation/widgets/common/song_artwork_widget.dart';
import 'package:ibnutify/presentation/screens/library/playlist_detail_screen.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  bool _isScanning = false;
  int _selectedTabIndex = 0; // 0: Playlists, 1: Artists, 2: Albums, 3: Songs, 4: Duplicates

  Future<void> _scanMusic() async {
    setState(() => _isScanning = true);
    final status = await Permission.audio.request();
    if (status.isDenied) {
      await Permission.storage.request();
    }
    await ref.read(songsProvider.notifier).scanDeviceSongs();
    setState(() => _isScanning = false);
  }

  void _createNewPlaylist() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        title: const Text('New Playlist', style: TextStyle(color: AppColors.onSurface)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: AppColors.onSurface),
          decoration: const InputDecoration(
            hintText: 'Playlist Name',
            hintStyle: TextStyle(color: AppColors.onSurfaceVariant),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.primary)),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                ref.read(playlistsProvider.notifier).create(name);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Create', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final songsAsync = ref.watch(songsProvider);
    final duplicatesAsync = ref.watch(duplicateSongsProvider);
    final duplicates = duplicatesAsync.value ?? {};
    final tabs = ['Playlists', 'Artists', 'Albums', 'Songs'];
    final hasDuplicates = duplicates.isNotEmpty;

    return Column(
      children: [
        // ── Sticky Header ───────────────────────────────────────────────────
        Container(
          color: AppColors.background.withOpacity(0.95),
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.surfaceContainerHigh,
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: const Icon(Icons.person_rounded, color: AppColors.onSurfaceVariant, size: 18),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Your Library',
                        style: TextStyle(
                          color: AppColors.onSurface,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: _scanMusic,
                        icon: _isScanning
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                              )
                            : const Icon(Icons.refresh_rounded, color: AppColors.onSurface),
                        tooltip: 'Scan Local Music',
                      ),
                      IconButton(
                        onPressed: _createNewPlaylist,
                        icon: const Icon(Icons.add_rounded, color: AppColors.onSurface),
                      ),
                    ],
                  ),
                ),

                // ── Tabs ───────────────────────────────────────────────────────
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      ...List.generate(tabs.length, (i) {
                        final isSelected = _selectedTabIndex == i;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => setState(() => _selectedTabIndex = i),
                              borderRadius: BorderRadius.circular(32),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isSelected ? AppColors.primary : AppColors.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(32),
                                  border: Border.all(
                                    color: isSelected ? AppColors.primary : Colors.transparent,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      tabs[i],
                                      style: TextStyle(
                                        color: isSelected ? AppColors.background : AppColors.onSurface,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── ML Progress Banner ──────────────────────────────────────────────
        Consumer(
          builder: (context, ref, child) {
            final mlProgress = ref.watch(mlProgressProvider);
            if (mlProgress == null) return const SizedBox.shrink();
            return Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.primary.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      mlProgress,
                      style: const TextStyle(
                        color: AppColors.onSurface,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),

        // ── Content ─────────────────────────────────────────────────────────
        Expanded(
          child: songsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
            error: (err, _) => Center(child: Text('Error: $err', style: const TextStyle(color: AppColors.onSurfaceVariant))),
            data: (songs) {
              final castSongs = songs.cast<SongModel>();

              if (castSongs.isEmpty) {
                return _EmptyState(onScan: _scanMusic, isScanning: _isScanning);
              }

              if (_selectedTabIndex == 0) return _buildPlaylistsView(castSongs);
              if (_selectedTabIndex == 1) return _buildArtistsView(castSongs);
              if (_selectedTabIndex == 2) return _buildAlbumsView(castSongs);
              
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                itemCount: castSongs.length + 2, // +1 for chip, +1 for bottom padding
                itemBuilder: (ctx, i) {
                  if (i == 0) {
                    if (hasDuplicates) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: ActionChip(
                          backgroundColor: Colors.redAccent.withOpacity(0.1),
                          side: BorderSide(color: Colors.redAccent.withOpacity(0.3)),
                          label: Text(
                            '${duplicates.length} Lagu Duplikat Ditemukan',
                            style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)
                          ),
                          onPressed: () {
                            showModalBottomSheet(
                              context: context,
                              backgroundColor: AppColors.background,
                              isScrollControlled: true,
                              builder: (context) => DraggableScrollableSheet(
                                initialChildSize: 0.9,
                                builder: (_, controller) => _buildDuplicatesView(controller),
                              ),
                            );
                          },
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  }

                  final songIndex = i - 1;
                  if (songIndex == castSongs.length) return const SizedBox(height: 160);
                  
                  final song = castSongs[songIndex];
                  final after = castSongs.sublist(songIndex);
                  final before = castSongs.sublist(0, songIndex);
                  final contextQueue = [...after, ...before];
                  return SongListTile(song: song, queue: contextQueue);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPlaylistsView(List<SongModel> allSongs) {
    final playlistsAsync = ref.watch(playlistsProvider);
    final playlists = playlistsAsync.value ?? [];
    final recentlyPlayedAsync = ref.watch(recentlyPlayedProvider);
    final recentlyPlayed = recentlyPlayedAsync.value ?? [];
    final topSongsAsync = ref.watch(topSongsProvider);
    final topSongs = topSongsAsync.value ?? [];
    final dailyMixes = ref.watch(dailyMixesProvider);
    final songEras = ref.watch(songErasProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 160),
      children: [
        // Recently Played (24h)
        if (recentlyPlayed.isNotEmpty)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.history_rounded, color: AppColors.primary),
            ),
            title: const Text('Recently Played',
                style: TextStyle(color: AppColors.onSurface, fontWeight: FontWeight.w700)),
            subtitle: Text('${recentlyPlayed.length} songs recently played',
                style: const TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12)),
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PlaylistDetailScreen(
                  title: 'Recently Played',
                  description: 'Songs played recently',
                  initialSongs: recentlyPlayed,
                ),
              ));
            },
          ),
        if (recentlyPlayed.isNotEmpty) const SizedBox(height: 8),

        // Top Songs
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.trending_up_rounded, color: AppColors.primary),
          ),
          title: const Text('On Repeat',
              style: TextStyle(color: AppColors.onSurface, fontWeight: FontWeight.w700)),
          subtitle: const Text('Your top 20 most listened songs',
              style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12)),
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PlaylistDetailScreen(
                title: 'On Repeat',
                description: 'Songs you listen to the most.',
                initialSongs: topSongs,
              ),
            ));
          },
        ),
        const SizedBox(height: 12),

        // Daily Mixes
        if (dailyMixes.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Made For You', style: TextStyle(color: AppColors.onSurfaceVariant, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          ...dailyMixes.map((mix) {
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: mix.songs.isNotEmpty
                  ? SongArtworkWidget(song: mix.songs.first, size: 56, borderRadius: 8)
                  : Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.auto_awesome_rounded, color: AppColors.primary),
                    ),
              title: Text(mix.name,
                  style: const TextStyle(color: AppColors.onSurface, fontWeight: FontWeight.w700)),
              subtitle: Text(mix.description,
                  style: const TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PlaylistDetailScreen(
                    title: mix.name,
                    description: mix.description,
                    initialSongs: mix.songs,
                  ),
                ));
              },
            );
          }),
          const SizedBox(height: 12),
        ],

        // Song Eras
        if (songEras.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Song Eras', style: TextStyle(color: AppColors.onSurfaceVariant, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          ...songEras.map((era) {
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: era.songs.isNotEmpty
                  ? SongArtworkWidget(song: era.songs.first, size: 56, borderRadius: 8)
                  : Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.schedule_rounded, color: AppColors.primary),
                    ),
              title: Text(era.name,
                  style: const TextStyle(color: AppColors.onSurface, fontWeight: FontWeight.w700)),
              subtitle: Text(era.description,
                  style: const TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PlaylistDetailScreen(
                    title: era.name,
                    description: era.description,
                    initialSongs: era.songs,
                  ),
                ));
              },
            );
          }),
          const SizedBox(height: 12),
        ],

        // User Playlists Header
        if (playlists.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Playlists', style: TextStyle(color: AppColors.onSurfaceVariant, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        ],
        ...playlists.map((p) {
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.queue_music_rounded,
                  color: AppColors.onSurfaceVariant),
            ),
            title: Text(p.name,
                style: const TextStyle(
                    color: AppColors.onSurface, fontWeight: FontWeight.w700)),
            subtitle: Text('${p.songIds.length} songs',
                style: const TextStyle(
                    color: AppColors.onSurfaceVariant, fontSize: 12)),
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PlaylistDetailScreen(
                  title: p.name,
                  description: p.description ?? '',
                  initialSongs: const [],
                  playlistId: p.id,
                ),
              ));
            },
          );
        }),
      ],
    );
  }

  Widget _buildArtistsView(List<SongModel> allSongs) {
    final artistsMap = <String, List<SongModel>>{};
    for (var s in allSongs) {
      artistsMap.putIfAbsent(s.artist, () => []).add(s);
    }
    final sortedArtists = artistsMap.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 160),
      itemCount: sortedArtists.length,
      itemBuilder: (context, index) {
        final artist = sortedArtists[index];
        final artistSongs = artistsMap[artist]!;
        return Consumer(
          builder: (_, ref, __) {
            final artAsync = ref.watch(artistImageProvider(artist));
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: ClipOval(
                child: artAsync.when(
                  data: (path) {
                    if (path != null) {
                      return Image.file(
                        File(path),
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => SongArtworkWidget(song: artistSongs.first, size: 56, borderRadius: 28),
                      );
                    }
                    return SongArtworkWidget(song: artistSongs.first, size: 56, borderRadius: 28);
                  },
                  loading: () => SongArtworkWidget(song: artistSongs.first, size: 56, borderRadius: 28),
                  error: (_, __) => SongArtworkWidget(song: artistSongs.first, size: 56, borderRadius: 28),
                ),
              ),
              title: Text(artist,
                  style: const TextStyle(
                      color: AppColors.onSurface, fontWeight: FontWeight.w700)),
              subtitle: Text('${artistSongs.length} songs',
                  style: const TextStyle(
                      color: AppColors.onSurfaceVariant, fontSize: 12)),
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PlaylistDetailScreen(
                    title: artist,
                    description: 'Songs by $artist',
                    initialSongs: artistSongs,
                  ),
                ));
              },
            );
          },
        );
      },
    );
  }

  Widget _artistPlaceholder() {
    return Container(
      width: 56,
      height: 56,
      color: AppColors.surfaceContainerHigh,
      child: const Icon(Icons.person_rounded,
          color: AppColors.onSurfaceVariant),
    );
  }

  Widget _buildAlbumsView(List<SongModel> allSongs) {
    final albumsMap = <String, List<SongModel>>{};
    for (var s in allSongs) {
      albumsMap.putIfAbsent(s.album, () => []).add(s);
    }
    final sortedAlbums = albumsMap.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 160),
      itemCount: sortedAlbums.length,
      itemBuilder: (context, index) {
        final album = sortedAlbums[index];
        final albumSongs = albumsMap[album]!;
        final artist = albumSongs.first.artist;
        final cacheKey = '$album|||$artist';
        return Consumer(
          builder: (_, ref, __) {
            final artAsync = ref.watch(albumCoverOnlineProvider(cacheKey));
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: artAsync.when(
                  data: (path) {
                    if (path != null) {
                      return Image.file(
                        File(path),
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => SongArtworkWidget(song: albumSongs.first, size: 56, borderRadius: 8),
                      );
                    }
                    return SongArtworkWidget(song: albumSongs.first, size: 56, borderRadius: 8);
                  },
                  loading: () => SongArtworkWidget(song: albumSongs.first, size: 56, borderRadius: 8),
                  error: (_, __) => SongArtworkWidget(song: albumSongs.first, size: 56, borderRadius: 8),
                ),
              ),
              title: Text(album,
                  style: const TextStyle(
                      color: AppColors.onSurface, fontWeight: FontWeight.w700)),
              subtitle: Text('${albumSongs.length} songs',
                  style: const TextStyle(
                      color: AppColors.onSurfaceVariant, fontSize: 12)),
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PlaylistDetailScreen(
                    title: album,
                    description: 'Album',
                    initialSongs: albumSongs,
                  ),
                ));
              },
            );
          },
        );
      },
    );
  }

  Widget _albumPlaceholder() {
    return Container(
      width: 56,
      height: 56,
      color: AppColors.surfaceContainerHigh,
      child: const Icon(Icons.album_rounded, color: AppColors.onSurfaceVariant),
    );
  }

  /// K2: Build tampilan duplikat — grouped by title+artist.
  Widget _buildDuplicatesView([ScrollController? scrollController]) {
    final duplicatesAsync = ref.watch(duplicateSongsProvider);
    final duplicates = duplicatesAsync.value ?? {};

    if (duplicates.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: AppColors.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_outline_rounded,
                  color: AppColors.primary, size: 40),
            ),
            const SizedBox(height: 20),
            const Text(
              'No duplicates found!',
              style: TextStyle(
                  color: AppColors.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your library is clean.',
              style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 14),
            ),
          ],
        ),
      );
    }

    final groups = duplicates.entries.toList();
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 160),
      itemCount: groups.length,
      itemBuilder: (context, groupIndex) {
        final entry = groups[groupIndex];
        final songs = entry.value;
        final displayTitle = songs.first.title;
        final displayArtist = songs.first.artist;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Group header
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayTitle,
                          style: const TextStyle(
                              color: AppColors.onSurface,
                              fontWeight: FontWeight.w900,
                              fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '$displayArtist • ${songs.length} duplicates',
                          style: const TextStyle(
                              color: AppColors.onSurfaceVariant, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                    ),
                    child: Text(
                      '${songs.length} dupes',
                      style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            // Individual songs in this group
            ...songs.asMap().entries.map((e) {
              final i = e.key;
              final song = e.value;
              return ListTile(
                contentPadding: const EdgeInsets.only(left: 8, right: 0),
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        color: i == 0
                            ? AppColors.primary
                            : AppColors.onSurfaceVariant,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                title: Text(
                  song.title,
                  style: TextStyle(
                    color: i == 0 ? AppColors.onSurface : AppColors.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w400,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  song.uri.split('/').last,
                  style: const TextStyle(
                      color: AppColors.onSurfaceVariant, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: i == 0
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('Keep',
                            style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      )
                    : IconButton(
                        icon: const Icon(Icons.delete_outline_rounded,
                            color: Colors.redAccent, size: 20),
                        onPressed: () => _confirmDeleteDuplicate(context, song),
                      ),
              );
            }),
            const Divider(color: Colors.white10, height: 1),
          ],
        );
      },
    );
  }

  void _confirmDeleteDuplicate(BuildContext context, SongModel song) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        title: const Text('Delete duplicate?',
            style: TextStyle(color: AppColors.onSurface)),
        content: Text(
          '"${song.title}" akan dihapus permanen dari storage.',
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
            },
            child: const Text('Delete',
                style: TextStyle(
                    color: Colors.redAccent, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onScan;
  final bool isScanning;

  const _EmptyState({required this.onScan, required this.isScanning});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHighest,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 30)
              ],
            ),
            child: const Icon(Icons.album_rounded, color: AppColors.primary, size: 56),
          ),
          const SizedBox(height: 24),
          const Text(
            'Your library is empty',
            style: TextStyle(color: AppColors.onSurface, fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Tap Scan Music to load songs from your device storage',
              style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 32),
          GestureDetector(
            onTap: isScanning ? null : onScan,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isScanning)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(color: AppColors.background, strokeWidth: 2),
                    )
                  else
                    const Icon(Icons.add_rounded, color: AppColors.background, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Scan Music',
                    style: TextStyle(color: AppColors.background, fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
