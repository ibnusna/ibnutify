import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/datasources/database_helper.dart';
import '../../../data/models/activity_model.dart';
import '../../providers/app_providers.dart';
import '../../widgets/workout/sport_mode_picker.dart';
import 'workout_detail_screen.dart';

/// WorkoutHistoryScreen — daftar riwayat aktivitas olahraga dengan multi-select delete.
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

  // ── Multi-select deletion state ───────────────────────────────────────────
  bool _isSelectionMode = false;
  final Set<int> _selectedIds = {};

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

  void _enterSelectionMode(int initialId) {
    HapticFeedback.mediumImpact();
    setState(() {
      _isSelectionMode = true;
      _selectedIds.add(initialId);
    });
  }

  void _toggleSelection(int id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll(List<ActivityModel> activities) {
    HapticFeedback.selectionClick();
    setState(() {
      final validIds =
          activities.where((a) => a.id != null).map((a) => a.id!).toList();
      if (_selectedIds.length == validIds.length) {
        _selectedIds.clear();
        _isSelectionMode = false;
      } else {
        _selectedIds.addAll(validIds);
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedIds.clear();
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;
    final count = _selectedIds.length;
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
              'Hapus Riwayat?',
              style: TextStyle(
                color: AppColors.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'Apakah kamu yakin ingin menghapus $count aktivitas yang dipilih? Data rute dan statistik akan dihapus permanen.',
          style: const TextStyle(
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

    if (confirmed == true && mounted) {
      await DatabaseHelper.instance.deleteActivities(_selectedIds.toList());
      ref.invalidate(activitiesProvider);
      _exitSelectionMode();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$count aktivitas berhasil dihapus'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
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
      builder: (_) => const SportModePicker(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activitiesAsync = ref.watch(activitiesProvider);

    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isSelectionMode) {
          _exitSelectionMode();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        bottomNavigationBar: _isSelectionMode && _selectedIds.isNotEmpty
            ? SafeArea(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Text(
                        '${_selectedIds.length} dipilih',
                        style: const TextStyle(
                          color: AppColors.onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.error,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _deleteSelected,
                        icon: const Icon(Icons.delete_rounded, size: 18),
                        label: const Text('Hapus',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                ),
              )
            : null,
        body: CustomScrollView(
          slivers: [
            // ── Top App Bar ──────────────────────────────────────────────
            SliverAppBar(
              pinned: true,
              backgroundColor: AppColors.background,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              leading: _isSelectionMode
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: AppColors.onSurface),
                      onPressed: _exitSelectionMode,
                    )
                  : IconButton(
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: AppColors.onSurface),
                      onPressed: () => Navigator.pop(context),
                    ),
              title: Text(
                _isSelectionMode
                    ? '${_selectedIds.length} Dipilih'
                    : 'Riwayat Olahraga',
                style: GoogleFonts.inter(
                  color: AppColors.onSurface,
                  fontSize: _isSelectionMode ? 18 : 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              actions: [
                if (_isSelectionMode) ...[
                  activitiesAsync.maybeWhen(
                    data: (activities) {
                      final filtered = _selectedFilter == 'Semua'
                          ? activities
                          : activities
                              .where((a) => a.sportMode == _selectedFilter)
                              .toList();
                      final isAllSelected = filtered.isNotEmpty &&
                          _selectedIds.length == filtered.length;
                      return IconButton(
                        icon: Icon(
                          isAllSelected
                              ? Icons.deselect_rounded
                              : Icons.select_all_rounded,
                          color: AppColors.onSurface,
                        ),
                        tooltip: isAllSelected ? 'Batal Semua' : 'Pilih Semua',
                        onPressed: () => _selectAll(filtered),
                      );
                    },
                    orElse: () => const SizedBox.shrink(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: AppColors.error),
                    tooltip: 'Hapus',
                    onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
                  ),
                  const SizedBox(width: 8),
                ] else ...[
                  activitiesAsync.maybeWhen(
                    data: (activities) {
                      if (activities.isEmpty) return const SizedBox.shrink();
                      return IconButton(
                        icon: const Icon(Icons.checklist_rounded,
                            color: AppColors.onSurface),
                        tooltip: 'Pilih',
                        onPressed: () =>
                            setState(() => _isSelectionMode = true),
                      );
                    },
                    orElse: () => const SizedBox.shrink(),
                  ),
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
                error: (_, __) =>
                    const SliverToBoxAdapter(child: SizedBox.shrink()),
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
                              color:
                                  AppColors.onSurfaceVariant.withOpacity(0.4),
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
                      (ctx, i) {
                        final act = filtered[i];
                        final isSelected =
                            act.id != null && _selectedIds.contains(act.id);

                        return _ActivityCard(
                          activity: act,
                          sportIcon: _sportIcon(act.sportMode),
                          dateString: _formatDate(act.createdAt),
                          isSelectionMode: _isSelectionMode,
                          isSelected: isSelected,
                          onTap: () {
                            if (_isSelectionMode && act.id != null) {
                              _toggleSelection(act.id!);
                            } else {
                              Navigator.of(context).push(
                                PageRouteBuilder(
                                  pageBuilder: (_, __, ___) =>
                                      WorkoutDetailScreen(activity: act),
                                  transitionsBuilder:
                                      (_, animation, __, child) =>
                                          SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(1, 0),
                                      end: Offset.zero,
                                    ).animate(CurvedAnimation(
                                        parent: animation,
                                        curve: Curves.easeOutCubic)),
                                    child: child,
                                  ),
                                  transitionDuration:
                                      const Duration(milliseconds: 300),
                                ),
                              );
                            }
                          },
                          onLongPress: () {
                            if (act.id != null) {
                              if (_isSelectionMode) {
                                _toggleSelection(act.id!);
                              } else {
                                _enterSelectionMode(act.id!);
                              }
                            }
                          },
                        );
                      },
                      childCount: filtered.length,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Activity Card ─────────────────────────────────────────────────────────────

class _ActivityCard extends StatelessWidget {
  final ActivityModel activity;
  final IconData sportIcon;
  final String dateString;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ActivityCard({
    required this.activity,
    required this.sportIcon,
    required this.dateString,
    required this.isSelectionMode,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isSelected
            ? AppColors.primary.withOpacity(0.12)
            : AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? AppColors.primary.withOpacity(0.5)
              : Colors.white.withOpacity(0.06),
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    // Checkbox jika mode selection aktif
                    if (isSelectionMode) ...[
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 24,
                        height: 24,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected
                              ? AppColors.primary
                              : Colors.transparent,
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary
                                : Colors.white.withOpacity(0.35),
                            width: 2,
                          ),
                        ),
                        child: isSelected
                            ? const Icon(Icons.check_rounded,
                                size: 16, color: AppColors.background)
                            : null,
                      ),
                    ],

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
                          Row(
                            children: [
                              Text(
                                activity.sportMode,
                                style: const TextStyle(
                                  color: AppColors.onSurface,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              // Badge BPM jika ada data HR
                              if (activity.avgHeartRateBpm > 0) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.favorite_rounded,
                                          color: Colors.redAccent, size: 10),
                                      const SizedBox(width: 3),
                                      Text(
                                        '${activity.avgHeartRateBpm} bpm',
                                        style: const TextStyle(
                                          color: Colors.redAccent,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
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
                    if (!isSelectionMode)
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.onSurfaceVariant,
                        size: 22,
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // Stats row: Selalu tampilkan data valid, tidak pernah menampilkan strip '--'
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.background.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: Row(
                    children: [
                      _StatCell(
                          label: 'JARAK', value: activity.formattedDistance),
                      _VertDivider(),
                      _StatCell(
                          label: 'WAKTU', value: activity.formattedDuration),
                      // Kolom ke-3 HANYA ditampilkan jika ada data valid (bukan strip)
                      if (activity.avgPace != '--\'--"/km') ...[
                        _VertDivider(),
                        _StatCell(label: 'PACE', value: activity.avgPace),
                      ] else if (activity.estimatedCalories > 0) ...[
                        _VertDivider(),
                        _StatCell(
                            label: 'KALORI',
                            value:
                                '${activity.estimatedCalories.toStringAsFixed(0)} kal'),
                      ] else if (activity.sportMode != 'Sepeda' &&
                          activity.stepCount > 0) ...[
                        _VertDivider(),
                        _StatCell(
                            label: 'LANGKAH',
                            value: '${activity.stepCount}'),
                      ],
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
