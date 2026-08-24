import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/song_model.dart';
import '../../providers/app_providers.dart';
import '../../widgets/common/song_artwork_widget.dart';
import '../../widgets/player/more_options_sheet.dart';
import '../../widgets/workout/osm_map_widget.dart';
import 'workout_history_screen.dart';
import 'workout_summary_screen.dart';
import 'watch_pairing_sheet.dart';
import '../../../services/sensor_fusion_engine.dart';

/// WorkoutActiveScreen — layar pelacakan GPS real-time + Pace Match music.
/// Dikonversi dari workout_tracking_live/code.html
class WorkoutActiveScreen extends ConsumerStatefulWidget {
  final String sportMode;
  final SongModel? initialSong; // optional: dari More Options Sheet

  const WorkoutActiveScreen({
    super.key,
    required this.sportMode,
    this.initialSong,
  });

  @override
  ConsumerState<WorkoutActiveScreen> createState() =>
      _WorkoutActiveScreenState();
}

class _WorkoutActiveScreenState extends ConsumerState<WorkoutActiveScreen>
    with TickerProviderStateMixin {
  bool _locationDenied = false;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _startWorkout());
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _startWorkout() async {
    // Jika ada initialSong (dari titik 3 MoreOptionsSheet), putar lagu tersebut jika belum menjadi lagu aktif
    if (widget.initialSong != null) {
      final playerNotifier = ref.read(playerProvider.notifier);
      final currentSong = ref.read(playerProvider).currentSong;
      if (currentSong?.id != widget.initialSong!.id) {
        final allSongs = ref.read(songsProvider).value ?? [];
        final queue = allSongs.contains(widget.initialSong) ? allSongs : [widget.initialSong!];
        await playerNotifier.playSong(widget.initialSong!, queue);
      } else if (!ref.read(playerProvider).isPlaying) {
        playerNotifier.togglePlay();
      }
    }

    final currentSong = ref.read(playerProvider).currentSong;
    final useCurrentQueue = widget.initialSong != null || currentSong != null;

    final ok = await ref
        .read(workoutProvider.notifier)
        .startWorkout(widget.sportMode, useCurrentQueue: useCurrentQueue);
    if (!mounted) return;
    if (!ok) {
      setState(() => _locationDenied = true);
      _showLocationDeniedDialog();
    }
  }

  void _showLocationDeniedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        title: const Text('Izin Lokasi Diperlukan',
            style: TextStyle(color: AppColors.onSurface)),
        content: const Text(
          'Mode Olahraga membutuhkan akses GPS untuk melacak rute.\n\n'
          'Aktifkan izin lokasi di Pengaturan > Aplikasi > IbnuTify > Izin.',
          style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: const Text('Kembali',
                style: TextStyle(color: AppColors.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }

  Future<void> _onStop() async {
    final snapshot =
        await ref.read(workoutProvider.notifier).stopWorkout();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) =>
            WorkoutSummaryScreen(snapshot: snapshot),
        transitionsBuilder: (_, animation, __, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  IconData get _sportIcon {
    switch (widget.sportMode) {
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

  /// [Bug 2 Fix] Dialog back: pilih antara lanjut di background atau keluar/stop.
  Future<void> _onBackPressed() async {
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        title: const Text('Mode Olahraga Aktif',
            style: TextStyle(color: AppColors.onSurface)),
        content: const Text(
          'Sesi olahraga masih berjalan.\n\nPilih tindakan:',
          style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('cancel'),
            child: const Text('Batal',
                style: TextStyle(color: AppColors.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('background'),
            child: const Text(
              'Lanjut di Background',
              style: TextStyle(
                  color: AppColors.primary, fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('stop'),
            child: const Text(
              'Hentikan & Keluar',
              style: TextStyle(
                  color: Colors.redAccent, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (choice == 'background') {
      // Lanjut berjalan di background — pop layar saja, workout tetap jalan
      Navigator.of(context).pop();
    } else if (choice == 'stop') {
      // Hentikan workout dan kembali ke WorkoutHistoryScreen
      await ref.read(workoutProvider.notifier).stopWorkout();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const WorkoutHistoryScreen(),
          transitionsBuilder: (_, animation, __, child) => FadeTransition(
            opacity: animation,
            child: child,
          ),
          transitionDuration: const Duration(milliseconds: 300),
        ),
      );
    }
    // 'cancel' atau null: tidak melakukan apa-apa, kembali ke layar
  }

  @override
  Widget build(BuildContext context) {
    final workout = ref.watch(workoutProvider);
    final player = ref.watch(playerProvider);
    final currentSong = player.currentSong;

    return PopScope(
      // [Bug 2 Fix] Intercept hardware back button — tampilkan pilihan Background/Keluar
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _onBackPressed();
      },
      child: Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Subtle gradient header glow
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 200,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.primary.withOpacity(0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // ── App Bar ──────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: AppColors.onSurface),
                        onPressed: _onBackPressed,
                      ),
                      const SizedBox(width: 4),
                      Icon(_sportIcon, color: AppColors.primary, size: 20),
                      const SizedBox(width: 6),
                      Text(
                        widget.sportMode,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      if (workout.isPaused)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                                color: Colors.amber.withOpacity(0.3)),
                          ),
                          child: const Text(
                            'PAUSED',
                            style: TextStyle(
                              color: Colors.amber,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      const SizedBox(width: 8),
                      // Watch connect button
                      IconButton(
                        tooltip: workout.isWatchConnected
                            ? workout.watchDeviceName
                            : 'Hubungkan Smartwatch',
                        icon: Icon(
                          workout.isWatchConnected
                              ? Icons.watch_rounded
                              : Icons.watch_off_rounded,
                          color: workout.isWatchConnected
                              ? AppColors.primary
                              : AppColors.onSurfaceVariant.withOpacity(0.5),
                          size: 22,
                        ),
                        onPressed: () {
                          showModalBottomSheet(
                            context: context,
                            backgroundColor: Colors.transparent,
                            isScrollControlled: true,
                            builder: (_) => const WatchPairingSheet(),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        const SizedBox(height: 16),

                        // ── Timer ────────────────────────────────────
                        Text(
                          'WAKTU',
                          style: TextStyle(
                            color: AppColors.onSurfaceVariant.withOpacity(0.7),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          workout.formattedDuration,
                          style: const TextStyle(
                            color: AppColors.onSurface,
                            fontSize: 64,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -2,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // ── Distance + Pace ──────────────────────────
                        Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 16, horizontal: 20),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.06)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  children: [
                                    Text(
                                      'JARAK',
                                      style: TextStyle(
                                        color: AppColors.onSurfaceVariant
                                            .withOpacity(0.7),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 2,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    RichText(
                                      text: TextSpan(
                                        children: [
                                          TextSpan(
                                            text: workout.distanceKm
                                                .toStringAsFixed(2),
                                            style: const TextStyle(
                                              color: AppColors.onSurface,
                                              fontSize: 28,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          const TextSpan(
                                            text: ' KM',
                                            style: TextStyle(
                                              color: AppColors.onSurfaceVariant,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 48,
                                color: Colors.white.withOpacity(0.08),
                              ),
                              Expanded(
                                child: Column(
                                  children: [
                                    Text(
                                      'PACE',
                                      style: TextStyle(
                                        color: AppColors.onSurfaceVariant
                                            .withOpacity(0.7),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 2,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      workout.currentPace,
                                      style: const TextStyle(
                                        color: AppColors.onSurface,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                         // ── Sensor Fusion Stats Row ───────────────
                        _SensorStatsRow(workout: workout),
                        const SizedBox(height: 16),

                        // ── OSM Map Canvas (realtime) ─────────────────
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Stack(
                            children: [
                              // Tile OSM + route overlay
                              OsmMapWidget(
                                points: workout.routePoints,
                                height: 200,
                                showLiveIndicator: true,
                                isLive: true,
                              ),
                              // Badge GPS accuracy (kanan atas)
                              Positioned(
                                top: 10,
                                right: 10,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.65),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                        color: Colors.white.withOpacity(0.1)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      FadeTransition(
                                        opacity: _pulseAnim,
                                        child: Container(
                                          width: 7,
                                          height: 7,
                                          decoration: BoxDecoration(
                                            color: _locationDenied
                                                ? Colors.redAccent
                                                : AppColors.primary,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _locationDenied
                                            ? 'GPS Nonaktif'
                                            : workout.gpsAccuracy > 0
                                                ? 'Live • ${workout.gpsAccuracy.toStringAsFixed(0)}m'
                                                : 'Live Tracking',
                                        style: TextStyle(
                                          color: workout.gpsAccuracy > 25
                                              ? Colors.orangeAccent
                                              : Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              // Overlay "Menunggu GPS" jika belum ada sinyal
                              if (workout.routePoints.isEmpty && !_locationDenied)
                                Positioned.fill(
                                  child: Container(
                                    color: Colors.black.withOpacity(0.45),
                                    child: Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.gps_fixed_rounded,
                                            color: AppColors.primary.withOpacity(0.7),
                                            size: 32,
                                          ),
                                          const SizedBox(height: 6),
                                          const Text(
                                            'Menunggu sinyal GPS...',
                                            style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          if (workout.gpsAccuracy > 0)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 4),
                                              child: Text(
                                                'Akurasi: ${workout.gpsAccuracy.toStringAsFixed(0)}m',
                                                style: TextStyle(
                                                  color: workout.gpsAccuracy <= 15
                                                      ? AppColors.primary
                                                      : Colors.orangeAccent,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ── Pace Match Music Player ───────────────────
                        if (currentSong != null)
                          _PaceMatchPlayer(song: currentSong),

                        const SizedBox(height: 24),

                        // ── Action Buttons ────────────────────────────
                        Row(
                          children: [
                            Expanded(
                              child: _WorkoutButton(
                                label: workout.isPaused ? 'LANJUT' : 'PAUSE',
                                icon: workout.isPaused
                                    ? Icons.play_arrow_rounded
                                    : Icons.pause_rounded,
                                onTap: () {
                                  if (workout.isPaused) {
                                    ref
                                        .read(workoutProvider.notifier)
                                        .resumeWorkout();
                                  } else {
                                    ref
                                        .read(workoutProvider.notifier)
                                        .pauseWorkout();
                                  }
                                },
                                isPrimary: false,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _WorkoutButton(
                                label: 'SELESAI',
                                icon: Icons.stop_rounded,
                                onTap: _onStop,
                                isPrimary: true,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ), // End Scaffold (child of PopScope)
    ); // End PopScope
  }
}

// ─── Pace Match Player Widget ──────────────────────────────────────────────────

class _PaceMatchPlayer extends ConsumerWidget {
  final SongModel song;
  const _PaceMatchPlayer({required this.song});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerProvider);
    final bpm = song.bpm;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          // Album art + BPM badge
          Stack(
            clipBehavior: Clip.none,
            children: [
              SongArtworkWidget(song: song, size: 56, borderRadius: 10),
              if (bpm != null)
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.background.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${bpm.round()} BPM',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),

          // Song info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.speed_rounded,
                        color: AppColors.primary, size: 12),
                    const SizedBox(width: 4),
                    const Text(
                      'PACE MATCH',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  song.title,
                  style: const TextStyle(
                    color: AppColors.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  song.artist,
                  style: const TextStyle(
                    color: AppColors.onSurfaceVariant,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Controls
          IconButton(
            icon: Icon(
              playerState.isPlaying
                  ? Icons.pause_circle_filled_rounded
                  : Icons.play_circle_filled_rounded,
              color: AppColors.onSurface,
              size: 36,
            ),
            onPressed: () =>
                ref.read(playerProvider.notifier).togglePlay(),
          ),
          IconButton(
            icon: const Icon(Icons.skip_next_rounded,
                color: AppColors.onSurfaceVariant, size: 26),
            onPressed: () =>
                ref.read(playerProvider.notifier).nextTrack(),
          ),
          // Tombol titik tiga — buka MoreOptionsSheet sesuai queue
          IconButton(
            icon: const Icon(Icons.more_vert_rounded,
                color: AppColors.onSurfaceVariant, size: 22),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
                builder: (_) => MoreOptionsSheet(song: song),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─── Workout Action Button ────────────────────────────────────────────────────

class _WorkoutButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isPrimary;

  const _WorkoutButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.isPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isPrimary
                ? AppColors.primary
                : AppColors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
            border: isPrimary
                ? null
                : Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isPrimary ? AppColors.background : AppColors.onSurface,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color:
                      isPrimary ? AppColors.background : AppColors.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Sensor Fusion Stats Row ──────────────────────────────────────────────────

class _SensorStatsRow extends StatelessWidget {
  final WorkoutState workout;
  const _SensorStatsRow({required this.workout});

  @override
  Widget build(BuildContext context) {
    final showCadence = workout.sportMode != 'Sepeda' && workout.cadenceSpm > 0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          // Row: Steps / Cadence / Elevation / Calories
          Row(
            children: [
              Expanded(
                child: _SensorMini(
                  icon: Icons.directions_walk_rounded,
                  value: workout.sportMode == 'Sepeda'
                      ? '--'
                      : workout.stepCount.toString(),
                  unit: 'langkah',
                  color: AppColors.primary,
                ),
              ),
              Container(width: 1, height: 36, color: Colors.white.withOpacity(0.07)),
              Expanded(
                child: _SensorMini(
                  icon: Icons.speed_rounded,
                  value: showCadence
                      ? '${workout.cadenceSpm.round()}'
                      : '--',
                  unit: 'spm',
                  color: Colors.orangeAccent,
                ),
              ),
              Container(width: 1, height: 36, color: Colors.white.withOpacity(0.07)),
              Expanded(
                child: _SensorMini(
                  icon: Icons.trending_up_rounded,
                  value: '+${workout.elevationGainM.toStringAsFixed(0)}',
                  unit: 'm elev',
                  color: const Color(0xFF66BB6A),
                ),
              ),
              Container(width: 1, height: 36, color: Colors.white.withOpacity(0.07)),
              Expanded(
                child: _SensorMini(
                  icon: Icons.local_fire_department_rounded,
                  value: workout.estimatedCalories.toStringAsFixed(0),
                  unit: 'kal',
                  color: Colors.deepOrangeAccent,
                ),
              ),
            ],
          ),

          // Heart Rate row (only shown when watch is connected)
          if (workout.isWatchConnected || workout.heartRateBpm > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Color(workout.currentHrZone.colorValue).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Color(workout.currentHrZone.colorValue).withOpacity(0.25),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.favorite_rounded,
                    color: Color(workout.currentHrZone.colorValue),
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    workout.heartRateBpm > 0 ? '${workout.heartRateBpm} bpm' : '-- bpm',
                    style: TextStyle(
                      color: Color(workout.currentHrZone.colorValue),
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Color(workout.currentHrZone.colorValue).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      workout.currentHrZone.label,
                      style: TextStyle(
                        color: Color(workout.currentHrZone.colorValue),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.watch_rounded,
                    color: Color(workout.currentHrZone.colorValue).withOpacity(0.6),
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    workout.watchDeviceName.isNotEmpty
                        ? workout.watchDeviceName
                        : 'Smartwatch',
                    style: TextStyle(
                      color: AppColors.onSurfaceVariant.withOpacity(0.6),
                      fontSize: 10,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],

          // Detected activity badge
          if (workout.detectedActivity.isNotEmpty &&
              workout.detectedActivity != 'Diam' &&
              workout.isRunning) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.sensors_rounded,
                    color: AppColors.onSurfaceVariant, size: 11),
                const SizedBox(width: 4),
                Text(
                  'Terdeteksi: ${workout.detectedActivity}',
                  style: const TextStyle(
                    color: AppColors.onSurfaceVariant,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SensorMini extends StatelessWidget {
  final IconData icon;
  final String value;
  final String unit;
  final Color color;
  const _SensorMini({
    required this.icon,
    required this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color.withOpacity(0.7), size: 14),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          unit,
          style: const TextStyle(
            color: AppColors.onSurfaceVariant,
            fontSize: 9,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
