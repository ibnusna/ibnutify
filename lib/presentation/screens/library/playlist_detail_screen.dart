import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ibnutify/core/theme/app_theme.dart';
import 'package:ibnutify/data/models/playlist_model.dart';
import 'package:ibnutify/data/models/song_model.dart';
import 'package:ibnutify/presentation/providers/app_providers.dart';
import 'package:ibnutify/presentation/widgets/common/song_list_tile.dart';
import 'package:ibnutify/presentation/widgets/common/dynamic_cover_widget.dart';
import 'package:ibnutify/presentation/screens/library/library_screen.dart';
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

  String _formatTotalDuration(List<SongModel> songs) {
    if (songs.isEmpty) return '0 mnt';
    final totalSec = songs.fold<int>(0, (sum, s) => sum + (s.duration ~/ 1000));
    final hours = totalSec ~/ 3600;
    final minutes = (totalSec % 3600) ~/ 60;
    if (hours > 0) {
      return '${hours}j ${minutes} mnt';
    }
    return '${minutes} mnt';
  }

  void _openCoverEditor(PlaylistModel playlist, List<SongModel> songs) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => TemplateEditorSheet(playlist: playlist, songs: songs),
    );
  }

  void _showOptionsMenu(BuildContext context, PlaylistModel playlistModel, List<SongModel> displaySongs, Set<int> existingSongIds, bool isEditable) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.palette_outlined, color: AppColors.primary),
                title: const Text('Edit Cover Playlist', style: TextStyle(color: AppColors.onSurface, fontWeight: FontWeight.w600)),
                subtitle: const Text('Ubah gaya template, warna, ikon & teks', style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  _openCoverEditor(playlistModel, displaySongs);
                },
              ),
              if (isEditable)
                ListTile(
                  leading: const Icon(Icons.add_rounded, color: AppColors.onSurface),
                  title: const Text('Tambah Lagu', style: TextStyle(color: AppColors.onSurface)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openAddSongs(context, existingSongIds);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.shuffle_rounded, color: AppColors.onSurface),
                title: const Text('Acak Antrean', style: TextStyle(color: AppColors.onSurface)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final shuffled = List<SongModel>.from(displaySongs)..shuffle();
                  if (shuffled.isNotEmpty) {
                    ref.read(playerProvider.notifier).playSong(
                          shuffled.first,
                          shuffled,
                          source: 'Playlist: ${widget.title}',
                        );
                  }
                },
              ),
              if (isEditable)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                  title: const Text('Hapus Playlist', style: TextStyle(color: Colors.redAccent)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmDelete(context, ref);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  void _showSongOptions(BuildContext context, SongModel song) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.play_arrow_rounded, color: AppColors.primary),
                title: Text(song.title, style: const TextStyle(color: AppColors.onSurface, fontWeight: FontWeight.bold)),
                subtitle: Text(song.artist, style: const TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12)),
              ),
              const Divider(color: Colors.white10),
              ListTile(
                leading: const Icon(Icons.queue_music_rounded, color: AppColors.onSurface),
                title: const Text('Tambah ke Antrean', style: TextStyle(color: AppColors.onSurface)),
                onTap: () {
                  Navigator.pop(ctx);
                  ref.read(playerProvider.notifier).addToQueue(song);
                },
              ),
              if (widget.playlistId != null)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                  title: const Text('Hapus dari Playlist', style: TextStyle(color: Colors.redAccent)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await ref.read(playlistsProvider.notifier).removeSong(widget.playlistId!, song.id);
                    await _loadLiveSongs();
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(playlistsProvider, (previous, next) {
      if (widget.playlistId != null) {
        _loadLiveSongs();
      }
    });

    final List<SongModel> displaySongs;
    final Set<int> existingSongIds;
    PlaylistModel? currentPlaylist;
    
    final playlistsAsync = ref.watch(playlistsProvider);
    final allPlaylists = playlistsAsync.value ?? [];

    if (widget.playlistId != null) {
      currentPlaylist = allPlaylists.where((p) => p.id == widget.playlistId).firstOrNull;
      displaySongs = _liveSongs ?? widget.initialSongs;
      existingSongIds = currentPlaylist != null ? Set<int>.from(currentPlaylist.songIds) : {};
    } else {
      currentPlaylist = allPlaylists.where((p) => p.id == widget.title || p.name == widget.title).firstOrNull;
      displaySongs = widget.initialSongs;
      existingSongIds = Set<int>.from(widget.initialSongs.map((s) => s.id));
    }

    final isEditable = widget.playlistId != null;

    final playlistModel = currentPlaylist ?? PlaylistModel(
      id: widget.playlistId ?? widget.title,
      name: widget.title,
      description: widget.description,
      songIds: displaySongs.map((s) => s.id).toList(),
      isCustom: false,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      coverTemplateType: widget.title.startsWith('Daily Mix') ? 'dailymix' : 'minimal',
      coverColor: 'purple-indigo',
      coverIcon: 'ph-music-notes',
      coverTitle: widget.title,
    );

    final isPlayingThisPlaylist = ref.watch(playerProvider).queueSource == 'Playlist: ${widget.title}' && ref.watch(playerProvider).isPlaying;

    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // ── Full-Width Edge-To-Edge Cover Header ───────────────────────────
          SliverToBoxAdapter(
            child: Stack(
              children: [
                // Full Width Hero Cover Art
                SizedBox(
                  width: screenWidth,
                  height: 320,
                  child: DynamicCoverWidget(
                    templateType: playlistModel.coverTemplateType ?? (widget.title.startsWith('Daily Mix') ? 'dailymix' : 'minimal'),
                    color: playlistModel.coverColor ?? 'purple-indigo',
                    icon: playlistModel.coverIcon ?? 'ph-music-notes',
                    title: playlistModel.coverTitle ?? widget.title,
                    songs: displaySongs,
                    size: screenWidth,
                    borderRadius: 0,
                    isPreview: true,
                  ),
                ),

                // Spotify Dark Gradient Overlay (Fade down to #121212)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.3),
                          Colors.black.withOpacity(0.6),
                          AppColors.background.withOpacity(0.95),
                          AppColors.background,
                        ],
                        stops: const [0.0, 0.4, 0.85, 1.0],
                      ),
                    ),
                  ),
                ),

                // Header Overlay Controls
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Back Arrow & Titik 3
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 28),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                            IconButton(
                              icon: const Icon(Icons.more_vert_rounded, color: Colors.white, size: 28),
                              onPressed: () => _showOptionsMenu(context, playlistModel, displaySongs, existingSongIds, isEditable),
                              tooltip: 'Opsi Playlist & Edit Cover',
                            ),
                          ],
                        ),
                        const SizedBox(height: 120),

                        // Title Text
                        Text(
                          playlistModel.coverTitle ?? widget.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),

                        // Description
                        if (widget.description.isNotEmpty) ...[
                          Text(
                            widget.description,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                        ],

                        // Spotify Green Badge / Tag
                        Row(
                          children: [
                            Container(
                              width: 18,
                              height: 18,
                              decoration: const BoxDecoration(
                                color: Color(0xFF1DB954),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.music_note_rounded, color: Colors.black, size: 12),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Dibuat untukmu',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '•   ${_formatTotalDuration(displaySongs)}',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Action Bar (Shuffle & Big Green Play Button)
                        Row(
                          children: [
                            const Spacer(),

                            // Shuffle Button
                            IconButton(
                              icon: const Icon(Icons.shuffle_rounded, color: Color(0xFF1DB954), size: 30),
                              onPressed: () {
                                final shuffled = List<SongModel>.from(displaySongs)..shuffle();
                                if (shuffled.isNotEmpty) {
                                  ref.read(playerProvider.notifier).playSong(
                                        shuffled.first,
                                        shuffled,
                                        source: 'Playlist: ${widget.title}',
                                      );
                                }
                              },
                              tooltip: 'Acak',
                            ),
                            const SizedBox(width: 12),

                            // Big Spotify Green Play Button
                            GestureDetector(
                              onTap: () {
                                if (displaySongs.isNotEmpty) {
                                  if (isPlayingThisPlaylist) {
                                    ref.read(playerProvider.notifier).togglePlay();
                                  } else {
                                    ref.read(playerProvider.notifier).playSong(
                                          displaySongs.first,
                                          displaySongs,
                                          source: 'Playlist: ${widget.title}',
                                        );
                                  }
                                }
                              },
                              child: Container(
                                width: 56,
                                height: 56,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF1DB954), // Spotify Green
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Color(0x661DB954),
                                      blurRadius: 16,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  isPlayingThisPlaylist ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                  color: Colors.black,
                                  size: 34,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Song List Items ────────────────────────────────────────────────
          displaySongs.isEmpty
              ? SliverFillRemaining(
                  child: _EmptyPlaylist(
                    isEditable: isEditable,
                    onAddSongs: isEditable
                        ? () => _openAddSongs(context, existingSongIds)
                        : null,
                  ),
                )
              : SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                      final song = displaySongs[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SongListTile(
                          song: song,
                          queue: displaySongs,
                          queueSource: 'Playlist: ${widget.title}',
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.more_vert_rounded,
                              color: AppColors.onSurfaceVariant,
                              size: 20,
                            ),
                            onPressed: () => _showSongOptions(context, song),
                          ),
                        ),
                      );
                    },
                    childCount: displaySongs.length,
                  ),
                ),

          const SliverToBoxAdapter(
            child: SizedBox(height: 140),
          ),
        ],
      ),

      // FAB shortcut to add songs (editable only)
      floatingActionButton: isEditable
          ? FloatingActionButton(
              onPressed: () => _openAddSongs(context, existingSongIds),
              backgroundColor: const Color(0xFF1DB954),
              tooltip: 'Add songs',
              child: const Icon(Icons.add_rounded, color: Colors.black),
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
