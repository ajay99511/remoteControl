import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:devicecontroller/models/device.dart';

void main() {
  const roku = Device(
    id: '192.168.1.50:8060',
    name: 'Living Room Roku',
    type: DeviceType.roku,
    model: 'Ultra',
    ip: '192.168.1.50',
    port: 8060,
  );

  group('DeviceType.fromString', () {
    test('accepts the canonical names', () {
      expect(DeviceType.fromString('roku'), DeviceType.roku);
      expect(DeviceType.fromString('samsung'), DeviceType.samsung);
      expect(DeviceType.fromString('lg'), DeviceType.lg);
      expect(DeviceType.fromString('vizio'), DeviceType.vizio);
      expect(DeviceType.fromString('ir'), DeviceType.ir);
    });

    test('is case insensitive', () {
      expect(DeviceType.fromString('ROKU'), DeviceType.roku);
      expect(DeviceType.fromString('Samsung'), DeviceType.samsung);
    });

    test('accepts the spelling variants persisted by older builds', () {
      for (final spelling in ['firetv', 'fire_tv', 'fire tv']) {
        expect(DeviceType.fromString(spelling), DeviceType.fireTv);
      }
      for (final spelling in [
        'googletv',
        'google_tv',
        'google tv',
        'androidtv',
        'android tv',
      ]) {
        expect(DeviceType.fromString(spelling), DeviceType.googleTv);
      }
    });

    test('falls back to unknown rather than throwing', () {
      expect(DeviceType.fromString(''), DeviceType.unknown);
      expect(DeviceType.fromString('toaster'), DeviceType.unknown);
    });
  });

  group('Device serialisation', () {
    test('round-trips through JSON', () {
      final restored = Device.fromJson(
        jsonDecode(jsonEncode(roku.toJson())) as Map<String, dynamic>,
      );

      expect(restored, roku);
    });

    test('round-trips a device with no address', () {
      const headless = Device(
        id: 'x',
        name: 'Unknown',
        type: DeviceType.unknown,
        model: 'y',
      );

      final restored = Device.fromJson(
        jsonDecode(jsonEncode(headless.toJson())) as Map<String, dynamic>,
      );

      expect(restored, headless);
      expect(restored.ip, isNull);
      expect(restored.port, isNull);
    });

    test('tolerates a blob written before the type field existed', () {
      final restored = Device.fromJson({
        'id': 'x',
        'name': 'Old',
        'model': 'y',
        'ip': null,
        'port': null,
      });

      expect(restored.type, DeviceType.unknown);
    });

    test('tolerates the signal key dropped in Phase 1', () {
      // Blobs written by older builds still carry it; fromJson must ignore
      // the extra key rather than choke on it.
      final restored = Device.fromJson({
        'id': 'x',
        'name': 'Old',
        'type': 'roku',
        'model': 'y',
        'signal': 100,
        'ip': '10.0.0.1',
        'port': 8060,
      });

      expect(restored.type, DeviceType.roku);
      expect(restored.ip, '10.0.0.1');
    });
  });

  group('Device value semantics', () {
    test('equal devices are equal and hash alike', () {
      const same = Device(
        id: '192.168.1.50:8060',
        name: 'Living Room Roku',
        type: DeviceType.roku,
        model: 'Ultra',
        ip: '192.168.1.50',
        port: 8060,
      );

      expect(same, roku);
      expect(same.hashCode, roku.hashCode);
    });

    test('a differing field breaks equality', () {
      expect(roku.copyWith(port: 8061), isNot(roku));
      expect(roku.copyWith(name: 'Other'), isNot(roku));
    });

    test('copyWith leaves untouched fields alone', () {
      final renamed = roku.copyWith(name: 'Bedroom');

      expect(renamed.name, 'Bedroom');
      expect(renamed.ip, roku.ip);
      expect(renamed.port, roku.port);
      expect(renamed.type, roku.type);
    });

    test('toString names the device without dumping every field', () {
      expect(roku.toString(), contains('Living Room Roku'));
      expect(roku.toString(), contains('roku'));
    });
  });

  group('credentialKey', () {
    test('prefers the stable id so secrets follow the television', () {
      const withUid = Device(
        id: 'ssdp:abc',
        name: 'Roku',
        type: DeviceType.roku,
        model: 'Ultra',
        ip: '192.168.1.50',
        uid: 'ssdp:abc',
      );

      expect(withUid.credentialKey, 'ssdp:abc');
      // A DHCP renewal must not orphan the pairing token or the cert pin.
      expect(withUid.copyWith(ip: '192.168.1.77').credentialKey, 'ssdp:abc');
    });

    test('falls back to the address when there is no stable id', () {
      expect(roku.credentialKey, '192.168.1.50');
    });

    test('falls back to the id when there is no address either', () {
      const manual = Device(
        id: 'manual-1',
        name: 'Manual',
        type: DeviceType.roku,
        model: 'Custom IP',
      );

      expect(manual.credentialKey, 'manual-1');
    });
  });

  group('kDefaultPorts', () {
    test('covers every network-controllable vendor', () {
      expect(kDefaultPorts[DeviceType.roku], 8060);
      expect(kDefaultPorts[DeviceType.samsung], 8001);
      expect(kDefaultPorts[DeviceType.lg], 3000);
      expect(kDefaultPorts[DeviceType.vizio], 7345);
    });
  });

  group('DeviceType.isControllable', () {
    test('is true exactly for the vendors with a working transport', () {
      // The discovery screen lists whatever answers, including Chromecasts
      // that reply to _googlecast._tcp and AirPlay responders that name no
      // vendor at all. Offering those as tappable rows means the user picks
      // one, waits, and is told it failed - when nothing was ever going to
      // work.
      expect(DeviceType.roku.isControllable, isTrue);
      expect(DeviceType.samsung.isControllable, isTrue);
      expect(DeviceType.lg.isControllable, isTrue);
      expect(DeviceType.vizio.isControllable, isTrue);
    });

    test('is false for every type whose controller refuses to connect', () {
      // Each of these throws from connect(): the two stubs, the IR controller
      // with no platform channel, and an unrecognised responder.
      expect(DeviceType.fireTv.isControllable, isFalse);
      expect(DeviceType.googleTv.isControllable, isFalse);
      expect(DeviceType.ir.isControllable, isFalse);
      expect(DeviceType.unknown.isControllable, isFalse);
    });

    test('covers every enum value', () {
      // A new vendor must make a deliberate choice here rather than defaulting.
      for (final type in DeviceType.values) {
        expect(() => type.isControllable, returnsNormally);
      }
    });
  });
}
