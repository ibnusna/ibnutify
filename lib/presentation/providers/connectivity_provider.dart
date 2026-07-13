import 'dart:io';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final isOfflineProvider = StateNotifierProvider<ConnectivityNotifier, bool>((ref) {
  return ConnectivityNotifier();
});

class ConnectivityNotifier extends StateNotifier<bool> {
  Timer? _timer;

  ConnectivityNotifier() : super(false) {
    _checkInternet();
    // Poll every 5 seconds
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _checkInternet());
  }

  Future<void> _checkInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      final hasInternet = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      if (state != !hasInternet) {
        state = !hasInternet;
      }
    } on SocketException catch (_) {
      if (state != true) {
        state = true;
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
