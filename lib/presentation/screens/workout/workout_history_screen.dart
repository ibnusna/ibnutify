import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/activity_model.dart';
import '../../providers/app_providers.dart';
import 'workout_active_screen.dart';

/// WorkoutHistoryScreen — daftar riwayat aktivitas olahraga.
/// Diakses dari ikon [🏃] di Top App Bar HomeScreen.
class WorkoutHistoryScreen extends ConsumerStatefulWidget {
  const WorkoutHistoryScreen({super.key});

  @override
  ConsumerState<WorkoutHistoryScreen> createState() =>
      _WorkoutHistoryScreenState();
}

class _WorkoutHistoryScreenState extends ConsumerState<WorkoutHistoryScreen>
    with SingleTickerProviderStateMixin {
  String _selectedFilter = 'Semua';
  late AnimationController _fabAnim;
  late Animation<double> _fabScale;

  static const _filters = ['Semua', 'Berlari', 'Sepeda', 'Berjalan', 'Mendaki'];

  @override
  void initState() {
    super.initState();
    _fabAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();
    _fabScale = CurvedAnimation(parent: _fabAnim, curve: Curves.elasticOut);
  }

  @override
  void dispose() {
    _fabAnim.dispose();
    super.dispose();
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

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inDays == 0) return 'Hari Ini, ${_pad(dt.hour)}:${_pad(dt.minute)}';
      if (diff.inDays == 1) return 'Kemarin, ${_pad(dt.hour)}:${_pad(dt.minute)}';
      return '${dt.day}/${dt.month}/${dt.year}, ${_pad(dt.hour)}:${_pad(dt.minute)}';
    } catch (_) {
      return iso;
    }
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  void _showSportPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _SportPickerSheet(onSelect: (mode) {
        Navigator.pop(context);
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => WorkoutActiveScreen(sportMode: mode),
            transitionsBuilder: (_, animation, __, child) => SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
              child: child,
            ),
            transitionDuration: const Duration(milliseconds: 380),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activitiesAsync = ref.watch(activitiesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // ── Top App Bar ──────────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.background,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded,
                  color: AppColors.onSurface),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              'Riwayat Olahraga',
              style: TextStyle(
                color: AppColors.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            actions: [
              ScaleTransition(
                scale: _fabScale,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.background,
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                    onPressed: _showSportPicker,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text(
                      'Baru',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
            ],
          ),

          // ── Filter Chips ─────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _filters.map((f) {
                    final selected = _selectedFilter == f;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedFilter = f),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 10),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppColors.onSurface
                                  : AppColors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: selected
                                    ? Colors.transparent
                                    : Colors.white.withOpacity(0.1),
                              ),
                            ),
                            child: Text(
                              f,
                              style: TextStyle(
                                color: selected
                                    ? AppColors.background
                                    : AppColors.onSurfaceVariant,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),

          // ── Activity List ────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
            sliver: activitiesAsync.when(
              loading: () => const SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: 48),
                    child: CircularProgressIndicator(
                      color: AppColors.primary,
                      strokeWidth: 2,
                    ),
                  ),
                ),
              ),
              error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
              data: (activities) {
                final filtered = _selectedFilter == 'Semua'
                    ? activities
                    : activities
                        .where((a) => a.sportMode == _selectedFilter)
                        .toList();

                if (filtered.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 80),
                      child: Column(
                        children: [
                          Icon(
                            Icons.directions_run_rounded,
                            color: AppColors.onSurfaceVariant.withOpacity(0.4),
                            size: 72,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            activities.isEmpty
                                ? 'Belum ada riwayat.\nMulai olahraga pertamamu!'
                                : 'Tidak ada aktivitas "$_selectedFilter".',
                            style: const TextStyle(
                              color: AppColors.onSurfaceVariant,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _ActivityCard(
                      activity: filtered[i],
                      sportIcon: _sportIcon(filtered[i].sportMode),
                      dateString: _formatDate(filtered[i].createdAt),
                    ),
                    childCount: filtered.length,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Activity Card ─────────────────────────────────────────────────────────────

class _ActivityCard extends StatelessWidget {
  final ActivityModel activity;
  final IconData sportIcon;
  final String dateString;

  const _ActivityCard({
    required this.activity,
    required this.sportIcon,
    required this.dateString,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {},
          child: Padding(
            padding: const EdgeInsets.all(16),
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
                      child: Icon(sportIcon, color: AppColors.primary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            activity.sportMode,
                            style: const TextStyle(
                              color: AppColors.onSurface,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            dateString,
                            style: const TextStyle(
                              color: AppColors.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.onSurfaceVariant,
                      size: 22,
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Stats row
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.background.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: Row(
                    children: [
                      _StatCell(label: 'JARAK', value: activity.formattedDistance),
                      _VertDivider(),
                      _StatCell(
                          label: 'WAKTU', value: activity.formattedDuration),
                      _VertDivider(),
                      _StatCell(label: 'PACE', value: activity.avgPace),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  const _StatCell({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.onSurfaceVariant,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _VertDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 32,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        color: Colors.white.withOpacity(0.08),
      );
}

// ─── Sport Picker Sheet ────────────────────────────────────────────────────────

class _SportPickerSheet extends StatelessWidget {
  final void Function(String mode) onSelect;
  const _SportPickerSheet({required this.onSelect});

  static const _sports = [
    ('Berlari', Icons.directions_run_rounded),
    ('Sepeda', Icons.directions_bike_rounded),
    ('Berjalan', Icons.directions_walk_rounded),
    ('Mendaki', Icons.landscape_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Text(
                'Pilih Jenis Olahraga',
                style: TextStyle(
                  color: AppColors.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const Divider(color: Colors.white10, height: 1),
            ..._sports.map((s) => ListTile(
                  leading: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(s.$2, color: AppColors.primary, size: 22),
                  ),
                  title: Text(
                    s.$1,
                    style: const TextStyle(
                      color: AppColors.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded,
                      color: AppColors.onSurfaceVariant),
                  onTap: () => onSelect(s.$1),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                )),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
