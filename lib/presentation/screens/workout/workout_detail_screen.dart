import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/activity_model.dart';
import '../../providers/app_providers.dart' show LatLngPoint;
import '../../widgets/workout/osm_map_widget.dart';

/// WorkoutDetailScreen — detail riwayat aktivitas tunggal.
/// Menampilkan: peta OSM realtime + semua statistik aktivitas.
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
      const months = [
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

  List<LatLngPoint> _parseRoutePoints() {
    final parsed = activity.parsedRoutePoints;
    return parsed.map((e) => LatLngPoint(e['lat']!, e['lng']!)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final routePoints = _parseRoutePoints();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Subtle gradient background
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
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

                // ── Scrollable content ────────────────────────────────────
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      16, 8, 16,
                      // Pastikan konten tidak terpotong system navigation bar
                      MediaQuery.of(context).padding.bottom + 24,
                    ),
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

                        // ── OSM Map (peta dengan tile OpenStreetMap) ──────
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: OsmMapWidget(
                            points: routePoints,
                            height: 240,
                            showLiveIndicator: false,
                            isLive: false,
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
                            // ── Sensor fusion stats (DB v7) ───────────────
                            _StatBento(
                              icon: Icons.directions_walk_rounded,
                              iconColor: AppColors.onSurfaceVariant,
                              value: activity.sportMode == 'Sepeda'
                                  ? '--'
                                  : '${activity.stepCount}',
                              label: 'Langkah',
                            ),
                            _StatBento(
                              icon: Icons.trending_up_rounded,
                              iconColor: const Color(0xFF66BB6A),
                              value: '+${activity.elevationGainM.toStringAsFixed(0)} m',
                              label: 'Elevasi Naik',
                              valueColor: const Color(0xFF66BB6A),
                            ),
                            _StatBento(
                              icon: Icons.local_fire_department_rounded,
                              iconColor: Colors.deepOrangeAccent,
                              value: activity.estimatedCalories > 0
                                  ? '${activity.estimatedCalories.toStringAsFixed(0)} kal'
                                  : '-- kal',
                              label: 'Kalori',
                              valueColor: activity.estimatedCalories > 0
                                  ? Colors.deepOrangeAccent
                                  : AppColors.onSurface,
                            ),
                            _StatBento(
                              icon: Icons.favorite_rounded,
                              iconColor: Colors.redAccent,
                              value: activity.avgHeartRateBpm > 0
                                  ? '${activity.avgHeartRateBpm} bpm'
                                  : '-- bpm',
                              label: 'Detak Jantung',
                              valueColor: activity.avgHeartRateBpm > 0
                                  ? Colors.redAccent
                                  : AppColors.onSurfaceVariant,
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
