import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:devicecontroller/models/device.dart';
import 'package:devicecontroller/services/device_persistence_service.dart';

import 'device_persistence_service_test.mocks.dart';

/// Covers the app's auth-equivalent surface: pairing tokens, client keys and
/// certificate pins. The audit flagged this file at 17% coverage - untested
/// code handling credentials is a defect regardless of the percentage.
@GenerateMocks([FlutterSecureStorage])
void main() {
  late MockFlutterSecureStorage storage;
  late DevicePersistenceService service;

  const device = Device(
    id: '192.168.1.50:8060',
    name: 'Living Room Roku',
    type: DeviceType.roku,
    model: 'Ultra',
    ip: '192.168.1.50',
    port: 8060,
  );

  setUp(() {
    storage = MockFlutterSecureStorage();
    service = DevicePersistenceService(storage: storage);
    when(
      storage.write(key: anyNamed('key'), value: anyNamed('value')),
    ).thenAnswer((_) async {});
    when(storage.delete(key: anyNamed('key'))).thenAnswer((_) async {});
  });

  group('device persistence', () {
    test('writes the device as JSON under a versioned key', () async {
      await service.saveDevice(device);

      final key = verify(
        storage.write(
          key: captureAnyNamed('key'),
          value: captureAnyNamed('value'),
        ),
      ).captured;
      expect(key[0], 'last_device_v1');
      expect(
        jsonDecode(key[1] as String),
        containsPair('id', '192.168.1.50:8060'),
      );
    });

    test('restores a saved device', () async {
      when(
        storage.read(key: 'last_device_v1'),
      ).thenAnswer((_) async => jsonEncode(device.toJson()));

      expect(await service.loadDevice(), device);
    });

    test('returns null when nothing was saved', () async {
      when(storage.read(key: anyNamed('key'))).thenAnswer((_) async => null);

      expect(await service.loadDevice(), isNull);
    });

    test('returns null rather than throwing on a corrupt blob', () async {
      when(
        storage.read(key: anyNamed('key')),
      ).thenAnswer((_) async => 'not json');

      expect(await service.loadDevice(), isNull);
    });

    test('returns null on JSON that is valid but not a device', () async {
      when(
        storage.read(key: anyNamed('key')),
      ).thenAnswer((_) async => jsonEncode({'unexpected': true}));

      expect(await service.loadDevice(), isNull);
    });

    test('clearDevice removes the entry', () async {
      await service.clearDevice();

      verify(storage.delete(key: 'last_device_v1')).called(1);
    });
  });

  group('per-host credentials', () {
    test('namespaces each secret by host so two TVs cannot collide', () async {
      await service.saveSamsungToken('10.0.0.1', 'token-a');
      await service.saveSamsungToken('10.0.0.2', 'token-b');

      verify(
        storage.write(key: 'samsung_token_10.0.0.1', value: 'token-a'),
      ).called(1);
      verify(
        storage.write(key: 'samsung_token_10.0.0.2', value: 'token-b'),
      ).called(1);
    });

    test('stores and reads a certificate fingerprint', () async {
      await service.saveCertFingerprint('10.0.0.1', 'sha-a');
      verify(
        storage.write(key: 'tofu_cert_10.0.0.1', value: 'sha-a'),
      ).called(1);

      when(
        storage.read(key: 'tofu_cert_10.0.0.1'),
      ).thenAnswer((_) async => 'sha-a');
      expect(await service.loadCertFingerprint('10.0.0.1'), 'sha-a');
    });

    test('clearing one pin does not touch another host', () async {
      await service.clearCertFingerprint('10.0.0.1');

      verify(storage.delete(key: 'tofu_cert_10.0.0.1')).called(1);
      verifyNever(storage.delete(key: 'tofu_cert_10.0.0.2'));
    });

    test('stores and reads an LG client key', () async {
      await service.saveLgClientKey('10.0.0.3', 'client-key');
      verify(
        storage.write(key: 'lg_client_key_10.0.0.3', value: 'client-key'),
      ).called(1);

      when(
        storage.read(key: 'lg_client_key_10.0.0.3'),
      ).thenAnswer((_) async => 'client-key');
      expect(await service.loadLgClientKey('10.0.0.3'), 'client-key');
    });

    test('stores and reads a Vizio auth token', () async {
      await service.saveVizioToken('10.0.0.4', 'vizio-token');
      verify(
        storage.write(key: 'vizio_token_10.0.0.4', value: 'vizio-token'),
      ).called(1);

      when(
        storage.read(key: 'vizio_token_10.0.0.4'),
      ).thenAnswer((_) async => 'vizio-token');
      expect(await service.loadVizioToken('10.0.0.4'), 'vizio-token');
    });

    test('an unknown host has no stored secret', () async {
      when(storage.read(key: anyNamed('key'))).thenAnswer((_) async => null);

      expect(await service.loadSamsungToken('10.9.9.9'), isNull);
      expect(await service.loadCertFingerprint('10.9.9.9'), isNull);
    });
  });
}
