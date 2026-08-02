import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/activity_model.dart';
import '../../providers/app_providers.dart';

/// WorkoutDetailScreen — detail riwayat aktivitas tunggal.
/// Menampilkan: tracking map GPS (canvas offline) + semua statistik.
/// Dipanggil dari WorkoutHistoryScreen saat user tap card riwayat.
class WorkoutDetailScreen extends StatelessWidget {
  final ActivityModel activity;

  const WorkoutDetailScreen({super.key, required this.activity});

  IconData get _sportIcon {
    switch (activity.sportMode) {
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

  String _formatCreatedAt(String iso) {
    try {
      final dt = DateTime.parse(iso);
      final months = [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
        'Jul', 'Ags', 'Sep', 'Okt', 'Nov', 'Des'
      ];
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '${dt.day} ${months[dt.month]} ${dt.year}, $h:$m';
    } catch (_) {
      return iso;
    }
  }

  /// Parse routePoints JSON ke list<LatLngPoint>
  List<LatLngPoint> _parseRoutePoints() {
    final parsed = activity.parsedRoutePoints;
    return parsed
        .map((e) => LatLngPoint(e['lat']!, e['lng']!))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final routePoints = _parseRoutePoints();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Background gradient
          Positioned(
            top: 0, left: 0, right: 0, height: 260,
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

          SafeArea(
            child: Column(
              children: [
                // ── App Bar ───────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: AppColors.onSurface),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const Spacer(),
                      const Text(
                        'Detail Aktivitas',
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

                // ── Scrollable content ───────────────────────────────────
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header: sport mode + tanggal
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.12),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(_sportIcon,
                                  color: AppColors.primary, size: 22),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  activity.sportMode,
                                  style: const TextStyle(
                                    color: AppColors.onSurface,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    height: 1,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _formatCreatedAt(activity.createdAt),
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

                        // ── Route Map Canvas ──────────────────────────────
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            height: 220,
                            width: double.infinity,
                            color: const Color(0xFF091209),
                            child: Stack(
                              children: [
                                // Canvas route
                                routePoints.length > 1
                                    ? CustomPaint(
                                        painter: _DetailRoutePainter(
                                            points: routePoints),
                                        size: const Size(double.infinity, 220),
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
                                                color:
                                                    AppColors.onSurfaceVariant,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                // Gradient overlay bottom
                                Positioned(
                                  bottom: 0, left: 0, right: 0,
                                  height: 60,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.transparent,
                                          const Color(0xFF091209).withOpacity(0.7),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),

                                // Label
                                Positioned(
                                  bottom: 10,
                                  left: 12,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceContainerHigh
                                          .withOpacity(0.9),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                          color: Colors.white.withOpacity(0.1)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.my_location_rounded,
                                            color: AppColors.primary, size: 14),
                                        const SizedBox(width: 5),
                                        Text(
                                          routePoints.length > 1
                                              ? '${routePoints.length} titik GPS'
                                              : 'Rute GPS',
                                          style: const TextStyle(
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

                        // ── Stats Bento Grid ──────────────────────────────
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
                              value: activity.formattedDistance,
                              label: 'Jarak Total',
                              valueColor: AppColors.primary,
                            ),
                            _StatBento(
                              icon: Icons.timer_rounded,
                              iconColor: AppColors.onSurfaceVariant,
                              value: activity.formattedDuration,
                              label: 'Waktu Total',
                            ),
                            _StatBento(
                              icon: Icons.speed_rounded,
                              iconColor: AppColors.onSurfaceVariant,
                              value: activity.avgPace,
                              label: 'Pace Rata-rata',
                            ),
                            _StatBento(
                              icon: Icons.my_location_rounded,
                              iconColor: AppColors.primary,
                              value: '${routePoints.length}',
                              label: 'Titik GPS',
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
        ],
      ),
    );
  }
}

// ─── Detail Route Painter ─────────────────────────────────────────────────────

class _DetailRoutePainter extends CustomPainter {
  final List<LatLngPoint> points;
  const _DetailRoutePainter({required this.points});

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

    final path = Path()
      ..moveTo(toOffset(points.first).dx, toOffset(points.first).dy);
    for (final p in points.skip(1)) {
      final o = toOffset(p);
      path.lineTo(o.dx, o.dy);
    }

    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, linePaint);

    // Start dot (hijau)
    final start = toOffset(points.first);
    canvas.drawCircle(start, 5, Paint()..color = AppColors.primary.withOpacity(0.5));
    canvas.drawCircle(start, 3, Paint()..color = AppColors.primary);

    // End dot
    final end = toOffset(points.last);
    canvas.drawCircle(end, 8, Paint()..color = AppColors.primary.withOpacity(0.3));
    canvas.drawCircle(end, 5, Paint()..color = AppColors.primary);
  }

  @override
  bool shouldRepaint(_DetailRoutePainter old) => false;
}

// ─── Stat Bento Card ──────────────────────────────────────────────────────────

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
