import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devicecontroller/services/connectivity_service.dart';

void main() {
  group('canReachLocalNetwork', () {
    test('wifi and ethernet can reach a device on the LAN', () {
      expect(canReachLocalNetwork([ConnectivityResult.wifi]), isTrue);
      expect(canReachLocalNetwork([ConnectivityResult.ethernet]), isTrue);
    });

    test('cellular cannot', () {
      // Every controller talks to a private address. Mobile data is not
      // `none`, so a "not none" check treated this as reachable.
      expect(canReachLocalNetwork([ConnectivityResult.mobile]), isFalse);
    });

    test('vpn alone cannot', () {
      expect(canReachLocalNetwork([ConnectivityResult.vpn]), isFalse);
    });

    test('none cannot', () {
      expect(canReachLocalNetwork([ConnectivityResult.none]), isFalse);
      expect(canReachLocalNetwork([]), isFalse);
    });

    test('wifi alongside another transport still counts', () {
      expect(
        canReachLocalNetwork([ConnectivityResult.vpn, ConnectivityResult.wifi]),
        isTrue,
      );
    });
  });
}
