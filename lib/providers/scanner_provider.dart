import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nsd/nsd.dart';
import 'package:permission_handler/permission_handler.dart' hide ServiceStatus;

import '../core/app_logger.dart';
import '../models/device.dart';
import '../services/device_description.dart';
import '../services/device_persistence_service.dart';
import 'discovery_parsers.dart';

/// Immutable state for the device scanner.
class ScannerState {
  final bool isScanning;
  final List<Device> devices;
  final String? error;

  /// [Device.credentialKey]s of entries restored from storage that this scan
  /// has not yet heard from.
  ///
  /// A device the user has connected to before is shown immediately rather
  /// than after a multi-second sweep, but until it answers, all we have is a
  /// memory and an address the router may since have reassigned. The UI needs
  /// to say which is which.
  final Set<String> restored;

  const ScannerState({
    this.isScanning = false,
    this.devices = const [],
    this.error,
    this.restored = const {},
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
    Set<String>? restored,
  }) => ScannerState(
    isScanning: isScanning ?? this.isScanning,
    devices: devices ?? this.devices,
    error: clearError ? null : (error ?? this.error),
    restored: restored ?? this.restored,
  );
}

/// Binds the UDP socket the SSDP probe listens on.
///
/// Injected so the scanner's resource handling is testable. Overridden in
/// tests; production binds a real socket.
typedef DatagramSocketBinder = Future<RawDatagramSocket> Function();

final ssdpSocketBinderProvider = Provider<DatagramSocketBinder>(
  (_) =>
      () => RawDatagramSocket.bind(InternetAddress.anyIPv4, 0),
);

/// Whether to run mDNS/NSD discovery. Off on web and Windows, which nsd does
/// not support; overridden in tests so they never touch the network.
final mdnsEnabledProvider = Provider<bool>(
  (_) => !kIsWeb && !Platform.isWindows,
);

/// Reads a discovered device's self-description. Overridden in tests.
final deviceDescriptionFetcherProvider = Provider<DeviceDescriptionFetcher>(
  (_) => fetchDeviceDescription,
);

/// Reads the devices the user has connected to before. Overridden in tests so
/// the scanner never touches the keychain.
typedef KnownDevicesLoader = Future<List<Device>> Function();

final knownDevicesLoaderProvider = Provider<KnownDevicesLoader>(
  (ref) => ref.watch(devicePersistenceProvider).loadKnownDevices,
);

/// Riverpod [Notifier] that manages mDNS / NSD and SSDP device discovery.
class ScannerNotifier extends Notifier<ScannerState> {
  static const _scanWindow = Duration(seconds: 10);
  static const _ssdpListenWindow = Duration(seconds: 8);
  static const _ssdpProbeCount = 3;
  static const _ssdpProbeInterval = Duration(milliseconds: 500);
  static const _ssdpPort = 1900;
  static const _ssdpMulticast = '239.255.255.250';

  /// Search targets, most specific first.
  ///
  /// `ssdp:all` alone asks every UPnP device on the segment to answer, which
  /// is noisy, slower to filter, and something some access points rate-limit.
  /// Real remotes ask for what they can control: Roku defines `roku:ecp`, and
  /// DIAL is the multiscreen standard Roku, Samsung and Vizio all implement.
  /// `ssdp:all` stays last so anything not covered still turns up.
  static const _searchTargets = [
    'roku:ecp',
    'urn:dial-multiscreen-org:service:dial:1',
    'urn:schemas-upnp-org:device:MediaRenderer:1',
    'ssdp:all',
  ];

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

  /// Which scan the SSDP probe belongs to.
  ///
  /// Binding a UDP socket is asynchronous, so a stopScan or a rescan can land
  /// between the request and the socket arriving. Without this the probe went
  /// on to adopt a socket for a scan that no longer existed, and nothing was
  /// left holding a reference to close it.
  int _scanGeneration = 0;

  late final DatagramSocketBinder _bindSocket;
  late final bool _mdnsEnabled;
  late final DeviceDescriptionFetcher _fetchDescription;
  late final KnownDevicesLoader _loadKnownDevices;

  /// Description URLs already requested. Devices answer every search target,
  /// so without this a single TV would be fetched four times per round.
  final Set<Uri> _describing = {};

  @override
  ScannerState build() {
    _bindSocket = ref.read(ssdpSocketBinderProvider);
    _mdnsEnabled = ref.read(mdnsEnabledProvider);
    _fetchDescription = ref.read(deviceDescriptionFetcherProvider);
    _loadKnownDevices = ref.read(knownDevicesLoaderProvider);

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
    _scanGeneration++;

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

    _describing.clear();
    state = state.copyWith(
      isScanning: true,
      devices: [],
      restored: {},
      clearError: true,
    );
    await _seedFromMemory();
    if (_disposed) return;

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
        // Started concurrently: these are seven independent registrations and
        // awaiting them one at a time delayed the whole scan, SSDP included,
        // by the sum of their setup latencies.
        final started = await Future.wait(
          serviceTypes.map(
            (type) => startDiscovery(type, ipLookupType: IpLookupType.any),
          ),
        );

        if (_disposed) {
          await Future.wait(started.map(stopDiscovery));
          return;
        }

        for (final discovery in started) {
          _discoveries.add(discovery);
          discovery.addServiceListener((service, status) {
            if (status == ServiceStatus.found) _handleServiceFound(service);
          });
        }
      }

      unawaited(_startSsdpDiscovery(_scanGeneration));

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
    _scanGeneration++;
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
      addresses: [
        for (final a in service.addresses ?? const <InternetAddress>[])
          a.address,
      ],
    );
    if (device == null) return;
    _addDevice(device, via: 'mDNS');
  }

  /// Shows devices the user has connected to before, before the network has
  /// had a chance to answer.
  ///
  /// A sweep takes seconds; a remote that opens on an empty list every time
  /// is one that has forgotten the television it was talking to a minute ago.
  /// A live sighting merges over the remembered entry and updates its address,
  /// so a device that moved is corrected rather than duplicated.
  Future<void> _seedFromMemory() async {
    final List<Device> known;
    try {
      known = await _loadKnownDevices();
    } catch (e, s) {
      // Memory is a convenience; losing it must not stop a scan.
      log.e('ScannerNotifier: could not read remembered devices', e, s);
      return;
    }
    if (_disposed || known.isEmpty || state.devices.isNotEmpty) return;

    state = state.copyWith(
      devices: known,
      restored: {for (final d in known) d.credentialKey},
    );
  }

  /// Merges a discovered device into state, keyed by host.
  void _addDevice(Device device, {required String via}) {
    if (_disposed) return;

    // A sighting confirms whichever entry it matches, so the same rule that
    // decides the merge decides whether a remembered device has answered.
    final matched = indexOfDevice(state.devices, device);
    final confirmed = matched < 0 ? null : state.devices[matched].credentialKey;

    final merged = mergeDiscovered(state.devices, device);
    if (identical(merged, state.devices) &&
        !(confirmed != null && state.restored.contains(confirmed))) {
      return;
    }
    state = state.copyWith(
      devices: merged,
      restored: confirmed == null || !state.restored.contains(confirmed)
          ? null
          : ({...state.restored}..remove(confirmed)),
    );
    log.d(
      'ScannerNotifier: found "${device.name}" at ${device.ip}:'
      '${device.port} (${device.type.name}) via $via',
    );
  }

  Future<void> _startSsdpDiscovery(int generation) async {
    try {
      final socket = await _bindSocket();
      if (_disposed || generation != _scanGeneration) {
        socket.close();
        return;
      }
      socket.broadcastEnabled = true;
      _ssdpSocket = socket;

      // Listen before probing. Sending three rounds of probes first and only
      // then attaching the listener meant the window where a prompt responder
      // replies was open before anything was reading the socket.
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

      final multicastAddress = InternetAddress(_ssdpMulticast);

      // One probe per search target, repeated: a single M-SEARCH is routinely
      // dropped on Wi-Fi and UDP offers no retransmission of its own.
      for (var round = 0; round < _ssdpProbeCount; round++) {
        for (final target in _searchTargets) {
          if (_disposed ||
              _ssdpSocket == null ||
              generation != _scanGeneration) {
            return;
          }
          socket.send(
            utf8.encode(_mSearch(target)),
            multicastAddress,
            _ssdpPort,
          );
        }
        if (round < _ssdpProbeCount - 1) {
          await Future<void>.delayed(_ssdpProbeInterval);
        }
      }
    } catch (e, s) {
      log.e('ScannerNotifier: SSDP error', e, s);
    }
  }

  /// An M-SEARCH request for one search target.
  ///
  /// MX is the maximum seconds a device may wait before replying; UPnP
  /// requires 1-5, and the previous single ssdp:all probe used 3, spreading
  /// every device's answer across three seconds for no benefit.
  static String _mSearch(String searchTarget) =>
      'M-SEARCH * HTTP/1.1\r\n'
      'HOST: $_ssdpMulticast:$_ssdpPort\r\n'
      'MAN: "ssdp:discover"\r\n'
      'MX: 2\r\n'
      'ST: $searchTarget\r\n\r\n';

  void _handleSsdpResponse(String response, String sourceIp) {
    final device = parseSsdpResponse(response, sourceIp);
    if (device == null) return;
    _addDevice(device, via: 'SSDP');

    // The response only points at the description; reading it is what turns
    // "Samsung TV" into the name the owner gave the set. Fired concurrently so
    // a slow or silent device never holds up the scan.
    final location = ssdpLocationOf(response);
    if (location != null) unawaited(_describe(device, location));
  }

  /// Replaces an inferred placeholder name with what the device calls itself.
  Future<void> _describe(Device device, Uri location) async {
    if (!_describing.add(location)) return;

    final description = await _fetchDescription(location);
    if (description == null || _disposed) return;

    final index = state.devices.indexWhere(
      (d) => (device.uid != null && d.uid == device.uid) || d.ip == device.ip,
    );
    if (index < 0) return;

    final existing = state.devices[index];
    final enriched = existing.copyWith(
      name: description.friendlyName,
      model: description.modelName,
      uid: existing.uid ?? description.stableId,
    );
    if (enriched == existing) return;

    state = state.copyWith(devices: [...state.devices]..[index] = enriched);
    log.d(
      'ScannerNotifier: "${existing.name}" describes itself as '
      '"${enriched.name}"',
    );
  }
}

/// Global provider for the device scanner.
final scannerProvider = NotifierProvider<ScannerNotifier, ScannerState>(
  ScannerNotifier.new,
);
