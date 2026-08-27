import 'package:flutter_test/flutter_test.dart';

import 'package:devicecontroller/controllers/device_controller_factory.dart';
import 'package:devicecontroller/controllers/fire_tv_controller.dart';
import 'package:devicecontroller/controllers/google_tv_controller.dart';
import 'package:devicecontroller/controllers/ir_controller.dart';
import 'package:devicecontroller/controllers/lg_controller.dart';
import 'package:devicecontroller/controllers/roku_controller.dart';
import 'package:devicecontroller/controllers/samsung_controller.dart';
import 'package:devicecontroller/controllers/vizio_controller.dart';
import 'package:devicecontroller/exceptions/unsupported_device_exception.dart';
import 'package:devicecontroller/models/device.dart';

import 'vizio_controller_test.mocks.dart';

void main() {
  late MockDevicePersistenceService persistence;

  Device deviceOf(DeviceType type, {String? ip = '192.168.1.50', int? port}) =>
      Device(
        id: 'test',
        name: 'Test',
        type: type,
        model: 'samsung',
        ip: ip,
        port: port,
      );

  setUp(() => persistence = MockDevicePersistenceService());

  group('buildDeviceController', () {
    test('builds the transport matching the device type', () {
      expect(
        buildDeviceController(deviceOf(DeviceType.roku), persistence),
        isA<RokuController>(),
      );
      expect(
        buildDeviceController(deviceOf(DeviceType.samsung), persistence),
        isA<SamsungController>(),
      );
      expect(
        buildDeviceController(deviceOf(DeviceType.lg), persistence),
        isA<LgController>(),
      );
      expect(
        buildDeviceController(deviceOf(DeviceType.vizio), persistence),
        isA<VizioController>(),
      );
      expect(
        buildDeviceController(deviceOf(DeviceType.fireTv), persistence),
        isA<FireTvController>(),
      );
      expect(
        buildDeviceController(deviceOf(DeviceType.googleTv), persistence),
        isA<GoogleTvController>(),
      );
      expect(
        buildDeviceController(deviceOf(DeviceType.ir), persistence),
        isA<IrController>(),
      );
    });

    test('refuses a device type it has no transport for', () {
      expect(
        () => buildDeviceController(deviceOf(DeviceType.unknown), persistence),
        throwsA(isA<UnsupportedDeviceException>()),
      );
    });

    test('applies the vendor default port when none was discovered', () {
      final roku =
          buildDeviceController(deviceOf(DeviceType.roku), persistence)
              as RokuController;

      expect(roku.port, kDefaultPorts[DeviceType.roku]);
    });

    test('honours a port the device advertised', () {
      final roku =
          buildDeviceController(
                deviceOf(DeviceType.roku, port: 9999),
                persistence,
              )
              as RokuController;

      expect(roku.port, 9999);
    });

    group('missing address', () {
      // Device.ip is nullable and fromJson will happily produce a device
      // without one, so the previous `device.ip!` force-unwraps were a real
      // crash path on auto-reconnect from a malformed persisted blob.
      for (final type in [
        DeviceType.roku,
        DeviceType.samsung,
        DeviceType.lg,
        DeviceType.vizio,
      ]) {
        test('${type.name} reports it rather than crashing', () {
          expect(
            () => buildDeviceController(deviceOf(type, ip: null), persistence),
            throwsA(isA<ArgumentError>()),
          );
          expect(
            () => buildDeviceController(deviceOf(type, ip: ''), persistence),
            throwsA(isA<ArgumentError>()),
          );
        });
      }

      test('device types that need no address are unaffected', () {
        expect(
          buildDeviceController(
            deviceOf(DeviceType.fireTv, ip: null),
            persistence,
          ),
          isA<FireTvController>(),
        );
        expect(
          buildDeviceController(deviceOf(DeviceType.ir, ip: null), persistence),
          isA<IrController>(),
        );
      });
    });
  });
}
