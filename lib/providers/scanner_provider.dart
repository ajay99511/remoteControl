import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nsd/nsd.dart';
import 'package:permission_handler/permission_handler.dart' hide ServiceStatus;

import '../core/app_logger.dart';
import '../models/device.dart';
import 'discovery_parsers.dart';

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

  /// [clearError] mirrors the convention already used by
  /// [DeviceConnectionState]. Without it `error` was the one field that did
  /// not default to its current value, so every unrelated update - the scan
  /// deadline, each discovered device, every stopScan - silently wiped an
  /// error the user had not read yet.
  ScannerState copyWith({
    bool? isScanning,
    List<Device>? devices,
    String? error,
    bool clearError = false,
  }) =>
      ScannerState(
        isScanning: isScanning ?? this.isScanning,
        devices: devices ?? this.devices,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Binds the UDP socket the SSDP probe listens on.
///
/// Injected so the scanner's resource handling is testable. Overridden in
/// tests; production binds a real socket.
typedef DatagramSocketBinder = Future<RawDatagramSocket> Function();

final ssdpSocketBinderProvider = Provider<DatagramSocketBinder>(
  (_) => () => RawDatagramSocket.bind(InternetAddress.anyIPv4, 0),
);

/// Whether to run mDNS/NSD discovery. Off on web and Windows, which nsd does
/// not support; overridden in tests so they never touch the network.
final mdnsEnabledProvider = Provider<bool>(
  (_) => !kIsWeb && !Platform.isWindows,
);

/// Riverpod [Notifier] that manages mDNS / NSD and SSDP device discovery.
class ScannerNotifier extends Notifier<ScannerState> {
  static const _scanWindow = Duration(seconds: 10);
  static const _ssdpListenWindow = Duration(seconds: 8);
  static const _ssdpProbeCount = 3;
  static const _ssdpProbeInterval = Duration(milliseconds: 500);
  static const _ssdpPort = 1900;
  static const _ssdpMulticast = '239.255.255.250';

  final List<Discovery> _discoveries = [];

  // Every one of these used to be started and then forgotten. None could be
  // cancelled, so a scan outlived the screen that requested it: the 10s
  // deadline woke up and assigned state on a disposed Notifier, and the UDP
  // socket stayed bound and listening for a further 8 seconds per rescan.
  Timer? _scanDeadline;
  Timer? _ssdpDeadline;
  RawDatagramSocket? _ssdpSocket;
  StreamSubscription<RawSocketEvent>? _ssdpSub;
  bool _disposed = false;

  late final DatagramSocketBinder _bindSocket;
  late final bool _mdnsEnabled;

  @override
  ScannerState build() {
    _bindSocket = ref.read(ssdpSocketBinderProvider);
    _mdnsEnabled = ref.read(mdnsEnabledProvider);

    ref.onDispose(() {
      _disposed = true;
      _releaseResources();
      stopScan(isDisposing: true);
    });
    return const ScannerState();
  }

  /// Releases only the SSDP transport.
  ///
  /// Kept separate from [_releaseResources] because the SSDP listen window
  /// (8s) closes before the scan window (10s); tearing everything down here
  /// would cancel the scan deadline and leave `isScanning` stuck on.
  void _releaseSsdp() {
    _ssdpDeadline?.cancel();
    _ssdpDeadline = null;
    _ssdpSub?.cancel();
    _ssdpSub = null;
    _ssdpSocket?.close();
    _ssdpSocket = null;
  }

  /// Cancels every timer, subscription and socket this notifier owns.
  void _releaseResources() {
    _scanDeadline?.cancel();
    _scanDeadline = null;
    _releaseSsdp();
  }

  /// Start scanning for devices on the local network.
  Future<void> startScan() async {
    if (_disposed) return;

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
    if (_disposed) return;

    state = state.copyWith(isScanning: true, devices: [], clearError: true);

    const serviceTypes = [
      '_roku._tcp',
      '_http._tcp',
      '_samsungtv._tcp',
      '_smart-tv._tcp',
      '_samsungbridge._tcp',
      '_googlecast._tcp',
      '_airplay._tcp',
    ];

    try {
      if (_mdnsEnabled) {
        for (final type in serviceTypes) {
          final discovery =
              await startDiscovery(type, ipLookupType: IpLookupType.any);
          if (_disposed) {
            await stopDiscovery(discovery);
            return;
          }
          _discoveries.add(discovery);
          discovery.addServiceListener((service, status) {
            if (status == ServiceStatus.found) _handleServiceFound(service);
          });
        }
      }

      unawaited(_startSsdpDiscovery());

      _scanDeadline?.cancel();
      _scanDeadline = Timer(_scanWindow, () {
        if (_disposed) return;
        if (state.isScanning) state = state.copyWith(isScanning: false);
      });
    } catch (e, s) {
      log.e('ScannerNotifier: Discovery error', e, s);
      if (_disposed) return;
      state = state.copyWith(isScanning: false, error: 'Discovery failed: $e');
    }
  }

  /// Stop all active discoveries and release resources.
  Future<void> stopScan({bool isDisposing = false}) async {
    _releaseResources();

    final activeDiscoveries = List<Discovery>.from(_discoveries);
    _discoveries.clear();

    for (final discovery in activeDiscoveries) {
      try {
        await stopDiscovery(discovery);
      } catch (e) {
        log.e('ScannerNotifier: Error stopping discovery', e);
      }
    }
    if (!isDisposing && !_disposed) {
      state = state.copyWith(isScanning: false);
    }
  }

  void _handleServiceFound(Service service) {
    final device = parseMdnsService(
      name: service.name ?? '',
      host: service.host ?? '',
      port: service.port ?? 0,
      type: service.type ?? '',
      addresses: [for (final a in service.addresses ?? []) a.address],
    );
    if (device == null) return;
    _addDevice(device, via: 'mDNS');
  }

  /// Merges a discovered device into state, keyed by host.
  void _addDevice(Device device, {required String via}) {
    if (_disposed) return;
    final merged = mergeDiscovered(state.devices, device);
    if (identical(merged, state.devices)) return;
    state = state.copyWith(devices: merged);
    log.d('ScannerNotifier: found "${device.name}" at ${device.ip}:'
        '${device.port} (${device.type.name}) via $via');
  }

  Future<void> _startSsdpDiscovery() async {
    try {
      final socket = await _bindSocket();
      if (_disposed) {
        socket.close();
        return;
      }
      socket.broadcastEnabled = true;
      _ssdpSocket = socket;

      const searchMessage = 'M-SEARCH * HTTP/1.1\r\n'
          'HOST: $_ssdpMulticast:$_ssdpPort\r\n'
          'MAN: "ssdp:discover"\r\n'
          'MX: 3\r\n'
          'ST: ssdp:all\r\n\r\n';

      final data = utf8.encode(searchMessage);
      final multicastAddress = InternetAddress(_ssdpMulticast);

      // Several probes: a single M-SEARCH is routinely dropped on Wi-Fi.
      for (var i = 0; i < _ssdpProbeCount; i++) {
        if (_disposed || _ssdpSocket == null) return;
        socket.send(data, multicastAddress, _ssdpPort);
        if (i < _ssdpProbeCount - 1) {
          await Future<void>.delayed(_ssdpProbeInterval);
        }
      }

      _ssdpSub = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null) return;
        try {
          _handleSsdpResponse(
            utf8.decode(datagram.data),
            datagram.address.address,
          );
        } on FormatException catch (e) {
          // A malformed datagram from any host on the LAN must not take the
          // scan down with it.
          log.d('ScannerNotifier: undecodable SSDP datagram ignored', e);
        }
      });

      _ssdpDeadline?.cancel();
      _ssdpDeadline = Timer(_ssdpListenWindow, _releaseSsdp);
    } catch (e, s) {
      log.e('ScannerNotifier: SSDP error', e, s);
    }
  }

  void _handleSsdpResponse(String response, String sourceIp) {
    final device = parseSsdpResponse(response, sourceIp);
    if (device == null) return;
    _addDevice(device, via: 'SSDP');
  }
}

/// Global provider for the device scanner.
final scannerProvider = NotifierProvider<ScannerNotifier, ScannerState>(
  ScannerNotifier.new,
);
