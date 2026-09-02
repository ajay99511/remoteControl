import 'package:flutter_test/flutter_test.dart';

import 'package:devicecontroller/models/device.dart';
import 'package:devicecontroller/services/ssdp.dart';

import '../../tool/probe_network.dart';

/// The probe stands alone so it can run under the plain Dart VM, which means
/// it restates what the app sends instead of importing it. A diagnostic that
/// asks a different question from the app is worse than none: it would clear
/// a network the app cannot actually use, or condemn one it can.
void main() {
  group('tool/probe_network mirrors the app', () {
    test('asks for the same search targets', () {
      expect(probeSearchTargets, ssdpSearchTargets);
    });

    test('sends a byte-identical M-SEARCH', () {
      for (final target in ssdpSearchTargets) {
        expect(probeMSearch(target), ssdpMSearch(target));
      }
    });

    test('uses the same multicast endpoint', () {
      expect(probeMulticastAddress, ssdpMulticastAddress);
      expect(probeSsdpPort, ssdpPort);
    });

    test('scans every port a controller connects on', () {
      // A port missing here means the sweep reports "nothing reachable" for a
      // device the app could have driven.
      for (final port in kDefaultPorts.values) {
        expect(
          probeControlPorts.keys,
          contains(port),
          reason: 'kDefaultPorts has $port; the probe does not scan it',
        );
      }
      // Samsung's legacy plaintext port is not in kDefaultPorts (which names
      // 8001) but the controller falls back to it, so the probe checks both.
      expect(probeControlPorts.keys, contains(8002));
    });
  });
}
