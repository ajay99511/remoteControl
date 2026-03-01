import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
      // The `nsd` package has known threading issues on Windows and throws platform channel exceptions.
      // We will skip mDNS entirely on Windows and rely solely on the SSDP fallback.
      if (!kIsWeb && !Platform.isWindows) {
        for (final type in serviceTypes) {
          final discovery = await startDiscovery(
            type,
            ipLookupType: IpLookupType.any, // Use any as defined in nsd package
          );
          _discoveries.add(discovery);
          discovery.addServiceListener((service, status) {
            if (status == ServiceStatus.found) {
              _handleServiceFound(service);
            }
          });
        }
      }

      // Also start SSDP discovery as a fallback for Windows where mDNS might fail
      _startSsdpDiscovery();

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
    final activeDiscoveries = List<Discovery>.from(_discoveries);
    _discoveries.clear();

    for (final discovery in activeDiscoveries) {
      try {
        await stopDiscovery(discovery);
      } catch (e) {
        debugPrint('ScannerNotifier: Error stopping discovery — $e');
      }
    }
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
    int resolvedPort = port;
    if (port == 8060 ||
        name.toLowerCase().contains('roku') ||
        type.contains('_roku')) {
      deviceType = 'roku';
      if (resolvedPort == 80) resolvedPort = 8060;
    } else if (name.toLowerCase().contains('samsung') ||
        type.contains('samsung')) {
      deviceType = 'samsung';
      // If we found a Samsung device but mDNS gave us port 80, assume 8002
      if (resolvedPort == 80) resolvedPort = 8002;
    } else if (type.contains('_googlecast')) {
      deviceType = 'chromecast';
    } else if (type.contains('_airplay')) {
      deviceType = 'airplay';
    } else {
      deviceType = 'wifi';
    }

    // Filter out duplicates by ip+port
    final existing = state.devices;
    if (existing.any((d) => d.ip == ip && d.port == resolvedPort)) return;

    final device = Device(
      id: '$ip:$resolvedPort',
      name: name,
      type: deviceType,
      model: type.replaceAll('._tcp', '').replaceAll('_', ''),
      signal: 100,
      ip: ip,
      port: port,
    );

    state = state.copyWith(devices: [...existing, device]);
    debugPrint(
      'ScannerNotifier: Found device "$name" at $ip:$port ($deviceType) via mDNS',
    );
  }

  /// Fallback SSDP (Simple Service Discovery Protocol) scanner.
  /// Extremely useful on Windows where Bonjour/mDNS might be unavailable or blocked.
  Future<void> _startSsdpDiscovery() async {
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      // SSDP M-SEARCH payload (discover all upnp devices)
      const searchMessage =
          'M-SEARCH * HTTP/1.1\r\n'
          'HOST: 239.255.255.250:1900\r\n'
          'MAN: "ssdp:discover"\r\n'
          'MX: 3\r\n'
          'ST: ssdp:all\r\n\r\n';

      final data = utf8.encode(searchMessage);
      final multicastAddress = InternetAddress('239.255.255.250');

      socket.send(data, multicastAddress, 1900);

      socket.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket.receive();
          if (datagram != null) {
            final response = utf8.decode(datagram.data);
            _handleSsdpResponse(response, datagram.address.address);
          }
        }
      });

      // Keep SSDP socket alive for 5 seconds
      Future.delayed(const Duration(seconds: 5), () {
        socket.close();
      });
    } catch (e) {
      debugPrint('ScannerNotifier: SSDP error — $e');
    }
  }

  /// Parse an HTTP-like SSDP response and map to a [Device].
  void _handleSsdpResponse(String response, String sourceIp) {
    if (!response.contains('HTTP/1.1 200 OK')) return;

    final lines = response.split('\r\n');
    String server = '';
    String location = '';

    for (var line in lines) {
      if (line.toUpperCase().startsWith('SERVER:')) {
        server = line.substring(7).trim();
      } else if (line.toUpperCase().startsWith('LOCATION:')) {
        location = line.substring(9).trim();
      }
    }

    if (location.isEmpty) return;

    String deviceType = 'wifi';
    String name = 'Unknown Device';
    int port = 80; // default generic port
    String ip = sourceIp;

    // Roku devices typically broadcast Server: Roku UPnP/1.0
    // and Location usually points to http://ip:8060/
    if (server.toLowerCase().contains('roku') || location.contains(':8060')) {
      deviceType = 'roku';
      name = 'Roku Device';
      port = 8060;
    }
    // Samsung Tizen usually broadcasts SEC_UDP or similar, and has port 8001 or 8002 in location
    else if (server.toLowerCase().contains('samsung') ||
        location.contains('samsung') ||
        location.contains(':8001') ||
        location.contains(':8002')) {
      deviceType = 'samsung';
      name = 'Samsung TV';
      if (location.contains(':8002'))
        port = 8002;
      else if (location.contains(':8001'))
        port = 8001;
      else
        port = 8002; // Default to secure websocket port for modern Samsung TVs
    } else {
      // Ignore other UPnP devices for now
      return;
    }

    final existing = state.devices;
    if (existing.any((d) => d.ip == ip && d.port == port)) return;

    final device = Device(
      id: '$ip:$port',
      name: name,
      type: deviceType,
      model: 'SSDP Discovered',
      signal: 100,
      ip: ip,
      port: port,
    );

    // Run safe state updates
    state = state.copyWith(devices: [...existing, device]);
    debugPrint(
      'ScannerNotifier: Found device "$name" at $ip:$port ($deviceType) via SSDP',
    );
  }
}

/// Global provider for the device scanner.
final scannerProvider = NotifierProvider<ScannerNotifier, ScannerState>(
  ScannerNotifier.new,
);
