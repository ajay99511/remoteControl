import 'package:flutter_test/flutter_test.dart';

import 'package:devicecontroller/controllers/ir_controller.dart';
import 'package:devicecontroller/exceptions/unsupported_device_exception.dart';
import 'package:devicecontroller/models/remote_key.dart';

void main() {
  group('IrController', () {
    test('connect() refuses instead of claiming a transmitter it lacks', () {
      final controller = IrController(brand: 'samsung');

      // There is no MethodChannel and no ConsumerIrManager binding, so
      // reporting success here produced a "CONNECTED" remote that silently
      // transmitted nothing.
      expect(
        controller.connect(),
        throwsA(isA<UnsupportedDeviceException>()),
      );
    });

    test('is never reported as connected', () async {
      final controller = IrController(brand: 'lg');

      await controller.connect().catchError((_) {});

      expect(controller.isConnected, isFalse);
    });

    test('sendKey is a no-op while unconnected', () async {
      final controller = IrController(brand: 'samsung');

      // Must not throw: the command path treats an unconnected controller as
      // a dropped command, not a crash.
      await expectLater(controller.sendKey(RemoteKey.power), completes);
    });
  });
}
