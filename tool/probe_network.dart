// Diagnoses why a television is not reachable from this machine.
//
//   dart run tool/probe_network.dart                 # this machine's /24
//   dart run tool/probe_network.dart 192.168.1       # a specific /24
//
// Deliberately pure `dart:io` with no package imports, so it runs under the
// plain Dart VM. The app cannot be imported here: its models reach
// package:flutter for `@immutable` and `kReleaseMode`, which needs the Flutter
// test harness, and that harness does not survive the long real-network waits
// this makes.
//
// The cost of standing alone is that the request format could drift from the
// app's. `test/tool/probe_network_test.dart` asserts it does not.
//
// It answers, in order:
//
//   1. What network is this machine actually on?
//   2. Does anything answer an SSDP search? (UDP - a host firewall can hide
//      this, so nothing here is suggestive, not conclusive.)
//   3. Is any vendor control port open anywhere on the subnet? (TCP - a host
//      firewall cannot hide this, so this answer is conclusive.)
//   4. Does the Roku ECP endpoint reply to the exact request the app sends?

// A diagnostic CLI: printing is the whole point of it.
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Kept identical to `ssdpSearchTargets` in lib/services/ssdp.dart.
const probeSearchTargets = [
  'roku:ecp',
  'urn:dial-multiscreen-org:service:dial:1',
  'urn:schemas-upnp-org:device:MediaRenderer:1',
  'ssdp:all',
];

const probeMulticastAddress = '239.255.255.250';
const probeSsdpPort = 1900;

/// Kept identical to `ssdpMSearch` in lib/services/ssdp.dart.
String probeMSearch(String searchTarget, {int mx = 2}) =>
    'M-SEARCH * HTTP/1.1\r\n'
    'HOST: $probeMulticastAddress:$probeSsdpPort\r\n'
    'MAN: "ssdp:discover"\r\n'
    'MX: $mx\r\n'
    'ST: $searchTarget\r\n\r\n';

/// The control port each vendor listens on, mirroring `kDefaultPorts`.
const probeControlPorts = {
  8060: 'Roku ECP',
  8001: 'Samsung (legacy ws)',
  8002: 'Samsung (wss)',
  3000: 'LG webOS',
  7345: 'Vizio SmartCast',
};

Future<void> main(List<String> args) async {
  final prefix = args.isNotEmpty ? args.first : await _localPrefix();
  if (prefix == null) {
    print('No IPv4 network interface. Nothing on a LAN is reachable.');
    exit(1);
  }

  await _ssdpSweep();
  final open = await _portSweep(prefix);
  for (final ip in open.where((h) => h.endsWith(':8060')).map(_hostOf)) {
    await _ecpCheck(ip);
  }
  _verdict(open);
  exit(0);
}

// ── 1. this machine ──────────────────────────────────────────────────────────

Future<String?> _localPrefix() async {
  _heading('This machine');
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
  );
  String? prefix;
  for (final nic in interfaces) {
    for (final address in nic.addresses) {
      final name = nic.name.toLowerCase();
      final isVirtual =
          name.contains('vethernet') ||
          name.contains('virtual') ||
          address.address.startsWith('172.');
      print(
        '  ${nic.name}: ${address.address}${isVirtual ? "  (virtual)" : ""}',
      );
      if (!isVirtual) {
        prefix ??= address.address.split('.').take(3).join('.');
      }
    }
  }
  if (prefix != null) {
    print('');
    print('  Testing $prefix.0/24. The TV must be on this subnet; if it is on');
    print('  a guest SSID or a separate IoT band, it is a different network');
    print('  however similar the name looks.');
  }
  return prefix;
}

// ── 2. SSDP ──────────────────────────────────────────────────────────────────

Future<void> _ssdpSweep() async {
  _heading('SSDP discovery (the request the app sends)');

  final RawDatagramSocket socket;
  try {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  } catch (e) {
    print('  Could not bind a UDP socket: $e');
    return;
  }
  socket.broadcastEnabled = true;

  final byHost = <String, String>{};
  socket.listen((event) {
    if (event != RawSocketEvent.read) return;
    final datagram = socket.receive();
    if (datagram == null) return;
    try {
      byHost.putIfAbsent(
        datagram.address.address,
        () => utf8.decode(datagram.data),
      );
    } on FormatException {
      // A malformed datagram from any host must not stop the sweep.
    }
  });

  final multicast = InternetAddress(probeMulticastAddress);
  for (var round = 0; round < 3; round++) {
    for (final target in probeSearchTargets) {
      socket.send(utf8.encode(probeMSearch(target)), multicast, probeSsdpPort);
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  print(
    '  Sent ${probeSearchTargets.length * 3} M-SEARCH requests, listening 5s...',
  );
  await Future<void>.delayed(const Duration(seconds: 5));
  socket.close();

  if (byHost.isEmpty) {
    print('');
    print('  Nothing answered.');
    print('  On Windows this is often the host firewall rather than the');
    print('  network: replies arrive from <tv>:1900 while the request went to');
    print('  239.255.255.250:1900, and a stateful filter does not match those');
    print('  as one flow. The TCP sweep below is not subject to that.');
    return;
  }

  print('  ${byHost.length} responder(s):');
  for (final entry in byHost.entries) {
    print('');
    print('  ${entry.key}');
    for (final line in entry.value.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trim();
      final upper = trimmed.toUpperCase();
      if (upper.startsWith('SERVER') ||
          upper.startsWith('LOCATION') ||
          upper.startsWith('USN') ||
          upper.startsWith('ST:')) {
        print('    $trimmed');
      }
    }
  }
}

// ── 3. TCP ───────────────────────────────────────────────────────────────────

Future<List<String>> _portSweep(String prefix) async {
  _heading('Control ports on $prefix.0/24');
  print('  Scanning ${probeControlPorts.keys.join(", ")} on 254 hosts...');

  final open = <String>[];
  // Batched so the OS is not asked for 1270 sockets at once.
  for (var base = 1; base <= 254; base += 32) {
    final batch = <Future<void>>[];
    for (var host = base; host < base + 32 && host <= 254; host++) {
      for (final port in probeControlPorts.keys) {
        batch.add(_probePort('$prefix.$host', port, open));
      }
    }
    await Future.wait(batch);
  }

  open.sort();
  if (open.isEmpty) {
    print('');
    print('  No control port is open on any host in this subnet.');
  } else {
    print('');
    for (final hit in open) {
      final port = int.parse(hit.split(':').last);
      print('  OPEN $hit  ${probeControlPorts[port]}');
    }
  }
  return open;
}

Future<void> _probePort(String ip, int port, List<String> open) async {
  try {
    final socket = await Socket.connect(
      ip,
      port,
      timeout: const Duration(milliseconds: 900),
    );
    socket.destroy();
    open.add('$ip:$port');
  } catch (_) {
    // Closed, filtered or no such host: all the same answer here.
  }
}

String _hostOf(String hostPort) => hostPort.split(':').first;

// ── 4. Roku ECP ──────────────────────────────────────────────────────────────

Future<void> _ecpCheck(String ip) async {
  _heading('Roku ECP: $ip:8060');
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    // Exactly what RokuController.connect() issues.
    print('  GET http://$ip:8060/query/device-info');
    final request = await client.getUrl(
      Uri.parse('http://$ip:8060/query/device-info'),
    );
    final response = await request.close().timeout(const Duration(seconds: 3));
    final body = await response.transform(utf8.decoder).join();
    print('  -> HTTP ${response.statusCode}, ${body.length} bytes');

    if (response.statusCode != 200) {
      print('  RokuController.connect() throws on any status but 200.');
      print('  403 here means the TV is refusing external control: check');
      print('  Settings > System > Advanced system settings >');
      print('  Control by mobile apps > Network access.');
      return;
    }

    for (final tag in [
      'friendly-device-name',
      'model-name',
      'serial-number',
      'power-mode',
    ]) {
      final match = RegExp('<$tag>(.*?)</$tag>').firstMatch(body);
      if (match != null) print('     $tag: ${match.group(1)}');
    }
    print('');
    print('  This device would connect. Use Manual IP in the app if it does');
    print('  not appear in the list.');
  } on TimeoutException {
    print('  -> timed out; the port opened but ECP did not answer.');
  } catch (e) {
    print('  -> failed: $e');
  } finally {
    client.close(force: true);
  }
}

// ── verdict ──────────────────────────────────────────────────────────────────

void _verdict(List<String> open) {
  _heading('Verdict');
  if (open.isEmpty) {
    print('  No controllable device is reachable from this machine.');
    print('');
    print(
      '  This is a network fact, not an app fault. In order of likelihood:',
    );
    print('   1. The TV is on a different network - a guest SSID, or a');
    print('      separate 2.4GHz IoT band that the router keeps isolated.');
    print('   2. Client isolation / AP isolation is on, so devices on the');
    print('      same Wi-Fi cannot address each other at all.');
    print('   3. The TV is powered off, or on Ethernet in a different subnet.');
    print('');
    print('  Check it from the TV: Roku shows its address under');
    print('  Settings > Network > About. If that address is not on the subnet');
    print('  scanned above, nothing in the app can bridge the gap.');
  } else {
    print('  ${open.length} control port(s) reachable. The network is fine,');
    print('  so any failure to connect is in the app or on the device, and');
    print('  the detail above says which.');
  }
}

void _heading(String title) {
  print('');
  print('=== $title ${"=" * (58 - title.length).clamp(0, 58)}');
}
