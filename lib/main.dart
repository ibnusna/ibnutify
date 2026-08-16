import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'core/theme/app_theme.dart';
import 'presentation/providers/app_providers.dart';
import 'presentation/screens/main_shell.dart';
import 'services/audio_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Inisialisasi FlutterForegroundTask (workout background service) ──
  // Harus dipanggil sebelum startService(), idealnya di awal main().
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'com.ibnutify.workout',
      channelName: 'IbnuTify Workout',
      channelDescription: 'GPS workout tracking berjalan di latar belakang',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
      onlyAlertOnce: true,
      showWhen: false,
      enableVibration: false,
      playSound: false,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: true,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      // onRepeatEvent dipanggil setiap 1000ms = 1 detik (menggantikan Timer.periodic)
      eventAction: ForegroundTaskEventAction.repeat(1000),
      allowWakeLock: true,       // CPU tidak tidur saat screen off
      allowWifiLock: false,
      allowAutoRestart: true,    // Auto-restart jika proses dibunuh sistem
      stopWithTask: false,       // Jangan stop saat task removed (swipe-dismiss app)
    ),
  );

  // Init communication port agar main isolate bisa receive data dari task isolate
  FlutterForegroundTask.initCommunicationPort();

  try {
    // Load .env for Gemini API key
    await dotenv.load(fileName: '.env');

    // Force portrait orientation
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    // Transparent status bar like Spotify
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.surfaceVariant,
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    // Small delay to ensure FlutterEngine is fully ready before audio_service init
    // This prevents PlatformException from audio_service not finding FlutterEngine
    await Future.delayed(const Duration(milliseconds: 100));

    // Initialize audio_service + just_audio
    final audioHandler = await AudioService.init(
      builder: () => IbnuTifyAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.ibnutify.ibnutify.audio',
        androidNotificationChannelName: 'IbnuTify Music',
        androidNotificationChannelDescription: 'IbnuTify music playback controls',
        // ongoing=false memungkinkan user swipe-dismiss saat paused
        // (Android 13+ wajib: ongoing notification harus bisa dismissed)
        androidNotificationOngoing: false,
        // Stop foreground service saat paused agar notif bisa diswipe
        androidStopForegroundOnPause: true,
        // Warna aksen di notification (warna hijau Spotify)
        notificationColor: Color(0xFF1DB954),
        // Ukuran artwork di notification: large untuk lockscreen
        artDownscaleWidth: 300,
        artDownscaleHeight: 300,
      ),
    );

    runApp(
      ProviderScope(
        overrides: [
          audioHandlerProvider.overrideWithValue(audioHandler),
        ],
        child: const IbnuTifyApp(),
      ),
    );

    // Remove splash screen only after the first frame is fully rendered.
    // Using addPostFrameCallback ensures the Flutter widget tree is mounted
    // before the native splash layer is dismissed — fixing the stuck-splash
    // issue on real mobile devices caused by the previous Future.delayed race.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
    });
  } catch (e, stackTrace) {
    // Show error dialog if initialization fails
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text(
                    'Initialization Error',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    e.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    stackTrace.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ));
    FlutterNativeSplash.remove();
  }
}

class IbnuTifyApp extends StatelessWidget {
  const IbnuTifyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IbnuTify',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const MainShell(),
    );
  }
}
