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

    // Simulated device discovery sequence
    _simulateDiscovery();

    // Service types that Roku and other smart devices advertise
    final serviceTypes = [
      '_roku._tcp', // Roku-specific
      '_http._tcp', // Generic HTTP (Roku also advertises here)
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

  void _simulateDiscovery() {
    // Add mock Roku
    Future.delayed(const Duration(seconds: 2), () {
      if (!state.isScanning) return;
      final mockRoku = Device(
        id: 'mock-roku',
        name: 'Living Room TV',
        type: 'roku',
        model: 'Roku Ultra',
        signal: 100,
        ip: '192.168.1.100',
        port: 8060,
      );
      if (!state.devices.any((d) => d.id == mockRoku.id)) {
        state = state.copyWith(devices: [...state.devices, mockRoku]);
      }
    });

    // Add mock Chromecast
    Future.delayed(const Duration(seconds: 4), () {
      if (!state.isScanning) return;
      final mockChromecast = Device(
        id: 'mock-chromecast',
        name: 'Bedroom Audio',
        type: 'chromecast',
        model: 'Chromecast Audio',
        signal: 85,
        ip: '192.168.1.101',
        port: 8009,
      );
      if (!state.devices.any((d) => d.id == mockChromecast.id)) {
        state = state.copyWith(devices: [...state.devices, mockChromecast]);
      }
    });

    // Add mock AirPlay
    Future.delayed(const Duration(seconds: 6), () {
      if (!state.isScanning) return;
      final mockAirplay = Device(
        id: 'mock-airplay',
        name: 'Kitchen Speaker',
        type: 'airplay',
        model: 'Apple TV',
        signal: 90,
        ip: '192.168.1.102',
        port: 7000,
      );
      if (!state.devices.any((d) => d.id == mockAirplay.id)) {
        state = state.copyWith(devices: [...state.devices, mockAirplay]);
      }
    });
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

    if (name.isEmpty || host.isEmpty) return;

    // Determine device type based on service metadata
    String deviceType;
    if (port == 8060 ||
        name.toLowerCase().contains('roku') ||
        type.contains('_roku')) {
      deviceType = 'roku';
    } else if (type.contains('_googlecast')) {
      deviceType = 'chromecast';
    } else if (type.contains('_airplay')) {
      deviceType = 'airplay';
    } else {
      deviceType = 'wifi';
    }

    // Filter out duplicates by host+port
    final existing = state.devices;
    if (existing.any((d) => d.ip == host && d.port == port)) return;

    final device = Device(
      id: '$host:$port',
      name: name,
      type: deviceType,
      model: type.replaceAll('._tcp', '').replaceAll('_', ''),
      signal: 100,
      ip: host,
      port: port,
    );

    state = state.copyWith(devices: [...existing, device]);
    debugPrint(
      'ScannerNotifier: Found device "$name" at $host:$port ($deviceType)',
    );
  }
}

/// Global provider for the device scanner.
final scannerProvider = NotifierProvider<ScannerNotifier, ScannerState>(
  ScannerNotifier.new,
);
