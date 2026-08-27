import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:devicecontroller/controllers/vizio_controller.dart';
import 'package:devicecontroller/exceptions/pairing_required_exception.dart';
import 'package:devicecontroller/models/command_result.dart';
import 'package:devicecontroller/models/remote_key.dart';
import 'package:devicecontroller/services/device_persistence_service.dart';

import 'vizio_controller_test.mocks.dart';

@GenerateMocks([http.Client, DevicePersistenceService])
void main() {
  late MockClient mockClient;
  late MockDevicePersistenceService mockPersistence;
  late VizioController controller;
  const host = '192.168.1.140';

  setUp(() {
    mockClient = MockClient();
    mockPersistence = MockDevicePersistenceService();
    when(mockPersistence.loadVizioToken(any)).thenAnswer((_) async => null);

    controller = VizioController(
      host: host,
      client: mockClient,
      persistence: mockPersistence,
    );
  });

  group('VizioController.connect', () {
    test('connects when the TV accepts the request', () async {
      when(
        mockClient.get(any, headers: anyNamed('headers')),
      ).thenAnswer((_) async => http.Response('{}', 200));

      await controller.connect();

      expect(controller.isConnected, isTrue);
    });

    test('treats 401 as a pairing requirement, not a connection', () async {
      when(
        mockClient.get(any, headers: anyNamed('headers')),
      ).thenAnswer((_) async => http.Response('', 401));

      await expectLater(
        controller.connect(),
        throwsA(isA<PairingRequiredException>()),
      );
      expect(
        controller.isConnected,
        isFalse,
        reason: 'an unauthenticated session must never report as connected',
      );
    });

    test('treats 403 as a pairing requirement too', () async {
      when(
        mockClient.get(any, headers: anyNamed('headers')),
      ).thenAnswer((_) async => http.Response('', 403));

      await expectLater(
        controller.connect(),
        throwsA(isA<PairingRequiredException>()),
      );
    });

    test('sends the stored auth token when one exists', () async {
      when(
        mockPersistence.loadVizioToken(host),
      ).thenAnswer((_) async => 'stored-token');
      when(
        mockClient.get(any, headers: anyNamed('headers')),
      ).thenAnswer((_) async => http.Response('{}', 200));

      await controller.connect();

      final headers =
          verify(
                mockClient.get(any, headers: captureAnyNamed('headers')),
              ).captured.single
              as Map<String, String>;
      expect(headers['AUTH'], 'stored-token');
    });

    test('surfaces an unexpected status rather than guessing', () async {
      when(
        mockClient.get(any, headers: anyNamed('headers')),
      ).thenAnswer((_) async => http.Response('', 500));

      await expectLater(controller.connect(), throwsA(isA<Exception>()));
      expect(controller.isConnected, isFalse);
    });
  });

  group('VizioController commands', () {
    test('reports not-connected instead of returning silently', () async {
      final result = await controller.sendKey(RemoteKey.volumeUp);

      expect(result, isA<CommandNotConnected>());
      verifyNever(
        mockClient.put(
          any,
          headers: anyNamed('headers'),
          body: anyNamed('body'),
        ),
      );
    });

    test('reports text entry as unsupported on this API', () async {
      // SmartCast exposes no text endpoint. This previously logged at debug
      // and returned, which the caller could not distinguish from success.
      expect(await controller.sendText('search'), isA<CommandUnsupported>());
    });

    test('reports an unmapped key as unsupported once connected', () async {
      when(
        mockClient.get(any, headers: anyNamed('headers')),
      ).thenAnswer((_) async => http.Response('{}', 200));
      await controller.connect();

      expect(
        await controller.sendKey(RemoteKey.sleep),
        isA<CommandUnsupported>(),
      );
    });
  });
}
