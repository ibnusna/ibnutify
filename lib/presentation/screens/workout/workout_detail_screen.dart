import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/datasources/database_helper.dart';
import '../../../data/models/activity_model.dart';
import '../../providers/app_providers.dart' show LatLngPoint, activitiesProvider;
import '../../widgets/workout/osm_map_widget.dart';

/// WorkoutDetailScreen — detail riwayat aktivitas tunggal.
/// Menampilkan: peta OSM realtime + statistik aktivitas yang kondisional & opsi hapus.
/// Dipanggil dari WorkoutHistoryScreen saat user tap card riwayat.
class WorkoutDetailScreen extends ConsumerWidget {
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

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.error, size: 22),
            ),
            const SizedBox(width: 12),
            const Text(
              'Hapus Aktivitas?',
              style: TextStyle(
                color: AppColors.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: const Text(
          'Apakah kamu yakin ingin menghapus riwayat aktivitas ini? Data rute dan statistik akan dihapus permanen.',
          style: TextStyle(
            color: AppColors.onSurfaceVariant,
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal',
                style: TextStyle(
                    color: AppColors.onSurfaceVariant,
                    fontWeight: FontWeight.w600)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true && activity.id != null && context.mounted) {
      await DatabaseHelper.instance.deleteActivity(activity.id!);
      ref.invalidate(activitiesProvider);
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Aktivitas berhasil dihapus'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routePoints = _parseRoutePoints();

    // ── Build Bento Items Secara Kondisional (Tidak menampilkan data kosong/strip) ──
    final bentoItems = <Widget>[
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
      if (activity.avgPace != '--\'--"/km')
        _StatBento(
          icon: Icons.speed_rounded,
          iconColor: AppColors.onSurfaceVariant,
          value: activity.avgPace,
          label: 'Pace Rata-rata',
        ),
      if (routePoints.isNotEmpty)
        _StatBento(
          icon: Icons.my_location_rounded,
          iconColor: AppColors.primary,
          value: '${routePoints.length}',
          label: 'Titik GPS',
        ),
      // Langkah HANYA tampil jika bukan mode Sepeda dan langkah terdeteksi (> 0)
      if (activity.sportMode != 'Sepeda' && activity.stepCount > 0)
        _StatBento(
          icon: Icons.directions_walk_rounded,
          iconColor: AppColors.onSurfaceVariant,
          value: '${activity.stepCount}',
          label: 'Langkah',
          valueColor: AppColors.primary,
        ),
      // Elevasi HANYA tampil jika ada elevasi naik (> 0)
      if (activity.elevationGainM > 0)
        _StatBento(
          icon: Icons.trending_up_rounded,
          iconColor: const Color(0xFF66BB6A),
          value: '+${activity.elevationGainM.toStringAsFixed(0)} m',
          label: 'Elevasi Naik',
          valueColor: const Color(0xFF66BB6A),
        ),
      // Kalori HANYA tampil jika > 0
      if (activity.estimatedCalories > 0)
        _StatBento(
          icon: Icons.local_fire_department_rounded,
          iconColor: Colors.deepOrangeAccent,
          value: '${activity.estimatedCalories.toStringAsFixed(0)} kal',
          label: 'Kalori',
          valueColor: Colors.deepOrangeAccent,
        ),
      // Detak Jantung HANYA tampil jika smartwatch mendeteksi HR (> 0)
      if (activity.avgHeartRateBpm > 0)
        _StatBento(
          icon: Icons.favorite_rounded,
          iconColor: Colors.redAccent,
          value: '${activity.avgHeartRateBpm} bpm',
          label: 'Detak Jantung',
          valueColor: Colors.redAccent,
        ),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Subtle gradient background
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
                      const SizedBox(width: 8),
                      const Text(
                        'Detail Aktivitas',
                        style: TextStyle(
                          color: AppColors.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Spacer(),
                      // Tombol Hapus Aktivitas Tunggal
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded,
                            color: AppColors.error),
                        tooltip: 'Hapus Aktivitas',
                        onPressed: () => _confirmDelete(context, ref),
                      ),
                    ],
                  ),
                ),

                // ── Scrollable content ────────────────────────────────────
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      8,
                      16,
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

                        // ── Stats Bento Grid (Semua item dijamin memiliki data valid) ──
                        GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1.6,
                          children: bentoItems,
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
