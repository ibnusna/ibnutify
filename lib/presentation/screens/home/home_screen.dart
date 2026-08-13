import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format_utils.dart';
import '../../../data/models/song_model.dart';
import '../../providers/app_providers.dart';
import '../../screens/player/player_screen.dart';
import '../../screens/workout/workout_history_screen.dart';
import '../../widgets/common/song_artwork_widget.dart';
import '../library/playlist_detail_screen.dart';

/// Home Screen — mirrors HomeView.tsx
/// Sections: greeting + filter pills, quick-access grid, recently played, made for you
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songsAsync = ref.watch(songsProvider);
    final playerNotifier = ref.read(playerProvider.notifier);

    return CustomScrollView(
      slivers: [
        // ── Header ──────────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 48, 16, 0),
            child: Row(
              children: [
                // Avatar (User) -> navigate to Your Library
                GestureDetector(
                  onTap: () => ref
                      .read(navigationProvider.notifier)
                      .navigate(AppScreen.library),
                  child: Container(
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
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    getGreeting(),
                    style: const TextStyle(
                      color: AppColors.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                // Workout icon [before bell]
                GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    PageRouteBuilder(
                      pageBuilder: (_, __, ___) =>
                          const WorkoutHistoryScreen(),
                      transitionsBuilder: (_, animation, __, child) =>
                          SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 1),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutCubic)),
                        child: child,
                      ),
                      transitionDuration: const Duration(milliseconds: 380),
                    ),
                  ),
                  child: const Icon(
                    Icons.directions_run_rounded,
                    color: AppColors.onSurfaceVariant,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                // Timer icon (middle) -> navigate to Recently Played
                GestureDetector(
                  onTap: () async {
                    final recently = await ref
                        .read(musicRepositoryProvider)
                        .getRecentlyPlayed24h(limit: 100);
                    if (context.mounted) {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => PlaylistDetailScreen(
                          title: 'Recently Played',
                          description: 'Songs played recently',
                          initialSongs: recently,
                        ),
                      ));
                    }
                  },
                  child: const Icon(Icons.timer_rounded,
                      color: AppColors.onSurfaceVariant, size: 24),
                ),
                const SizedBox(width: 16),
                // Settings icon -> navigate to Your Library
                GestureDetector(
                  onTap: () => ref
                      .read(navigationProvider.notifier)
                      .navigate(AppScreen.library),
                  child: const Icon(Icons.settings_rounded,
                      color: AppColors.onSurfaceVariant, size: 24),
                ),
              ],
            ),
          ),
        ),

        // ── Filter Pills ────────────────────────────────────────────────────
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterPill(label: 'Music', selected: true),
                  SizedBox(width: 8),
                  _FilterPill(label: 'Podcasts & Shows'),
                ],
              ),
            ),
          ),
        ),

        // ── ML Progress Banner ──────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Consumer(
            builder: (context, ref, child) {
              final progress = ref.watch(mlProgressProvider);
              if (progress == null) return const SizedBox.shrink();
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
                        progress,
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
        ),

        // ── Quick Access Grid (2-col) ───────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: songsAsync.when(
              loading: () => _QuickAccessGridSkeleton(),
              error: (_, __) => const SizedBox.shrink(),
              data: (songs) {
                final castSongs = songs.cast<SongModel>();
                if (castSongs.isEmpty) return const SizedBox.shrink();
                final gridSongs = ref.watch(randomHomeSongsProvider);
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 3.2,
                  ),
                  itemCount: gridSongs.length,
                  itemBuilder: (ctx, i) => _QuickAccessCard(
                    song: gridSongs[i],
                    allSongs: castSongs,
                    onTap: () {
                      playerNotifier.playSong(gridSongs[i], castSongs);
                      Navigator.of(context).push(_playerRoute());
                    },
                  ),
                );
              },
            ),
          ),
        ),

        // ── Your Local Songs ────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
            child: Consumer(
              builder: (context, ref, child) {
                return Row(
                  children: [
                    const Text(
                      'Recently Played',
                      style: TextStyle(
                        color: AppColors.onSurface,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => ref
                          .read(navigationProvider.notifier)
                          .navigate(AppScreen.library),
                      child: const Text(
                        'SHOW ALL',
                        style: TextStyle(
                          color: AppColors.onSurfaceVariant,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),

        // Horizontal scroll of recently played songs (real 24h history)
        SliverToBoxAdapter(
          child: SizedBox(
            height: 220,
            child: songsAsync.when(
              loading: () => _HorizontalSkeleton(),
              error: (_, __) => const SizedBox.shrink(),
              data: (songs) {
                final castSongs = songs.cast<SongModel>();
                if (castSongs.isEmpty) {
                  return const Center(
                    child: Text(
                      'No songs found. Scan your music from Library.',
                      style: TextStyle(color: AppColors.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                final recentlyAsync = ref.watch(recentlyPlayedProvider);
                final recently = recentlyAsync.value ?? [];
                final displaySongs = recently.isNotEmpty
                    ? recently.take(8).toList()
                    : castSongs.take(8).toList();
                return ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  itemCount: displaySongs.length,
                  itemBuilder: (ctx, i) => _SongCard(
                    song: displaySongs[i],
                    onTap: () {
                      playerNotifier.playSong(displaySongs[i], castSongs);
                      Navigator.of(context).push(_playerRoute());
                    },
                  ),
                );
              },
            ),
          ),
        ),

        // ── Top Songs (listen-through based) ───────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 28, 16, 4),
            child: Consumer(
              builder: (context, ref, child) {
                final topSongsAsync = ref.watch(topSongsProvider);
                final songs = topSongsAsync.value ?? [];

                return Row(
                  children: [
                    const Text(
                      'On Repeat',
                      style: TextStyle(
                        color: AppColors.onSurface,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => PlaylistDetailScreen(
                            title: 'On Repeat',
                            description: 'Songs you listen to the most.',
                            initialSongs: songs,
                          ),
                        ));
                      },
                      child: const Text(
                        'SHOW ALL',
                        style: TextStyle(
                          color: AppColors.onSurfaceVariant,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),

        SliverToBoxAdapter(
          child: SizedBox(
            height: 220,
            child: songsAsync.when(
              loading: () => _HorizontalSkeleton(),
              error: (_, __) => const SizedBox.shrink(),
              data: (songs) {
                final castSongs = songs.cast<SongModel>();
                final topSongsAsync = ref.watch(topSongsProvider);
                final topSongs = topSongsAsync.value ?? [];
                final displaySongs = topSongs.isNotEmpty
                    ? topSongs.take(8).toList()
                    : castSongs.take(8).toList();
                if (displaySongs.isEmpty) return const SizedBox.shrink();
                return ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  itemCount: displaySongs.length,
                  itemBuilder: (ctx, i) => _SongCard(
                    song: displaySongs[i],
                    onTap: () {
                      playerNotifier.playSong(displaySongs[i], castSongs);
                      Navigator.of(context).push(_playerRoute());
                    },
                  ),
                );
              },
            ),
          ),
        ),

        // ── Daily Mixes ───────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Consumer(
            builder: (context, ref, child) {
              final dailyMixes = ref.watch(dailyMixesProvider);
              if (dailyMixes.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 28, 16, 4),
                    child: Text(
                      'Made For You (Daily Mix)',
                      style: TextStyle(
                        color: AppColors.onSurface,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 220,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      itemCount: dailyMixes.length,
                      itemBuilder: (ctx, i) {
                        final mix = dailyMixes[i];
                        return _NamedPlaylistCard(
                          playlist: mix,
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
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),

        // ── Song Eras ─────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Consumer(
            builder: (context, ref, child) {
              final eras = ref.watch(songErasProvider);
              if (eras.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 28, 16, 4),
                    child: Text(
                      'Song Eras',
                      style: TextStyle(
                        color: AppColors.onSurface,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 220,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      itemCount: eras.length,
                      itemBuilder: (ctx, i) {
                        final era = eras[i];
                        return _NamedPlaylistCard(
                          playlist: era,
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
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),

        const SliverPadding(padding: EdgeInsets.only(bottom: 160)),
      ],
    );
  }

  PageRouteBuilder _playerRoute() => PageRouteBuilder(
        pageBuilder: (_, __, ___) => const PlayerScreen(),
        transitionsBuilder: (_, animation, __, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 350),
      );
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _FilterPill extends StatelessWidget {
  final String label;
  final bool selected;

  const _FilterPill({required this.label, this.selected = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.onSurface
            : AppColors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? AppColors.background : AppColors.onSurface,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _QuickAccessCard extends StatelessWidget {
  final SongModel song;
  final List<SongModel> allSongs;
  final VoidCallback onTap;

  const _QuickAccessCard({
    required this.song,
    required this.allSongs,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            SongArtworkWidget(song: song, size: 56, borderRadius: 6),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                song.title,
                style: const TextStyle(
                  color: AppColors.onSurface,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SongCard extends StatelessWidget {
  final SongModel song;
  final VoidCallback onTap;

  const _SongCard({required this.song, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        margin: const EdgeInsets.only(right: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                SongArtworkWidget(
                  song: song,
                  size: 140,
                  borderRadius: 8,
                  fit: BoxFit.cover,
                ),
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.play_arrow_rounded,
                        color: AppColors.background, size: 20),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              song.title,
              style: const TextStyle(
                color: AppColors.onSurface,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              song.artist,
              style: const TextStyle(
                color: AppColors.onSurfaceVariant,
                fontSize: 10,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAccessGridSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 3.2,
      ),
      itemCount: 6,
      itemBuilder: (_, __) => Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }
}

class _HorizontalSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      itemCount: 5,
      itemBuilder: (_, __) => Container(
        width: 140,
        margin: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

class _NamedPlaylistCard extends StatelessWidget {
  final NamedPlaylist playlist;
  final VoidCallback onTap;

  const _NamedPlaylistCard({required this.playlist, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        margin: const EdgeInsets.only(right: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover
            if (playlist.songs.isNotEmpty)
              SongArtworkWidget(
                song: playlist.songs.first,
                size: 140,
                borderRadius: 8,
              )
            else
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withOpacity(0.4),
                      AppColors.surfaceContainerHigh,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: const Icon(
                  Icons.library_music_rounded,
                  size: 48,
                  color: AppColors.primary,
                ),
              ),
            const SizedBox(height: 8),
            // Title
            Text(
              playlist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            // Description
            Text(
              playlist.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
