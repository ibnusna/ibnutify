import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format_utils.dart';
import '../../providers/app_providers.dart';
import '../../providers/album_art_provider.dart';
import '../../providers/lyrics_provider.dart';
import '../../providers/connectivity_provider.dart';
import '../../../services/album_art_service.dart';
import '../../widgets/common/song_artwork_widget.dart';
import '../../widgets/player/more_options_sheet.dart';
import '../../widgets/player/music_video_player.dart';
import '../queue/queue_screen.dart';
import 'lyrics_screen.dart';

/// Full Player Screen — mirrors PlayerDetail.tsx
/// Features Spotify-style dynamic background that adapts to album art colors.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with TickerProviderStateMixin {
  late final AnimationController _gradientController;
  late final AnimationController _artController;

  List<Color> _previousGradient = AlbumArtService.kFallbackGradient;
  List<Color> _targetGradient = AlbumArtService.kFallbackGradient;

  @override
  void initState() {
    super.initState();
    _gradientController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _artController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..value = 1.0;

    // Sync gradient from any already-resolved AlbumArtState.
    // This handles the common case: user taps a song → song plays →
    // album art is already extracted → player screen opens.
    // ref.read is safe in initState only via post-frame callback.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = ref.read(albumArtProvider);
      if (!current.isLoading) {
        setState(() {
          _previousGradient = current.gradientColors;
          _targetGradient = current.gradientColors;
          _gradientController.value = 1.0;
        });
      }
      // Warm up lyrics provider so it starts fetching immediately
      ref.read(lyricsProvider);
    });
  }

  @override
  void dispose() {
    _gradientController.dispose();
    _artController.dispose();
    super.dispose();
  }

  void _animateToGradient(List<Color> newGradient) {
    _previousGradient = _targetGradient;
    _targetGradient = newGradient;
    _gradientController.forward(from: 0);
    _artController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerProvider);
    final currentSong = playerState.currentSong;
    final albumArtState = ref.watch(albumArtProvider);
    final isVideoMode = ref.watch(isVideoModeProvider);
    final isOffline = ref.watch(isOfflineProvider);
    final hasVideo = currentSong?.youtubeUrl != null && currentSong!.youtubeUrl!.isNotEmpty;

    // Trigger gradient animation when colors change
    ref.listen<AlbumArtState>(albumArtProvider, (prev, next) {
      if (prev?.gradientColors != next.gradientColors) {
        _animateToGradient(next.gradientColors);
      }
    });

    if (currentSong == null) {
      Navigator.of(context).pop();
      return const SizedBox.shrink();
    }

    final progress = playerState.duration.inMilliseconds > 0
        ? playerState.position.inMilliseconds /
            playerState.duration.inMilliseconds
        : 0.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // ── Animated dynamic background gradient (Adaptive Spotify Mesh) ──
          AnimatedBuilder(
            animation: _gradientController,
            builder: (context, _) {
              final t = Curves.easeInOut.transform(_gradientController.value);
              final interpolated = List.generate(
                _targetGradient.length,
                (i) {
                  final prevColor = i < _previousGradient.length
                      ? _previousGradient[i]
                      : _previousGradient.last;
                  return Color.lerp(prevColor, _targetGradient[i], t)!;
                },
              );
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.55, 1.0],
                    colors: interpolated.length >= 3
                        ? interpolated
                        : [
                            interpolated.first,
                            Color.lerp(interpolated.first, AppColors.background, 0.5)!,
                            AppColors.background,
                          ],
                  ),
                ),
              );
            },
          ),

          // ── Subtle gradient vignette to protect text & controls readability ──
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.5, 1.0],
                  colors: [
                    Colors.black.withOpacity(0.0),
                    Colors.black.withOpacity(0.05),
                    Colors.black.withOpacity(0.25),
                  ],
                ),
              ),
            ),
          ),

          // ── Main content ──────────────────────────────────────────────────
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          children: [
                            // Header row
                            Padding(
                              padding: const EdgeInsets.only(top: 16, bottom: 24),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        color: AppColors.onSurface, size: 32),
                                    onPressed: () => Navigator.of(context).pop(),
                                  ),
                                  const Text(
                                    'NOW PLAYING',
                                    style: TextStyle(
                                      color: AppColors.onSurface,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 2,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.more_vert_rounded,
                                        color: AppColors.onSurface, size: 24),
                                    onPressed: () {
                                      showModalBottomSheet(
                                        context: context,
                                        isScrollControlled: true,
                                        backgroundColor: Colors.transparent,
                                        builder: (_) =>
                                            MoreOptionsSheet(song: currentSong),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),

                            // Album art
                            Expanded(
                              child: Center(
                                child: AspectRatio(
                                  aspectRatio: (isVideoMode && hasVideo) ? 16 / 9 : 1,
                                  child: AnimatedBuilder(
                                    animation: _artController,
                                    builder: (_, child) => Transform.scale(
                                      scale: 0.92 + (_artController.value * 0.08),
                                      child: Opacity(
                                        opacity: _artController.value,
                                        child: child,
                                      ),
                                    ),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: [
                                          BoxShadow(
                                            color: albumArtState.dominantColor
                                                .withOpacity(albumArtState
                                                        .isLoading
                                                    ? 0.3
                                                    : 0.55),
                                            blurRadius: 70,
                                            spreadRadius: 4,
                                            offset: const Offset(0, 20),
                                          ),
                                          BoxShadow(
                                            color:
                                                Colors.black.withOpacity(0.5),
                                            blurRadius: 40,
                                            offset: const Offset(0, 15),
                                          ),
                                        ],
                                      ),
                                      child: isVideoMode && hasVideo
                                          ? MusicVideoPlayer(youtubeUrl: currentSong.youtubeUrl!)
                                          : SongArtworkWidget(
                                              song: currentSong,
                                              size: double.infinity,
                                              borderRadius: 16,
                                              fit: BoxFit.cover,
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 24),

                            // Song info + add button
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        currentSong.title,
                                        style: const TextStyle(
                                          color: AppColors.onSurface,
                                          fontSize: 22,
                                          fontWeight: FontWeight.w900,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        currentSong.artist,
                                        style: const TextStyle(
                                          color: AppColors.onSurfaceVariant,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                // F1: Tombol + / check untuk Liked Songs
                                Consumer(
                                  builder: (_, ref, __) {
                                    final isLiked = ref
                                        .watch(playlistsProvider.notifier)
                                        .isInLikedSongs(currentSong.id);
                                    return GestureDetector(
                                      onTap: () async {
                                        await ref
                                            .read(playlistsProvider.notifier)
                                            .addToLikedSongs(currentSong.id);
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                isLiked
                                                    ? 'Already in Liked Songs'
                                                    : 'Added to Liked Songs',
                                              ),
                                              backgroundColor:
                                                  AppColors.surfaceVariant,
                                              behavior:
                                                  SnackBarBehavior.floating,
                                              duration: const Duration(
                                                  seconds: 2),
                                            ),
                                          );
                                        }
                                      },
                                      child: AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 250),
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: isLiked
                                              ? AppColors.primary
                                                  .withOpacity(0.15)
                                              : Colors.transparent,
                                          border: Border.all(
                                            color: isLiked
                                                ? AppColors.primary
                                                : Colors.white.withOpacity(
                                                    0.15),
                                          ),
                                        ),
                                        child: Icon(
                                          isLiked
                                              ? Icons.check_rounded
                                              : Icons.add_rounded,
                                          color: isLiked
                                              ? AppColors.primary
                                              : AppColors.onSurface,
                                          size: 20,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),

                            const SizedBox(height: 20),

                            // Seek bar
                            Column(
                              children: [
                                SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    activeTrackColor: AppColors.onSurface,
                                    inactiveTrackColor:
                                        Colors.white.withOpacity(0.2),
                                    thumbColor: AppColors.onSurface,
                                    overlayColor:
                                        AppColors.onSurface.withOpacity(0.1),
                                    trackHeight: 3,
                                    thumbShape:
                                        const RoundSliderThumbShape(
                                            enabledThumbRadius: 5),
                                  ),
                                  child: Slider(
                                    value: progress.clamp(0.0, 1.0),
                                    onChanged: (v) {
                                      ref
                                          .read(playerProvider.notifier)
                                          .seek(v * 100);
                                    },
                                  ),
                                ),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      formatDuration(playerState.position),
                                      style: const TextStyle(
                                        color: AppColors.onSurfaceVariant,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      formatDuration(playerState.duration),
                                      style: const TextStyle(
                                        color: AppColors.onSurfaceVariant,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            // Main controls
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    Icons.shuffle_rounded,
                                    color: playerState.isShuffle
                                        ? AppColors.primary
                                        : AppColors.onSurface.withOpacity(0.6),
                                    size: 24,
                                  ),
                                  onPressed: () => ref
                                      .read(playerProvider.notifier)
                                      .toggleShuffle(),
                                ),
                                Row(
                                  children: [
                                    GestureDetector(
                                      onTap: () => ref
                                          .read(playerProvider.notifier)
                                          .previousTrack(),
                                      child: const Icon(
                                          Icons.skip_previous_rounded,
                                          color: AppColors.onSurface,
                                          size: 44),
                                    ),
                                    const SizedBox(width: 32),
                                    GestureDetector(
                                      onTap: () => ref
                                          .read(playerProvider.notifier)
                                          .togglePlay(),
                                      child: AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 200),
                                        width: 64,
                                        height: 64,
                                        decoration: const BoxDecoration(
                                          color: AppColors.onSurface,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          playerState.isPlaying
                                              ? Icons.pause_rounded
                                              : Icons.play_arrow_rounded,
                                          color: AppColors.background,
                                          size: 34,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 32),
                                    GestureDetector(
                                      onTap: () => ref
                                          .read(playerProvider.notifier)
                                          .nextTrack(),
                                      child: const Icon(
                                          Icons.skip_next_rounded,
                                          color: AppColors.onSurface,
                                          size: 44),
                                    ),
                                  ],
                                ),
                                IconButton(
                                  icon: Icon(
                                    playerState.repeatMode == RepeatMode.one
                                        ? Icons.repeat_one_rounded
                                        : Icons.repeat_rounded,
                                    color: playerState.repeatMode !=
                                            RepeatMode.off
                                        ? AppColors.primary
                                        : AppColors.onSurface.withOpacity(0.6),
                                    size: 24,
                                  ),
                                  onPressed: () => ref
                                      .read(playerProvider.notifier)
                                      .cycleRepeat(),
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            // Footer: device icon + queue button
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                hasVideo
                                    ? GestureDetector(
                                        onTap: isOffline
                                            ? () {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                        'Video tidak tersedia tanpa koneksi internet'),
                                                    behavior:
                                                        SnackBarBehavior.floating,
                                                  ),
                                                );
                                              }
                                            : () {
                                                ref
                                                    .read(isVideoModeProvider
                                                        .notifier)
                                                    .state = !isVideoMode;
                                              },
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                              milliseconds: 250),
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: isOffline
                                                ? Colors.transparent
                                                : (isVideoMode
                                                    ? AppColors.primary
                                                        .withOpacity(0.2)
                                                    : Colors.transparent),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Icon(
                                            isVideoMode
                                                ? Icons.videocam_rounded
                                                : Icons.videocam_outlined,
                                            color: isOffline
                                                ? AppColors.onSurfaceVariant
                                                    .withOpacity(0.3)
                                                : (isVideoMode
                                                    ? AppColors.primary
                                                    : AppColors
                                                        .onSurfaceVariant),
                                            size: 20,
                                          ),
                                        ),
                                      )
                                    : const Icon(Icons.phone_android_rounded,
                                        color: AppColors.onSurfaceVariant,
                                        size: 20),

                                // Spacer tengah
                                const SizedBox.shrink(),

                                IconButton(
                                  icon: const Icon(Icons.queue_music_rounded,
                                      color: AppColors.onSurfaceVariant,
                                      size: 24),
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      PageRouteBuilder(
                                        pageBuilder: (_, __, ___) =>
                                            const QueueScreen(),
                                        transitionsBuilder:
                                            (_, anim, __, child) =>
                                                SlideTransition(
                                          position: Tween<Offset>(
                                            begin: const Offset(0, 1),
                                            end: Offset.zero,
                                          ).animate(CurvedAnimation(
                                              parent: anim,
                                              curve: Curves.easeOutCubic)),
                                          child: child,
                                        ),
                                        transitionDuration:
                                            const Duration(milliseconds: 300),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),

                            const SizedBox(height: 16),

                            // ── Lyrics Peek Card ─────────────────────────────
                            // Mirip Spotify: kartu biru rounded di bawah player
                            // User bisa scroll up atau tap untuk buka full view
                            Consumer(
                              builder: (_, ref, __) {
                                final lyrics = ref.watch(lyricsProvider);
                                final art = ref.watch(albumArtProvider);
                                return _LyricsPeekCard(
                                  lyricsState: lyrics,
                                  dominantColor: art.dominantColor,
                                  onTap: () => _openLyrics(context),
                                );
                              },
                            ),

                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openLyrics(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const LyricsScreen(),
        transitionsBuilder: (_, anim, __, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }
}

// ─── Lyrics Peek Card ─────────────────────────────────────────────────────────

/// Card "Pratinjau lirik" yang muncul di bawah player, persis referensi.
/// Menampilkan 3 baris lirik pertama dengan warna kartu dinamis.
class _LyricsPeekCard extends ConsumerWidget {
  final LyricsState lyricsState;
  final Color dominantColor;
  final VoidCallback onTap;

  const _LyricsPeekCard({
    required this.lyricsState,
    required this.dominantColor,
    required this.onTap,
  });

  Color get _cardColor {
    // Warna kartu mengikuti dominant color album art (tidak di-shift ke biru).
    // Darkened + desaturated agar kontras dengan teks putih, seperti Spotify.
    final hsl = HSLColor.fromColor(dominantColor);
    return HSLColor.fromAHSL(
      1.0,
      hsl.hue,                                          // hue asli album art
      (hsl.saturation * 0.75).clamp(0.25, 0.85),        // slight desaturate
      (hsl.lightness * 0.40).clamp(0.10, 0.30),         // darkened
    ).toColor();
  }

  /// Ukuran font tetap (tidak adaptif) agar tampilan konsisten antar lagu.
  double _adaptiveFontSize(List<String> lines) {
    return 16.0;
  }

  List<String> _previewLines(String lyrics) {
    return lyrics
        .replaceAll(RegExp(r'\[\d+:\d+(?:\.\d+)?\]'), '') // Strip timestamps
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .take(4)
        .toList();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
        width: double.infinity,
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row (Watermark lrclib dihapus sesuai permintaan)
            const Text(
              'Pratinjau lirik',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),

            const SizedBox(height: 14),

            // Content
            if (lyricsState.isLoading)
              _buildLoadingState()
            else if (lyricsState.hasLyrics)
              _buildLyricsPreview(lyricsState, ref.watch(playerProvider.select((p) => p.position)))
            else
              _buildEmptyState(lyricsState),

            const SizedBox(height: 16),

            // "Tampilkan lirik" button
            GestureDetector(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  lyricsState.hasLyrics ? 'Tampilkan lirik' : 'Cari lirik',
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Column(
      children: List.generate(
        3,
        (i) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            height: 18,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLyricsPreview(LyricsState state, Duration position) {
    List<String> lines = [];
    int activeIndex = -1;

    if (state.hasSyncedLyrics) {
      final synced = state.syncedLines!;
      int newIndex = -1;
      for (int i = 0; i < synced.length; i++) {
        if (position >= synced[i].timestamp) {
          newIndex = i;
        } else {
          break;
        }
      }
      
      activeIndex = newIndex < 0 ? 0 : newIndex;
      
      // Get up to 4 lines starting from the active index (or slightly before if near end)
      int startIdx = activeIndex;
      int endIdx = startIdx + 4;
      if (endIdx > synced.length) {
        endIdx = synced.length;
      }
      
      for (int i = startIdx; i < endIdx; i++) {
        lines.add(synced[i].text);
      }
      
      // Adjust active index relative to the extracted window
      activeIndex = newIndex < 0 ? -1 : 0; 
    } else {
      lines = _previewLines(state.lyrics!);
    }

    final fontSize = _adaptiveFontSize(lines);
    // Hapus SizedBox agar tinggi preview fleksibel menyesuaikan layar / lirik
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: lines.asMap().entries.map((e) {
        final isHighlighted = state.hasSyncedLyrics
            ? (e.key == activeIndex)
            : (e.key == lines.length - 1);

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 300),
            style: TextStyle(
              color: isHighlighted
                  ? Colors.white
                  : Colors.white.withOpacity(0.55),
              fontSize: isHighlighted ? fontSize + 4 : fontSize,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            child: Text(e.value),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildEmptyState(LyricsState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Lirik tidak ditemukan.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.55),
              fontSize: 14,
              height: 1.6,
            ),
          ),
          if (state.debugMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              'DEBUG:\n${state.debugMessage}',
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
