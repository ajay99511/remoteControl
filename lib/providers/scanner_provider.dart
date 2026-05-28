import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nsd/nsd.dart';
import 'package:permission_handler/permission_handler.dart' hide ServiceStatus;

import '../core/app_logger.dart';
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
  }) =>
      ScannerState(
        isScanning: isScanning ?? this.isScanning,
        devices: devices ?? this.devices,
        error: error,
      );
}

/// Riverpod [Notifier] that manages mDNS / NSD and SSDP device discovery.
class ScannerNotifier extends Notifier<ScannerState> {
  final List<Discovery> _discoveries = [];

  @override
  ScannerState build() {
    ref.onDispose(() => stopScan(isDisposing: true));
    return const ScannerState();
  }

  /// Start scanning for devices on the local network.
  Future<void> startScan() async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        final status = await Permission.nearbyWifiDevices.request();
        if (status.isDenied) {
          log.w('ScannerNotifier: Nearby WiFi permission denied');
        }
      } catch (e) {
        log.e('ScannerNotifier: Error requesting permissions', e);
      }
    }

    state = state.copyWith(isScanning: true, devices: [], error: null);

    final serviceTypes = [
      '_roku._tcp',
      '_http._tcp',
      '_samsungtv._tcp',
      '_smart-tv._tcp',
      '_samsungbridge._tcp',
      '_googlecast._tcp',
      '_airplay._tcp',
    ];

    try {
      if (!kIsWeb && !Platform.isWindows) {
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
      }

      _startSsdpDiscovery();

      Future.delayed(const Duration(seconds: 10), () {
        if (state.isScanning) {
          state = state.copyWith(isScanning: false);
        }
      });
    } catch (e) {
      log.e('ScannerNotifier: Discovery error', e);
      state = state.copyWith(isScanning: false, error: 'Discovery failed: $e');
    }
  }

  /// Stop all active discoveries and release resources.
  Future<void> stopScan({bool isDisposing = false}) async {
    final activeDiscoveries = List<Discovery>.from(_discoveries);
    _discoveries.clear();

    for (final discovery in activeDiscoveries) {
      try {
        await stopDiscovery(discovery);
      } catch (e) {
        log.e('ScannerNotifier: Error stopping discovery', e);
      }
    }
    if (!isDisposing) {
      state = state.copyWith(isScanning: false);
    }
  }

  void _handleServiceFound(Service service) {
    final name = service.name ?? '';
    final host = service.host ?? '';
    final port = service.port ?? 0;
    final type = service.type ?? '';

    final addresses = service.addresses ?? [];
    final ip = addresses.isNotEmpty ? addresses.first.address : host;

    if (name.isEmpty || ip.isEmpty) return;

    DeviceType deviceType = DeviceType.unknown;
    int resolvedPort = port;

    if (port == 8060 ||
        name.toLowerCase().contains('roku') ||
        type.contains('_roku')) {
      deviceType = DeviceType.roku;
      if (resolvedPort == 80) resolvedPort = 8060;
    } else if (name.toLowerCase().contains('samsung') ||
        type.contains('samsung')) {
      deviceType = DeviceType.samsung;
      if (resolvedPort == 80) resolvedPort = 8002;
    } else if (type.contains('_googlecast')) {
      deviceType = DeviceType.googleTv;
    } else if (type.contains('_airplay')) {
      // AirPlay could be LG, Vizio, etc.
      deviceType = DeviceType.unknown;
    }

    final existing = state.devices;
    if (existing.any((d) => d.ip == ip && d.port == resolvedPort)) return;

    final device = Device(
      id: '$ip:$resolvedPort',
      name: name,
      type: deviceType,
      model: type.replaceAll('._tcp', '').replaceAll('_', ''),
      signal: 100,
      ip: ip,
      port: resolvedPort,
    );

    state = state.copyWith(devices: [...existing, device]);
    log.d('ScannerNotifier: Found device "$name" at $ip:$resolvedPort (${deviceType.name}) via mDNS');
  }

  Future<void> _startSsdpDiscovery() async {
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      const searchMessage = 'M-SEARCH * HTTP/1.1\r\n'
          'HOST: 239.255.255.250:1900\r\n'
          'MAN: "ssdp:discover"\r\n'
          'MX: 3\r\n'
          'ST: ssdp:all\r\n\r\n';

      final data = utf8.encode(searchMessage);
      final multicastAddress = InternetAddress('239.255.255.250');

      // Send 3 probes with 500ms intervals (Requirement 2.19)
      for (int i = 0; i < 3; i++) {
        socket.send(data, multicastAddress, 1900);
        if (i < 2) await Future.delayed(const Duration(milliseconds: 500));
      }

      socket.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket.receive();
          if (datagram != null) {
            final response = utf8.decode(datagram.data);
            _handleSsdpResponse(response, datagram.address.address);
          }
        }
      });

      // Keep SSDP socket alive for 8 seconds (Requirement 2.19)
      Future.delayed(const Duration(seconds: 8), () {
        socket.close();
      });
    } catch (e) {
      log.e('ScannerNotifier: SSDP error', e);
    }
  }

  void _handleSsdpResponse(String response, String sourceIp) {
    if (!response.toUpperCase().contains('HTTP/1.1 200 OK')) return;

    final lines = response.split('\r\n');
    String server = '';
    String location = '';

    for (var line in lines) {
      final upperLine = line.toUpperCase();
      if (upperLine.startsWith('SERVER:')) {
        server = line.substring(7).trim();
      } else if (upperLine.startsWith('LOCATION:')) {
        location = line.substring(9).trim();
      }
    }

    DeviceType deviceType = DeviceType.unknown;
    String name = 'Unknown Device';
    int port = 80;
    String ip = sourceIp;

    final lowerServer = server.toLowerCase();
    final lowerLoc = location.toLowerCase();

    if (lowerServer.contains('roku') || lowerLoc.contains(':8060')) {
      deviceType = DeviceType.roku;
      name = 'Roku Device';
      port = 8060;
    } else if (lowerServer.contains('samsung') ||
        lowerLoc.contains('samsung') ||
        lowerLoc.contains(':8001') ||
        lowerLoc.contains(':8002')) {
      deviceType = DeviceType.samsung;
      name = 'Samsung TV';
      if (lowerLoc.contains(':8002')) {
        port = 8002;
      } else if (lowerLoc.contains(':8001')) {
        port = 8001;
      } else {
        port = 8002;
      }
    } else if (lowerServer.contains('webos') || lowerLoc.contains(':3000')) {
      deviceType = DeviceType.lg;
      name = 'LG webOS TV';
      port = 3000;
    } else if (lowerLoc.contains(':7345')) {
      deviceType = DeviceType.vizio;
      name = 'Vizio SmartCast TV';
      port = 7345;
    } else {
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

    state = state.copyWith(devices: [...existing, device]);
    log.d('ScannerNotifier: Found device "$name" at $ip:$port (${deviceType.name}) via SSDP');
  }
}

/// Global provider for the device scanner.
final scannerProvider = NotifierProvider<ScannerNotifier, ScannerState>(
  ScannerNotifier.new,
);
