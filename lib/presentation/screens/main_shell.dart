import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../providers/app_providers.dart';
import '../providers/album_art_provider.dart';
import '../screens/home/home_screen.dart';
import '../screens/search/search_screen.dart';
import '../screens/library/library_screen.dart';
import '../screens/ai_moods/ai_moods_screen.dart';
import '../screens/workout/workout_active_screen.dart';
import '../widgets/player/mini_player.dart';
import 'package:ibnutify/services/auto_lyrics_downloader.dart';

/// Main scaffold — mirrors Layout.tsx
/// Contains: bottom nav + mini player + screen switcher
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  @override
  void initState() {
    super.initState();
    // Start background auto-downloader for lyrics
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AutoLyricsDownloader.instance.start(ref.read(musicLocalDatasourceProvider));
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentScreen = ref.watch(navigationProvider);

    // Keep albumArtProvider alive at all times so artwork + palette are
    // already computed by the time the user opens PlayerScreen or reads
    // the mini player gradient. Without this, the provider is only created
    // when those widgets first build, causing the first-open to always
    // show the fallback green instead of the real album color.
    ref.watch(albumArtProvider);

    ref.listen<AppScreen>(navigationProvider, (_, __) {
      FocusManager.instance.primaryFocus?.unfocus();
    });

    final screens = [
      const HomeScreen(),
      const SearchScreen(),
      const LibraryScreen(),
      const AIMoodsScreen(),
    ];

    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: IndexedStack(
          index: currentScreen.index,
          children: screens,
        ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Workout Mini Banner (di atas MiniPlayer, hanya saat workout aktif)
          const _WorkoutMiniBanner(),

          // Mini Player (above nav)
          const MiniPlayer(),

          // Bottom navigation
          Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant.withOpacity(0.95),
              border: Border(
                top: BorderSide(color: Colors.white.withOpacity(0.05)),
              ),
            ),
            child: SafeArea(
              top: false,
              child: BottomNavigationBar(
                currentIndex: currentScreen.index,
                onTap: (i) {
                  FocusScope.of(context).unfocus();
                  ref.read(navigationProvider.notifier).navigate(AppScreen.values[i]);
                },
                backgroundColor: Colors.transparent,
                elevation: 0,
                selectedItemColor: AppColors.onSurface,
                unselectedItemColor: AppColors.onSurfaceVariant,
                selectedLabelStyle: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: const TextStyle(fontSize: 10),
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.home_rounded),
                    activeIcon: Icon(Icons.home_rounded, size: 26),
                    label: 'Home',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.search_rounded),
                    activeIcon: Icon(Icons.search_rounded, size: 26),
                    label: 'Search',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.library_music_rounded),
                    activeIcon: Icon(Icons.library_music_rounded, size: 26),
                    label: 'Your Library',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.auto_awesome_rounded),
                    activeIcon: Icon(Icons.auto_awesome_rounded, size: 26),
                    label: 'AI Moods',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }
}

// ─── Workout Mini Banner ───────────────────────────────────────────────────────

/// Banner kecil yang tampil di atas MiniPlayer saat mode olahraga aktif di background.
/// Klik untuk kembali ke WorkoutActiveScreen.
class _WorkoutMiniBanner extends ConsumerWidget {
  const _WorkoutMiniBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workout = ref.watch(workoutProvider);

    // Hanya tampil saat olahraga sedang berjalan
    if (!workout.isRunning) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () {
        // Kembali ke WorkoutActiveScreen (push — bukan pushReplacement)
        Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => WorkoutActiveScreen(
              sportMode: workout.sportMode,
            ),
            transitionsBuilder: (_, animation, __, child) => SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                  parent: animation, curve: Curves.easeOutCubic)),
              child: child,
            ),
            transitionDuration: const Duration(milliseconds: 350),
          ),
        );
      },
      child: Container(
        height: 48,
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              AppColors.primary.withOpacity(0.85),
              AppColors.primary.withOpacity(0.60),
            ],
          ),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            // Pulse indicator
            const _PulsingDot(),
            const SizedBox(width: 8),
            // Sport icon
            Icon(
              _sportIcon(workout.sportMode),
              color: AppColors.background,
              size: 18,
            ),
            const SizedBox(width: 8),
            // Stats
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    workout.isPaused
                        ? '${workout.sportMode} — PAUSED'
                        : '${workout.sportMode} — AKTIF',
                    style: const TextStyle(
                      color: AppColors.background,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    '${workout.formattedDuration}  •  ${workout.distanceKm.toStringAsFixed(2)} km',
                    style: TextStyle(
                      color: AppColors.background.withOpacity(0.85),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            // Chevron
            Icon(
              Icons.chevron_right_rounded,
              color: AppColors.background.withOpacity(0.8),
              size: 20,
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  IconData _sportIcon(String mode) {
    switch (mode) {
      case 'Berlari':
        return Icons.directions_run_rounded;
      case 'Sepeda':
        return Icons.directions_bike_rounded;
      case 'Berjalan':
        return Icons.directions_walk_rounded;
      case 'Mendaki':
        return Icons.landscape_rounded;
      default:
        return Icons.fitness_center_rounded;
    }
  }
}

/// Titik berkedip untuk indikator aktif di workout mini banner.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _anim,
        child: Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: AppColors.background,
            shape: BoxShape.circle,
          ),
        ),
      );
}
