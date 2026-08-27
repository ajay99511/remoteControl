import 'package:flutter_test/flutter_test.dart';

import 'package:devicecontroller/models/device.dart';
import 'package:devicecontroller/providers/scanner_provider.dart';

void main() {
  const anError = ScannerState(error: 'Discovery failed: no multicast');

  group('ScannerState.copyWith', () {
    test('preserves an existing error when an unrelated field changes', () {
      // startScan sets an error, then the 10s deadline calls
      // copyWith(isScanning: false) - which used to wipe it, so the banner
      // vanished on its own seconds after appearing.
      final next = anError.copyWith(isScanning: false);

      expect(next.error, anError.error);
      expect(next.isScanning, isFalse);
    });

    test('preserves an existing error when a device is discovered', () {
      final next = anError.copyWith(
        devices: [
          const Device(
            id: '1',
            name: 'Roku',
            type: DeviceType.roku,
            model: 'x',
          ),
        ],
      );

      expect(next.error, anError.error);
      expect(next.devices, hasLength(1));
    });

    test('clears the error only when asked to', () {
      final next = anError.copyWith(clearError: true);

      expect(next.error, isNull);
    });

    test('replaces the error when a new one is supplied', () {
      final next = anError.copyWith(error: 'Permission denied');

      expect(next.error, 'Permission denied');
    });

    test('leaves untouched fields alone', () {
      const start = ScannerState(isScanning: true, error: 'boom');

      expect(start.copyWith().isScanning, isTrue);
      expect(start.copyWith().error, 'boom');
    });
  });
}
