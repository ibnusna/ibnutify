import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/song_model.dart';
import '../../screens/workout/workout_active_screen.dart';

/// Bottom sheet untuk memilih jenis olahraga sebelum memulai sesi.
/// Digunakan dari MoreOptionsSheet untuk menghindari circular import.
class SportModePicker extends StatelessWidget {
  final SongModel? initialSong;

  const SportModePicker({super.key, this.initialSong});

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
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (_, __, ___) => WorkoutActiveScreen(
                          sportMode: s.$1,
                          initialSong: initialSong,
                        ),
                        transitionsBuilder: (_, animation, __, child) =>
                            SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 1),
                            end: Offset.zero,
                          ).animate(CurvedAnimation(
                              parent: animation, curve: Curves.easeOutCubic)),
                          child: child,
                        ),
                        transitionDuration: const Duration(milliseconds: 380),
                      ),
                    );
                  },
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                )),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
