import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../providers/app_providers.dart';
import '../providers/album_art_provider.dart';
import '../screens/home/home_screen.dart';
import '../screens/search/search_screen.dart';
import '../screens/library/library_screen.dart';
import '../screens/ai_moods/ai_moods_screen.dart';
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

    final screens = [
      const HomeScreen(),
      const SearchScreen(),
      const LibraryScreen(),
      const AIMoodsScreen(),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: currentScreen.index,
        children: screens,
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
    );
  }
}
