import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import 'workout_history_screen.dart';

/// WorkoutSummaryScreen — ringkasan aktivitas setelah sesi olahraga selesai.
/// Dikonversi dari workout_summary/code.html
class WorkoutSummaryScreen extends ConsumerStatefulWidget {
  final WorkoutState snapshot;

  const WorkoutSummaryScreen({super.key, required this.snapshot});

  @override
  ConsumerState<WorkoutSummaryScreen> createState() =>
      _WorkoutSummaryScreenState();
}

class _WorkoutSummaryScreenState extends ConsumerState<WorkoutSummaryScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _fadeAnim =
        CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  IconData get _sportIcon {
    switch (widget.snapshot.sportMode) {
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

  String _formatCreatedAt() {
    final dt = DateTime.now();
    final months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Ags', 'Sep', 'Okt', 'Nov', 'Des'
    ];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month]} ${dt.year}, $h:$m';
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await ref.read(workoutProvider.notifier).saveActivity(widget.snapshot);
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pushAndRemoveUntil(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const WorkoutHistoryScreen(),
        transitionsBuilder: (_, animation, __, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(-1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 350),
      ),
      (route) => false,
    );
  }

  void _discard() {
    Navigator.pushAndRemoveUntil(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const WorkoutHistoryScreen(),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: animation,
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 300),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final snap = widget.snapshot;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Background gradient glow
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 260,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.primary.withOpacity(0.07),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Content
          SafeArea(
            child: Column(
              children: [
                // App Bar
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      const SizedBox(width: 48), // spacer for centering
                      const Spacer(),
                      const Text(
                        'Ringkasan Latihan',
                        style: TextStyle(
                          color: AppColors.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Spacer(),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),

                // Scrollable content
                Expanded(
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: SlideTransition(
                      position: _slideAnim,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 160),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header
                            Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withOpacity(0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(_sportIcon,
                                      color: AppColors.primary, size: 20),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      snap.sportMode,
                                      style: const TextStyle(
                                        color: AppColors.onSurface,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900,
                                        height: 1,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _formatCreatedAt(),
                                      style: const TextStyle(
                                        color: AppColors.onSurfaceVariant,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),

                            // Route canvas
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                height: 200,
                                width: double.infinity,
                                color: const Color(0xFF091209),
                                child: Stack(
                                  children: [
                                    snap.routePoints.length > 1
                                        ? CustomPaint(
                                            painter: _SummaryRoutePainter(
                                                points: snap.routePoints),
                                            size: const Size(
                                                double.infinity, 200),
                                          )
                                        : Center(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.route_rounded,
                                                  color: AppColors.primary
                                                      .withOpacity(0.3),
                                                  size: 48,
                                                ),
                                                const SizedBox(height: 8),
                                                const Text(
                                                  'Rute tidak tersedia',
                                                  style: TextStyle(
                                                    color: AppColors
                                                        .onSurfaceVariant,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                    // Gradient overlay bottom
                                    Positioned(
                                      bottom: 0,
                                      left: 0,
                                      right: 0,
                                      height: 60,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Colors.transparent,
                                              const Color(0xFF091209)
                                                  .withOpacity(0.7),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 10,
                                      left: 12,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: AppColors.surfaceContainerHigh
                                              .withOpacity(0.9),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                          border: Border.all(
                                              color:
                                                  Colors.white.withOpacity(0.1)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.my_location_rounded,
                                                color: AppColors.primary,
                                                size: 14),
                                            const SizedBox(width: 5),
                                            const Text(
                                              'Rute Selesai',
                                              style: TextStyle(
                                                color: AppColors.onSurface,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Stats bento grid
                            GridView.count(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisCount: 2,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 1.6,
                              children: [
                                _StatBento(
                                  icon: Icons.route_rounded,
                                  iconColor: AppColors.onSurfaceVariant,
                                  value: snap.distanceKm > 0
                                      ? '${snap.distanceKm.toStringAsFixed(2)} KM'
                                      : '0.00 KM',
                                  label: 'Jarak Total',
                                  valueColor: AppColors.primary,
                                ),
                                _StatBento(
                                  icon: Icons.timer_rounded,
                                  iconColor: AppColors.onSurfaceVariant,
                                  value: snap.formattedDuration,
                                  label: 'Waktu Total',
                                ),
                                _StatBento(
                                  icon: Icons.speed_rounded,
                                  iconColor: AppColors.onSurfaceVariant,
                                  value: snap.avgPace,
                                  label: 'Pace Rata-rata',
                                ),
                                _StatBento(
                                  icon: Icons.library_music_rounded,
                                  iconColor: AppColors.primary,
                                  value: '${snap.songsPlayed} Lagu',
                                  label: 'Dimainkan',
                                ),
                                _StatBento(
                                  icon: Icons.directions_walk_rounded,
                                  iconColor: AppColors.onSurfaceVariant,
                                  value: snap.sportMode == 'Sepeda'
                                      ? '--'
                                      : snap.stepCount.toString(),
                                  label: 'Langkah',
                                  valueColor: AppColors.primary,
                                ),
                                _StatBento(
                                  icon: Icons.trending_up_rounded,
                                  iconColor: const Color(0xFF66BB6A),
                                  value: '+${snap.elevationGainM.toStringAsFixed(0)} m',
                                  label: 'Elevasi Naik',
                                  valueColor: const Color(0xFF66BB6A),
                                ),
                                _StatBento(
                                  icon: Icons.local_fire_department_rounded,
                                  iconColor: Colors.deepOrangeAccent,
                                  value: snap.estimatedCalories > 0
                                      ? '${snap.estimatedCalories.toStringAsFixed(0)} kal'
                                      : '-- kal',
                                  label: 'Kalori',
                                  valueColor: Colors.deepOrangeAccent,
                                ),
                                _StatBento(
                                  icon: Icons.favorite_rounded,
                                  iconColor: Colors.redAccent,
                                  value: snap.heartRateBpm > 0
                                      ? '${snap.heartRateBpm} bpm'
                                      : '-- bpm',
                                  label: 'HR Terakhir',
                                  valueColor: snap.heartRateBpm > 0
                                      ? Colors.redAccent
                                      : AppColors.onSurfaceVariant,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Sticky bottom buttons
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    AppColors.background.withOpacity(0.97),
                    AppColors.background,
                  ],
                ),
              ),
              padding: EdgeInsets.fromLTRB(
                16,
                24,
                16,
                MediaQuery.of(context).padding.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Save button
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.background,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: const StadiumBorder(),
                      ),
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.background,
                              ),
                            )
                          : const Icon(Icons.save_rounded, size: 20),
                      label: const Text(
                        'SIMPAN KE RIWAYAT SAYA',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Discard button
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.onSurfaceVariant,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: const StadiumBorder(),
                      ),
                      onPressed: _discard,
                      child: const Text(
                        'Buang',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
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

// ─── Summary Route Painter ────────────────────────────────────────────────────

class _SummaryRoutePainter extends CustomPainter {
  final List<LatLngPoint> points;
  const _SummaryRoutePainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

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
    const padding = 24.0;
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

    final glowPaint = Paint()
      ..color = AppColors.primary.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
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

    // Start dot (green outline)
    final start = toOffset(points.first);
    canvas.drawCircle(start, 5,
        Paint()..color = AppColors.primary.withOpacity(0.5));
    canvas.drawCircle(start, 3, Paint()..color = AppColors.primary);

    // End dot (solid)
    final end = toOffset(points.last);
    canvas.drawCircle(
        end, 8, Paint()..color = AppColors.primary.withOpacity(0.3));
    canvas.drawCircle(end, 5, Paint()..color = AppColors.primary);
  }

  @override
  bool shouldRepaint(_SummaryRoutePainter old) => false;
}

// ─── Stat Bento Card ─────────────────────────────────────────────────────────

class _StatBento extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;
  final Color valueColor;

  const _StatBento({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
    this.valueColor = AppColors.onSurface,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: iconColor, size: 22),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: valueColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
