import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/watch_service.dart';
import '../../providers/app_providers.dart';

/// Bottom sheet untuk scan, pilih, dan pair smartwatch BLE.
/// Ditampilkan dari WorkoutActiveScreen via tombol "Hubungkan Smartwatch".
class WatchPairingSheet extends ConsumerStatefulWidget {
  const WatchPairingSheet({super.key});

  @override
  ConsumerState<WatchPairingSheet> createState() => _WatchPairingSheetState();
}

class _WatchPairingSheetState extends ConsumerState<WatchPairingSheet> {
  List<ScanResult> _devices = [];
  StreamSubscription<List<ScanResult>>? _scanSub;
  String? _connectingMac;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    super.dispose();
  }

  void _startScan() {
    setState(() {
      _devices.clear();
      _errorMsg = null;
    });

    _scanSub?.cancel();
    _scanSub = WatchService.instance.discoveredStream.listen((results) {
      if (mounted) setState(() => _devices = results);
    });

    WatchService.instance.startScan(timeout: const Duration(seconds: 12));
  }

  Future<void> _connect(BluetoothDevice device) async {
    setState(() {
      _connectingMac = device.remoteId.str;
      _errorMsg = null;
    });

    final ok = await WatchService.instance.connect(device);

    if (!mounted) return;
    setState(() => _connectingMac = null);

    if (ok) {
      Navigator.of(context).pop(true); // success → close sheet
    } else {
      setState(() {
        _errorMsg = WatchService.instance.state.errorMessage ??
            'Koneksi gagal. Coba lagi.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final watchState = ref.watch(watchStateProvider).valueOrNull;
    final isConnected = watchState?.isConnected ?? false;
    final isScanning = WatchService.instance.state.isScanning;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.watch_rounded,
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Hubungkan Smartwatch',
                    style: TextStyle(
                      color: AppColors.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    isConnected
                        ? '✅ Terhubung ke ${watchState?.deviceName}'
                        : isScanning
                            ? 'Mencari perangkat dengan Heart Rate...'
                            : '${_devices.length} perangkat ditemukan',
                    style: const TextStyle(
                      color: AppColors.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              if (isScanning)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(AppColors.primary),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Error banner
          if (_errorMsg != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
              ),
              child: Text(
                _errorMsg!,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 12,
                ),
              ),
            ),

          // Currently connected device
          if (isConnected && watchState != null) ...[
            _DeviceTile(
              name: watchState.deviceName,
              mac: watchState.deviceMac,
              battery: watchState.batteryLevel,
              isConnected: true,
              isConnecting: false,
              onTap: () {},
              onDisconnect: () async {
                await WatchService.instance.disconnect();
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
            const SizedBox(height: 8),
            const Divider(color: Colors.white12),
            const SizedBox(height: 8),
          ],

          // Scanned device list
          if (_devices.isEmpty && !isScanning)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    Icon(Icons.bluetooth_searching_rounded,
                        color: AppColors.onSurfaceVariant.withOpacity(0.4),
                        size: 48),
                    const SizedBox(height: 8),
                    Text(
                      'Tidak ada perangkat ditemukan.\nPastikan smartwatch dalam jangkauan dan mode pairing aktif.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.onSurfaceVariant.withOpacity(0.7),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _devices.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: Colors.white10),
                itemBuilder: (ctx, i) {
                  final r = _devices[i];
                  final name = r.device.platformName.isNotEmpty
                      ? r.device.platformName
                      : 'Smartwatch (${r.device.remoteId.str.substring(0, 8)})';
                  return _DeviceTile(
                    name: name,
                    mac: r.device.remoteId.str,
                    battery: -1,
                    isConnected: false,
                    isConnecting: _connectingMac == r.device.remoteId.str,
                    onTap: () => _connect(r.device),
                    onDisconnect: null,
                    rssi: r.rssi,
                  );
                },
              ),
            ),

          const SizedBox(height: 16),

          // Rescan + Forget buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(color: AppColors.primary.withOpacity(0.4)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: const StadiumBorder(),
                  ),
                  onPressed: isScanning ? null : _startScan,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Cari Ulang',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              if (isConnected) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: BorderSide(color: Colors.redAccent.withOpacity(0.4)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: const StadiumBorder(),
                    ),
                    onPressed: () async {
                      await WatchService.instance.forgetDevice();
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.link_off_rounded, size: 18),
                    label: const Text('Lupakan',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Device Tile ──────────────────────────────────────────────────────────────

class _DeviceTile extends StatelessWidget {
  final String name;
  final String mac;
  final int battery;
  final bool isConnected;
  final bool isConnecting;
  final VoidCallback onTap;
  final VoidCallback? onDisconnect;
  final int? rssi;

  const _DeviceTile({
    required this.name,
    required this.mac,
    required this.battery,
    required this.isConnected,
    required this.isConnecting,
    required this.onTap,
    required this.onDisconnect,
    this.rssi,
  });

  String _signalLabel(int? rssi) {
    if (rssi == null) return '';
    if (rssi > -60) return '📶 Kuat';
    if (rssi > -80) return '📶 Sedang';
    return '📶 Lemah';
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isConnected
              ? AppColors.primary.withOpacity(0.12)
              : AppColors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          isConnected ? Icons.watch_rounded : Icons.bluetooth_rounded,
          color: isConnected ? AppColors.primary : AppColors.onSurfaceVariant,
          size: 20,
        ),
      ),
      title: Text(
        name,
        style: TextStyle(
          color: AppColors.onSurface,
          fontSize: 14,
          fontWeight: isConnected ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
      subtitle: Text(
        [
          mac.length > 11 ? mac.substring(0, 11) : mac,
          if (battery >= 0) '🔋 $battery%',
          _signalLabel(rssi),
          if (isConnected) '✅ Terhubung',
        ].where((s) => s.isNotEmpty).join(' • '),
        style: const TextStyle(
          color: AppColors.onSurfaceVariant,
          fontSize: 11,
        ),
      ),
      trailing: isConnecting
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(AppColors.primary),
              ),
            )
          : isConnected
              ? IconButton(
                  icon: const Icon(Icons.link_off_rounded,
                      color: Colors.redAccent, size: 20),
                  onPressed: onDisconnect,
                )
              : const Icon(Icons.arrow_forward_ios_rounded,
                  color: AppColors.onSurfaceVariant, size: 14),
      onTap: isConnected || isConnecting ? null : onTap,
    );
  }
}
