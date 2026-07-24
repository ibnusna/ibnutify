import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/song_model.dart';
import '../../providers/app_providers.dart';
import '../../widgets/common/song_artwork_widget.dart';
import 'workout_summary_screen.dart';

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
    final ok = await ref
        .read(workoutProvider.notifier)
        .startWorkout(widget.sportMode);
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

  @override
  Widget build(BuildContext context) {
    final workout = ref.watch(workoutProvider);
    final player = ref.watch(playerProvider);
    final currentSong = player.currentSong;

    return Scaffold(
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
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: AppColors.surfaceContainerHigh,
                              title: const Text('Keluar dari olahraga?',
                                  style: TextStyle(color: AppColors.onSurface)),
                              content: const Text(
                                'Sesi aktif akan dihentikan. Data tidak tersimpan.',
                                style: TextStyle(
                                    color: AppColors.onSurfaceVariant,
                                    fontSize: 14),
                              ),
                              actions: [
                                TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(false),
                                    child: const Text('Batal',
                                        style: TextStyle(
                                            color: AppColors.onSurfaceVariant))),
                                TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(true),
                                    child: const Text('Keluar',
                                        style: TextStyle(
                                            color: Colors.redAccent,
                                            fontWeight: FontWeight.w900))),
                              ],
                            ),
                          );
                          if (confirm == true && mounted) {
                            await ref
                                .read(workoutProvider.notifier)
                                .stopWorkout();
                            if (mounted) Navigator.pop(context);
                          }
                        },
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
                                      workout.avgPace,
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

                        // ── Offline GPS Canvas ────────────────────────
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            height: 180,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: const Color(0xFF0A1A0A),
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.08)),
                            ),
                            child: Stack(
                              children: [
                                // Route canvas
                                workout.routePoints.length > 1
                                    ? CustomPaint(
                                        painter: _RoutePainter(
                                          points: workout.routePoints,
                                        ),
                                        size: const Size(double.infinity, 180),
                                      )
                                    : Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.gps_fixed_rounded,
                                              color: AppColors.primary
                                                  .withOpacity(0.4),
                                              size: 36,
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              _locationDenied
                                                  ? 'GPS tidak tersedia'
                                                  : 'Menunggu sinyal GPS...',
                                              style: TextStyle(
                                                color: AppColors.onSurfaceVariant
                                                    .withOpacity(0.6),
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                // Live indicator
                                Positioned(
                                  bottom: 10,
                                  left: 12,
                                  child: Row(
                                    children: [
                                      FadeTransition(
                                        opacity: _pulseAnim,
                                        child: Container(
                                          width: 8,
                                          height: 8,
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
                                            : 'Live Tracking',
                                        style: const TextStyle(
                                          color: AppColors.onSurface,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
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
    );
  }
}

// ─── Route Painter (Offline Canvas) ───────────────────────────────────────────

class _RoutePainter extends CustomPainter {
  final List<LatLngPoint> points;
  const _RoutePainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    // Find bounding box
    double minLat = points.first.lat, maxLat = points.first.lat;
    double minLng = points.first.lng, maxLng = points.first.lng;
    for (final p in points) {
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
      if (p.lng < minLng) minLng = p.lng;
      if (p.lng > maxLng) maxLng = p.lng;
    }

    final latRange = maxLat - minLat;
    final lngRange = maxLng - minLng;
    final rangeMax = latRange > lngRange ? latRange : lngRange;
    final padding = size.width * 0.1;
    final drawW = size.width - padding * 2;
    final drawH = size.height - padding * 2;

    Offset toOffset(LatLngPoint p) {
      final x = rangeMax > 0
          ? padding + (p.lng - minLng) / rangeMax * drawW
          : size.width / 2;
      final y = rangeMax > 0
          ? padding + (maxLat - p.lat) / rangeMax * drawH
          : size.height / 2;
      return Offset(x, y);
    }

    // Glow path
    final glowPaint = Paint()
      ..color = AppColors.primary.withOpacity(0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final linePaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()..moveTo(toOffset(points.first).dx, toOffset(points.first).dy);
    for (final p in points.skip(1)) {
      final o = toOffset(p);
      path.lineTo(o.dx, o.dy);
    }

    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, linePaint);

    // Current position dot
    final last = toOffset(points.last);
    canvas.drawCircle(
      last,
      6,
      Paint()..color = AppColors.primary,
    );
    canvas.drawCircle(
      last,
      10,
      Paint()
        ..color = AppColors.primary.withOpacity(0.3)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_RoutePainter oldDelegate) =>
      oldDelegate.points.length != points.length;
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
