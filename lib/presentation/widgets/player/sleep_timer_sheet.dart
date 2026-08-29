import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';

/// Modal bottom sheet untuk memilih durasi Sleep Timer.
class SleepTimerSheet extends ConsumerWidget {
  const SleepTimerSheet({super.key});

  static const _options = [
    ('Mati', null),
    ('5 Menit', Duration(minutes: 5)),
    ('15 Menit', Duration(minutes: 15)),
    ('30 Menit', Duration(minutes: 30)),
    ('45 Menit', Duration(minutes: 45)),
    ('60 Menit', Duration(minutes: 60)),
    ('Akhir Lagu Ini', Duration(seconds: -1)), // -1 = end of current song
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timerState = ref.watch(sleepTimerProvider);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
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
                'Sleep Timer',
                style: TextStyle(
                  color: AppColors.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const Divider(color: Colors.white10, height: 1),
            ..._options.map((opt) {
              final label = opt.$1;
              final duration = opt.$2;
              final isSelected = (duration == null && timerState.duration == null) ||
                  (duration != null &&
                      timerState.duration?.inSeconds == duration.inSeconds);

              return ListTile(
                leading: Icon(
                  Icons.timer_outlined,
                  color: isSelected ? AppColors.primary : AppColors.onSurfaceVariant,
                ),
                title: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? AppColors.primary : AppColors.onSurface,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                trailing: isSelected
                    ? const Icon(Icons.check_rounded, color: AppColors.primary)
                    : null,
                onTap: () {
                  ref.read(sleepTimerProvider.notifier).setTimer(duration);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        duration == null
                            ? 'Sleep Timer dimatikan'
                            : 'Sleep Timer diatur: $label',
                        style: const TextStyle(
                            color: Colors.black, fontWeight: FontWeight.w700),
                      ),
                      backgroundColor: AppColors.primary,
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              );
            }),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
