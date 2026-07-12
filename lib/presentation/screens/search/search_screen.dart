import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../../widgets/common/song_list_tile.dart';

/// Search Screen — mirrors SearchView.tsx
/// Real-time search with genre grid browse
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

  @override
  Widget build(BuildContext context) {
    final searchResultsAsync = ref.watch(searchResultsProvider);
    final searchResults = searchResultsAsync.value ?? [];

    return CustomScrollView(
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
                  suffixIcon: _isSearching
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded,
                              color: AppColors.background),
                          onPressed: () {
                            _controller.clear();
                            ref.read(searchQueryProvider.notifier).update('');
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

        // ── Filter Chips ────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['All', 'Artists', 'Albums', 'Playlists']
                    .asMap()
                    .entries
                    .map((e) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 8),
                            decoration: BoxDecoration(
                              color: e.key == 0
                                  ? AppColors.primary
                                  : AppColors.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              e.value,
                              style: TextStyle(
                                color: e.key == 0
                                    ? AppColors.background
                                    : AppColors.onSurface,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ),
        ),

        // ── Search Results or Genre Grid ────────────────────────────────────
        if (_isSearching) ...[
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
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final song = searchResults[i];
                    final allSongs = searchResults;
                    return SongListTile(
                      song: song,
                      // Build context-aware queue: same-artist songs first,
                      // then alphabetical continuation from the selected song.
                      queue: ref
                          .read(playerProvider.notifier)
                          .buildContextualQueue(song, allSongs),
                    );
                  },
                  childCount: searchResults.length,
                ),
              ),
            ),
        ] else ...[
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 24, 16, 4),
              child: Text(
                'Browse all',
                style: TextStyle(
                  color: AppColors.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
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
                (ctx, i) => _GenreCard(genre: _genres[i]),
                childCount: _genres.length,
              ),
            ),
          ),
        ],

        const SliverPadding(padding: EdgeInsets.only(bottom: 160)),
      ],
    );
  }
}

class _GenreCard extends StatelessWidget {
  final Map<String, dynamic> genre;

  const _GenreCard({required this.genre});

  @override
  Widget build(BuildContext context) {
    return Container(
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
    );
  }
}
