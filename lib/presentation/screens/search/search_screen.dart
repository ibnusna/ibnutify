import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/song_model.dart';
import '../../providers/app_providers.dart';
import '../../widgets/common/song_list_tile.dart';
import '../library/playlist_detail_screen.dart';
import '../player/player_screen.dart';

/// Search Screen — mirrors SearchView.tsx
/// Real-time search with genre grid browse, category filtering & My Library navigation
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _isSearching = false;

  final List<Map<String, dynamic>> _genres = [
    {'name': 'Pop', 'color': const Color(0xFF8D67AB)},
    {'name': 'Rock', 'color': const Color(0xFFE8115B)},
    {'name': 'Hip Hop', 'color': const Color(0xFFBC5900)},
    {'name': 'Electronic', 'color': const Color(0xFF503750)},
    {'name': 'Indie', 'color': const Color(0xFF608108)},
    {'name': 'Jazz', 'color': const Color(0xFF1E3264)},
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onSongTap(BuildContext ctx, SongModel song, List<SongModel> queue) {
    FocusManager.instance.primaryFocus?.unfocus();
    ref.read(playerProvider.notifier).playFromSearch(song);
    Navigator.of(ctx).push(
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
  }

  @override
  Widget build(BuildContext context) {
    final searchResultsAsync = ref.watch(searchResultsProvider);
    final searchResults = searchResultsAsync.value ?? [];
    final selectedGenre = ref.watch(selectedGenreProvider);
    final selectedCategory = ref.watch(selectedSearchCategoryProvider);
    final playlistsAsync = ref.watch(playlistsProvider);
    final playlists = playlistsAsync.value ?? [];

    final categories = ['All', 'Artists', 'Albums', 'Playlists'];

    return PopScope(
      onPopInvokedWithResult: (_, __) => FocusManager.instance.primaryFocus?.unfocus(),
      child: GestureDetector(
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: CustomScrollView(
      slivers: [
        // ── Header ─────────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 48, 16, 0),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Search',
                    style: TextStyle(
                      color: AppColors.onSurface,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const Icon(Icons.settings_rounded,
                    color: AppColors.primary, size: 24),
                const SizedBox(width: 16),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.surfaceContainerHigh,
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: const Icon(Icons.person_rounded,
                      color: AppColors.onSurfaceVariant, size: 18),
                ),
              ],
            ),
          ),
        ),

        // ── Search Bar ──────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.onSurface,
                borderRadius: BorderRadius.circular(6),
              ),
              child: TextField(
                controller: _controller,
                onChanged: (v) {
                  ref.read(searchQueryProvider.notifier).update(v);
                  setState(() => _isSearching = v.isNotEmpty);
                },
                style: const TextStyle(
                  color: AppColors.background,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'What do you want to listen to?',
                  hintStyle: TextStyle(
                    color: AppColors.background.withOpacity(0.5),
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: AppColors.background, size: 22),
                  suffixIcon: (_isSearching || selectedGenre != null)
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded,
                              color: AppColors.background),
                          onPressed: () {
                            _controller.clear();
                            ref.read(searchQueryProvider.notifier).update('');
                            ref.read(selectedGenreProvider.notifier).state = null;
                            setState(() => _isSearching = false);
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
        ),

        // ── Filter Chips (Category Selection) ────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: categories.map((cat) {
                  final isSelected = selectedCategory == cat;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () {
                        ref.read(selectedSearchCategoryProvider.notifier).state = cat;
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          cat,
                          style: TextStyle(
                            color: isSelected
                                ? AppColors.background
                                : AppColors.onSurface,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),

        // ── Active Genre Banner (if selected) ──────────────────────────────
        if (selectedGenre != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.style_rounded, color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Genre: $selectedGenre (${searchResults.length} songs)',
                        style: const TextStyle(
                          color: AppColors.onSurface,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        ref.read(selectedGenreProvider.notifier).state = null;
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                        child: Text(
                          'Clear Filter',
                          style: TextStyle(
                            color: AppColors.background,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // ── Search Results / Category Views / Genre Grid ────────────────────
        if (_isSearching || selectedGenre != null) ...[
          if (searchResults.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    'No results found',
                    style: TextStyle(color: AppColors.onSurfaceVariant),
                  ),
                ),
              ),
            )
          else if (selectedCategory == 'Artists') ...[
            _buildArtistsCategory(searchResults),
          ] else if (selectedCategory == 'Albums') ...[
            _buildAlbumsCategory(searchResults),
          ] else if (selectedCategory == 'Playlists') ...[
            _buildPlaylistsCategory(playlists),
          ] else ...[
            // Default: 'All'
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final song = searchResults[i];
                    return SongListTile(
                      song: song,
                      queue: searchResults,
                      onTap: () => _onSongTap(ctx, song, searchResults),
                    );
                  },
                  childCount: searchResults.length,
                ),
              ),
            ),
          ],
        ] else ...[
          // ── Browse All Section Header (Clickable → My Library) ───────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: InkWell(
                onTap: () {
                  ref.read(navigationProvider.notifier).navigate(AppScreen.library);
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Browse all',
                        style: TextStyle(
                          color: AppColors.onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Row(
                        children: const [
                          Text(
                            'My Library',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(Icons.arrow_forward_ios_rounded,
                              color: AppColors.primary, size: 12),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Genre Grid ───────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.65,
              ),
              delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  final genreData = _genres[i];
                  return _GenreCard(
                    genre: genreData,
                    onTap: () {
                      final genreName = genreData['name'] as String;
                      ref.read(selectedGenreProvider.notifier).state = genreName;
                    },
                  );
                },
                childCount: _genres.length,
              ),
            ),
          ),
        ],

        const SliverPadding(padding: EdgeInsets.only(bottom: 160)),
      ],
    ),
    ),
    );
  }

  Widget _buildArtistsCategory(List<SongModel> songs) {
    final Map<String, List<SongModel>> artistsMap = {};
    for (final s in songs) {
      artistsMap.putIfAbsent(s.artist, () => []).add(s);
    }
    final sortedArtists = artistsMap.keys.toList()..sort();

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (ctx, i) {
            final artist = sortedArtists[i];
            final artistSongs = artistsMap[artist]!;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: AppColors.primary.withOpacity(0.2),
                child: const Icon(Icons.person_rounded, color: AppColors.primary),
              ),
              title: Text(artist,
                  style: const TextStyle(
                      color: AppColors.onSurface, fontWeight: FontWeight.bold)),
              subtitle: Text('${artistSongs.length} songs',
                  style: const TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12)),
              onTap: () {
                Navigator.of(ctx).push(MaterialPageRoute(
                  builder: (_) => PlaylistDetailScreen(
                    title: artist,
                    description: 'Songs by $artist',
                    initialSongs: artistSongs,
                  ),
                ));
              },
            );
          },
          childCount: sortedArtists.length,
        ),
      ),
    );
  }

  Widget _buildAlbumsCategory(List<SongModel> songs) {
    final Map<String, List<SongModel>> albumsMap = {};
    for (final s in songs) {
      albumsMap.putIfAbsent(s.album, () => []).add(s);
    }
    final sortedAlbums = albumsMap.keys.toList()..sort();

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (ctx, i) {
            final album = sortedAlbums[i];
            final albumSongs = albumsMap[album]!;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.album_rounded, color: AppColors.primary),
              ),
              title: Text(album,
                  style: const TextStyle(
                      color: AppColors.onSurface, fontWeight: FontWeight.bold)),
              subtitle: Text('${albumSongs.first.artist} • ${albumSongs.length} songs',
                  style: const TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12)),
              onTap: () {
                Navigator.of(ctx).push(MaterialPageRoute(
                  builder: (_) => PlaylistDetailScreen(
                    title: album,
                    description: 'Album by ${albumSongs.first.artist}',
                    initialSongs: albumSongs,
                  ),
                ));
              },
            );
          },
          childCount: sortedAlbums.length,
        ),
      ),
    );
  }

  Widget _buildPlaylistsCategory(List<dynamic> playlists) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (ctx, i) {
            final p = playlists[i];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.queue_music_rounded, color: AppColors.primary),
              ),
              title: Text(p.name as String,
                  style: const TextStyle(
                      color: AppColors.onSurface, fontWeight: FontWeight.bold)),
              subtitle: Text('${p.songIds.length} songs',
                  style: const TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12)),
              onTap: () {
                Navigator.of(ctx).push(MaterialPageRoute(
                  builder: (_) => PlaylistDetailScreen(
                    title: p.name as String,
                    description: p.description as String? ?? '',
                    initialSongs: const [],
                    playlistId: p.id as String,
                  ),
                ));
              },
            );
          },
          childCount: playlists.length,
        ),
      ),
    );
  }
}

class _GenreCard extends StatelessWidget {
  final Map<String, dynamic> genre;
  final VoidCallback? onTap;

  const _GenreCard({required this.genre, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: genre['color'] as Color,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            Text(
              genre['name'] as String,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            Positioned(
              right: -8,
              bottom: -8,
              child: Transform.rotate(
                angle: 0.44,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.music_note_rounded,
                      color: Colors.white54, size: 28),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
