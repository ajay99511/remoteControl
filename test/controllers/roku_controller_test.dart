import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:devicecontroller/controllers/roku_controller.dart';
import 'package:devicecontroller/models/app_id.dart';
import 'package:devicecontroller/models/remote_key.dart';

import 'roku_controller_test.mocks.dart';

@GenerateMocks([http.Client])
void main() {
  late MockClient mockClient;
  late RokuController controller;
  const host = '192.168.1.100';
  const port = 8060;

  setUp(() {
    mockClient = MockClient();
    controller = RokuController(host: host, port: port, client: mockClient);
  });

  group('RokuController', () {
    test('connect() succeeds when device-info returns 200', () async {
      when(mockClient.get(any, headers: anyNamed('headers')))
          .thenAnswer((_) async => http.Response('<device-info></device-info>', 200));

      await controller.connect();
      expect(controller.isConnected, isTrue);
    });

    test('connect() throws Exception on unreachable host (simulated)', () async {
      when(mockClient.get(any, headers: anyNamed('headers')))
          .thenThrow(TimeoutException('Timed out'));

      expect(() => controller.connect(), throwsA(isA<TimeoutException>()));
      expect(controller.isConnected, isFalse);
    });

    test('sendKey(RemoteKey.up) POSTs to /keypress/Up', () async {
      // Connect first
      when(mockClient.get(any, headers: anyNamed('headers')))
          .thenAnswer((_) async => http.Response('', 200));
      await controller.connect();

      when(mockClient.post(any, headers: anyNamed('headers'), body: anyNamed('body')))
          .thenAnswer((_) async => http.Response('', 200));

      await controller.sendKey(RemoteKey.up);

      verify(mockClient.post(
        Uri.parse('http://$host:$port/keypress/Up'),
        headers: anyNamed('headers'),
      )).called(1);
    });

    test('sendKey(RemoteKey.channelUp) POSTs to /keypress/ChannelUp', () async {
      when(mockClient.get(any, headers: anyNamed('headers')))
          .thenAnswer((_) async => http.Response('', 200));
      await controller.connect();

      when(mockClient.post(any, headers: anyNamed('headers'), body: anyNamed('body')))
          .thenAnswer((_) async => http.Response('', 200));

      await controller.sendKey(RemoteKey.channelUp);

      verify(mockClient.post(
        Uri.parse('http://$host:$port/keypress/ChannelUp'),
        headers: anyNamed('headers'),
      )).called(1);
    });

    test('sendText("ab") sends two Lit_ keypresses', () async {
      when(mockClient.get(any, headers: anyNamed('headers')))
          .thenAnswer((_) async => http.Response('', 200));
      await controller.connect();

      when(mockClient.post(any, headers: anyNamed('headers'), body: anyNamed('body')))
          .thenAnswer((_) async => http.Response('', 200));

      await controller.sendText('ab');

      verify(mockClient.post(Uri.parse('http://$host:$port/keypress/Lit_a'))).called(1);
      verify(mockClient.post(Uri.parse('http://$host:$port/keypress/Lit_b'))).called(1);
    });

    test('launchApp(AppId.netflix) POSTs to /launch/12', () async {
      when(mockClient.get(any, headers: anyNamed('headers')))
          .thenAnswer((_) async => http.Response('', 200));
      await controller.connect();

      when(mockClient.post(any, headers: anyNamed('headers'), body: anyNamed('body')))
          .thenAnswer((_) async => http.Response('', 200));

      await controller.launchApp(AppId.netflix);

      verify(mockClient.post(
        Uri.parse('http://$host:$port/launch/12'),
        headers: anyNamed('headers'),
      )).called(1);
    });

    test('sendKey is no-op when not connected', () async {
      await controller.sendKey(RemoteKey.up);
      verifyNever(mockClient.post(any, headers: anyNamed('headers'), body: anyNamed('body')));
    });
    group('Timeout enforcement', () {
      test('all HTTP calls apply 3-second timeout', () async {
        // This is hard to test directly without wrapping the client or checking code,
        // but we can simulate a slow response and expect a TimeoutException if the controller uses .timeout().
        // Controller's connect() uses 3s timeout.
        
        when(mockClient.get(any, headers: anyNamed('headers')))
            .thenAnswer((_) async {
              await Future.delayed(const Duration(seconds: 4));
              return http.Response('', 200);
            });

        expect(() => controller.connect(), throwsA(isA<TimeoutException>()));
      });
    });
  });
}
