import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nsd/nsd.dart';

import '../models/device.dart';

/// Immutable state for the device scanner.
class ScannerState {
  final bool isScanning;
  final List<Device> devices;
  final String? error;

  const ScannerState({
    this.isScanning = false,
    this.devices = const [],
    this.error,
  });

  ScannerState copyWith({
    bool? isScanning,
    List<Device>? devices,
    String? error,
  }) => ScannerState(
    isScanning: isScanning ?? this.isScanning,
    devices: devices ?? this.devices,
    error: error,
  );
}

/// Riverpod [Notifier] that manages mDNS / NSD device discovery.
///
/// Scans for `_roku._tcp` (Roku-specific) and `_http._tcp` (generic)
/// service types and maps discovered services to [Device] objects.
/// Filters for Roku devices based on port 8060 or name heuristics.
class ScannerNotifier extends Notifier<ScannerState> {
  final List<Discovery> _discoveries = [];

  @override
  ScannerState build() {
    // Clean up NSD when provider is disposed
    ref.onDispose(() => stopScan());
    return const ScannerState();
  }

  /// Start scanning for devices on the local network.
  Future<void> startScan() async {
    state = state.copyWith(isScanning: true, devices: [], error: null);

    // Service types that Roku and other smart devices advertise
    final serviceTypes = [
      '_roku._tcp', // Roku-specific
      '_http._tcp', // Generic HTTP (Roku/Samsung often uses this)
      '_samsungtv._tcp', // Samsung Tizen specific
      '_smart-tv._tcp', // Samsung occasionally uses this
      '_samsungbridge._tcp', // Some Samsung devices
      '_googlecast._tcp', // Chromecast (future use)
      '_airplay._tcp', // AirPlay (future use)
    ];

    try {
      for (final type in serviceTypes) {
        final discovery = await startDiscovery(
          type,
          ipLookupType: IpLookupType.any,
        );
        _discoveries.add(discovery);
        discovery.addServiceListener((service, status) {
          if (status == ServiceStatus.found) {
            _handleServiceFound(service);
          }
        });
      }

      // Stop the scanning animation after 10 seconds, but keep
      // listening for new services in the background.
      Future.delayed(const Duration(seconds: 10), () {
        if (state.isScanning) {
          state = state.copyWith(isScanning: false);
        }
      });
    } catch (e) {
      debugPrint('ScannerNotifier: Discovery error — $e');
      state = state.copyWith(isScanning: false, error: 'Discovery failed: $e');
    }
  }

  /// Stop all active discoveries and release resources.
  Future<void> stopScan() async {
    for (final discovery in _discoveries) {
      try {
        await stopDiscovery(discovery);
      } catch (e) {
        debugPrint('ScannerNotifier: Error stopping discovery — $e');
      }
    }
    _discoveries.clear();
    state = state.copyWith(isScanning: false);
  }

  /// Map an NSD [Service] to a [Device] and add it to state,
  /// filtering duplicates and non-Roku devices.
  void _handleServiceFound(Service service) {
    final name = service.name ?? '';
    final host = service.host ?? '';
    final port = service.port ?? 0;
    final type = service.type ?? '';

    // Extract real IP address from resolved addresses, fallback to host
    final addresses = service.addresses ?? [];
    final ip = addresses.isNotEmpty ? addresses.first.address : host;

    if (name.isEmpty || ip.isEmpty) return;

    // Determine device type based on service metadata
    String deviceType;
    if (port == 8060 ||
        name.toLowerCase().contains('roku') ||
        type.contains('_roku')) {
      deviceType = 'roku';
    } else if (name.toLowerCase().contains('samsung') ||
        type.contains('samsung')) {
      deviceType = 'samsung';
    } else if (type.contains('_googlecast')) {
      deviceType = 'chromecast';
    } else if (type.contains('_airplay')) {
      deviceType = 'airplay';
    } else {
      deviceType = 'wifi';
    }

    // Filter out duplicates by ip+port
    final existing = state.devices;
    if (existing.any((d) => d.ip == ip && d.port == port)) return;

    final device = Device(
      id: '$ip:$port',
      name: name,
      type: deviceType,
      model: type.replaceAll('._tcp', '').replaceAll('_', ''),
      signal: 100,
      ip: ip,
      port: port,
    );

    state = state.copyWith(devices: [...existing, device]);
    debugPrint(
      'ScannerNotifier: Found device "$name" at $ip:$port ($deviceType)',
    );
  }
}

/// Global provider for the device scanner.
final scannerProvider = NotifierProvider<ScannerNotifier, ScannerState>(
  ScannerNotifier.new,
);
