import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';



// ─── BLE GATT Constants ───────────────────────────────────────────────────────

/// Standard Heart Rate Service UUID (Bluetooth SIG 0x180D)
const String _kHrServiceUuid = '0000180d-0000-1000-8000-00805f9b34fb';

/// Standard Heart Rate Measurement Characteristic UUID (0x2A37)
const String _kHrCharUuid = '00002a37-0000-1000-8000-00805f9b34fb';

/// Battery Service UUID (0x180F)
const String _kBatteryServiceUuid = '0000180f-0000-1000-8000-00805f9b34fb';

/// Battery Level Characteristic (0x2A19)
const String _kBatteryCharUuid = '00002a19-0000-1000-8000-00805f9b34fb';

const String _kPrefLastWatchMac = 'lastWatchMac';
const String _kPrefLastWatchName = 'lastWatchName';

// ─── Watch Connection State ───────────────────────────────────────────────────

enum WatchConnectionState { disconnected, scanning, connecting, connected, error }

class WatchState {
  final WatchConnectionState connectionState;
  final String deviceName;
  final String deviceMac;
  final int batteryLevel; // 0–100, -1 = unknown
  final bool hasHeartRate;
  final String? errorMessage;

  const WatchState({
    this.connectionState = WatchConnectionState.disconnected,
    this.deviceName = '',
    this.deviceMac = '',
    this.batteryLevel = -1,
    this.hasHeartRate = false,
    this.errorMessage,
  });

  bool get isConnected => connectionState == WatchConnectionState.connected;
  bool get isScanning => connectionState == WatchConnectionState.scanning;

  WatchState copyWith({
    WatchConnectionState? connectionState,
    String? deviceName,
    String? deviceMac,
    int? batteryLevel,
    bool? hasHeartRate,
    String? errorMessage,
  }) =>
      WatchState(
        connectionState: connectionState ?? this.connectionState,
        deviceName: deviceName ?? this.deviceName,
        deviceMac: deviceMac ?? this.deviceMac,
        batteryLevel: batteryLevel ?? this.batteryLevel,
        hasHeartRate: hasHeartRate ?? this.hasHeartRate,
        errorMessage: errorMessage,
      );
}

// ─── WatchService ─────────────────────────────────────────────────────────────

/// Singleton service that manages BLE connection to a smartwatch.
/// Exposes heart rate as a broadcast stream.
///
/// Architecture note: BLE must run in the main isolate (flutter_blue_plus
/// requires Android Bluetooth stack access). HR data is then forwarded to
/// WorkoutNotifier which also runs in main isolate.
class WatchService {
  WatchService._();
  static final WatchService instance = WatchService._();

  // ── State ─────────────────────────────────────────────────────────────────
  final _stateController = StreamController<WatchState>.broadcast();
  Stream<WatchState> get stateStream => _stateController.stream;
  WatchState _state = const WatchState();
  WatchState get state => _state;

  // HR stream
  final _hrController = StreamController<int>.broadcast();
  Stream<int> get hrStream => _hrController.stream;

  // Internal
  BluetoothDevice? _device;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<List<int>>? _hrNotifySub;
  StreamSubscription<BluetoothConnectionState>? _connStateSub;

  // Discovered devices for scanning sheet
  final _discoveredController = StreamController<List<ScanResult>>.broadcast();
  Stream<List<ScanResult>> get discoveredStream => _discoveredController.stream;
  final List<ScanResult> _discovered = [];

  // ── Public API ────────────────────────────────────────────────────────────

  void _emit(WatchState newState) {
    _state = newState;
    if (!_stateController.isClosed) _stateController.add(newState);
  }

  /// Scan for ALL nearby BLE devices (broad scan — no service UUID filter).
  ///
  /// Alasan tidak menggunakan withServices filter:
  /// Smartwatch budget (itel ISW-011, merek IoT Tiongkok) sering tidak
  /// mengiklankan Heart Rate UUID (0x180D) di advertisement packet,
  /// meskipun service tersebut tersedia setelah connect via GATT discovery.
  /// Broad scan memastikan semua device terdeteksi.
  ///
  /// [timeout] — stop scan after this duration (default 20s untuk device lambat advertise).
  Future<void> startScan({Duration timeout = const Duration(seconds: 20)}) async {
    if (_state.isScanning) return;

    // Check BLE adapter
    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      _emit(_state.copyWith(
        connectionState: WatchConnectionState.error,
        errorMessage: 'Bluetooth tidak aktif. Aktifkan Bluetooth terlebih dahulu.',
      ));
      return;
    }

    _discovered.clear();
    _emit(_state.copyWith(connectionState: WatchConnectionState.scanning));

    // Broad scan tanpa filter service UUID — menemukan semua perangkat BLE terdekat.
    // Filter visual dilakukan di UI (watch_pairing_sheet).
    await FlutterBluePlus.startScan(
      timeout: timeout,
    );

    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      _discovered.clear();
      _discovered.addAll(results);
      if (!_discoveredController.isClosed) {
        _discoveredController.add(List.unmodifiable(_discovered));
      }
    });

    // Auto stop scanning after timeout
    Future.delayed(timeout, () {
      stopScan();
    });
  }

  void stopScan() {
    FlutterBluePlus.stopScan();
    _scanSub?.cancel();
    _scanSub = null;
    if (_state.isScanning) {
      _emit(_state.copyWith(connectionState: WatchConnectionState.disconnected));
    }
  }

  /// Connect to a specific BLE device and subscribe to HR notifications.
  Future<bool> connect(BluetoothDevice device) async {
    stopScan();
    _emit(_state.copyWith(
      connectionState: WatchConnectionState.connecting,
      deviceName: device.platformName.isNotEmpty ? device.platformName : 'Smartwatch',
      deviceMac: device.remoteId.str,
    ));

    try {
      // Direct BLE connection (autoConnect: false)
      await device.connect(
        timeout: const Duration(seconds: 12),
        autoConnect: false,
      );
    } catch (e) {
      final errStr = e.toString();
      // Error 133 = GATT_ERROR — coba retry sekali lagi secara direct setelah delay 1.5s
      if (errStr.contains('133') ||
          errStr.contains('ANDROID_SPECIFIC_ERROR') ||
          errStr.contains('GATT_ERROR')) {
        try {
          await Future.delayed(const Duration(milliseconds: 1500));
          await device.connect(
            timeout: const Duration(seconds: 12),
            autoConnect: false,
          );
        } catch (e2) {
          _emit(_state.copyWith(
            connectionState: WatchConnectionState.error,
            errorMessage:
                'Koneksi gagal (GATT error 133). Pastikan smartwatch tidak terhubung ke aplikasi lain, '
                'atau restart Bluetooth HP Anda.',
          ));
          return false;
        }
      } else {
        _emit(_state.copyWith(
          connectionState: WatchConnectionState.error,
          errorMessage: 'Koneksi gagal: ${e.toString()}',
        ));
        return false;
      }
    }


    _device = device;

    // Listen connection state changes
    _connStateSub?.cancel();
    _connStateSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _hrNotifySub?.cancel();
        _emit(_state.copyWith(
          connectionState: WatchConnectionState.disconnected,
          hasHeartRate: false,
        ));
      }
    });

    // Discover services
    final services = await device.discoverServices();

    bool hrFound = false;
    int battery = -1;

    for (final service in services) {
      // Heart Rate Service
      if (service.serviceUuid.toString().toLowerCase() == _kHrServiceUuid) {
        for (final char in service.characteristics) {
          if (char.characteristicUuid.toString().toLowerCase() == _kHrCharUuid) {
            // Enable notifications
            await char.setNotifyValue(true);
            _hrNotifySub?.cancel();
            _hrNotifySub = char.onValueReceived.listen(_onHrData, onError: (_) {});
            hrFound = true;
          }
        }
      }
      // Battery Service (optional)
      if (service.serviceUuid.toString().toLowerCase() == _kBatteryServiceUuid) {
        for (final char in service.characteristics) {
          if (char.characteristicUuid.toString().toLowerCase() == _kBatteryCharUuid) {
            try {
              final value = await char.read();
              if (value.isNotEmpty) battery = value[0];
            } catch (_) {}
          }
        }
      }
    }

    if (!hrFound) {
      // Jangan langsung disconnect — beberapa smartwatch (seperti itel ISW-011)
      // menggunakan custom UUID atau tidak expose HR via standard GATT 0x180D.
      // Tetap emit "connected" dengan hasHeartRate=false agar user tahu device
      // berhasil ditemukan dan tersambung, meskipun HR tidak tersedia via GATT standar.
      _emit(_state.copyWith(
        connectionState: WatchConnectionState.connected,
        deviceName: device.platformName.isNotEmpty ? device.platformName : 'Smartwatch',
        deviceMac: device.remoteId.str,
        batteryLevel: battery,
        hasHeartRate: false,
        errorMessage:
            'Perangkat terhubung, tetapi Heart Rate Service (GATT 0x180D) tidak ditemukan. '
            'Detak jantung tidak akan ditampilkan.',
      ));
      // Simpan device untuk auto-reconnect meski tanpa HR
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefLastWatchMac, device.remoteId.str);
      await prefs.setString(
        _kPrefLastWatchName,
        device.platformName.isNotEmpty ? device.platformName : 'Smartwatch',
      );
      return true;
    }

    // Persist device for auto-reconnect
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefLastWatchMac, device.remoteId.str);
    await prefs.setString(
      _kPrefLastWatchName,
      device.platformName.isNotEmpty ? device.platformName : 'Smartwatch',
    );

    _emit(_state.copyWith(
      connectionState: WatchConnectionState.connected,
      deviceName: device.platformName.isNotEmpty ? device.platformName : 'Smartwatch',
      deviceMac: device.remoteId.str,
      batteryLevel: battery,
      hasHeartRate: true,
    ));

    return true;
  }

  /// Try to reconnect to the last paired device automatically.
  /// Called from WorkoutNotifier.startWorkout().
  Future<bool> autoConnect() async {
    final prefs = await SharedPreferences.getInstance();
    final lastMac = prefs.getString(_kPrefLastWatchMac);
    final lastName = prefs.getString(_kPrefLastWatchName) ?? 'Smartwatch';

    if (lastMac == null || lastMac.isEmpty) return false;

    try {
      // Check if device is already bonded (Android cache)
      final bonded = await FlutterBluePlus.bondedDevices;
      final cached = bonded.where((d) => d.remoteId.str == lastMac).toList();
      if (cached.isNotEmpty) {
        return await connect(cached.first);
      }

      // Otherwise scan briefly for the specific device
      _emit(_state.copyWith(
        connectionState: WatchConnectionState.scanning,
        deviceName: lastName,
        deviceMac: lastMac,
      ));

      // Broad scan untuk autoConnect — konsisten dengan startScan().
      // Timeout 8 detik agar device punya waktu mulai advertising.
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 8),
      );

      BluetoothDevice? found;
      final completer = Completer<BluetoothDevice?>();

      final sub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          if (r.device.remoteId.str == lastMac && !completer.isCompleted) {
            completer.complete(r.device);
          }
        }
      });

      found = await completer.future.timeout(
        const Duration(seconds: 7),
        onTimeout: () => null,
      );

      await FlutterBluePlus.stopScan();
      sub.cancel();

      if (found == null) {
        _emit(_state.copyWith(connectionState: WatchConnectionState.disconnected));
        return false;
      }

      return await connect(found);
    } catch (_) {
      _emit(_state.copyWith(connectionState: WatchConnectionState.disconnected));
      return false;
    }
  }

  /// Disconnect and clean up.
  Future<void> disconnect() async {
    _hrNotifySub?.cancel();
    _hrNotifySub = null;
    _connStateSub?.cancel();
    _connStateSub = null;
    stopScan();
    try {
      await _device?.disconnect();
    } catch (_) {}
    _device = null;
    _emit(_state.copyWith(
      connectionState: WatchConnectionState.disconnected,
      hasHeartRate: false,
    ));
  }

  /// Forget the last paired device.
  Future<void> forgetDevice() async {
    await disconnect();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPrefLastWatchMac);
    await prefs.remove(_kPrefLastWatchName);
  }

  void dispose() {
    _hrNotifySub?.cancel();
    _connStateSub?.cancel();
    _scanSub?.cancel();
    _adapterSub?.cancel();
    _stateController.close();
    _hrController.close();
    _discoveredController.close();
  }

  // ── HR Data Parsing ───────────────────────────────────────────────────────

  /// Parse Heart Rate Measurement characteristic (0x2A37).
  ///
  /// Byte 0: Flags
  ///   bit 0 = 0 → HR value is uint8 (byte 1)
  ///   bit 0 = 1 → HR value is uint16 (bytes 1–2)
  void _onHrData(List<int> data) {
    if (data.isEmpty) return;
    final flags = data[0];
    final isUint16 = (flags & 0x01) != 0;
    int bpm;
    if (isUint16 && data.length >= 3) {
      bpm = data[1] | (data[2] << 8);
    } else if (data.length >= 2) {
      bpm = data[1];
    } else {
      return;
    }
    if (bpm > 0 && bpm < 250) {
      if (!_hrController.isClosed) _hrController.add(bpm);
    }
  }
}
