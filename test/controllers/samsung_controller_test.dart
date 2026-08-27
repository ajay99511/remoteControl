import 'dart:async';
import 'dart:convert';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:devicecontroller/controllers/controller_health.dart';
import 'package:devicecontroller/core/certificate_pinning.dart';
import 'package:devicecontroller/controllers/samsung_controller.dart';
import 'package:devicecontroller/exceptions/certificate_pin_mismatch_exception.dart';
import 'package:devicecontroller/models/remote_key.dart';
import 'package:devicecontroller/services/device_persistence_service.dart';

import 'samsung_controller_test.mocks.dart';

@GenerateMocks([DevicePersistenceService, WebSocketChannel, WebSocketSink])
void main() {
  late MockDevicePersistenceService mockPersistence;
  late MockWebSocketChannel mockChannel;
  late MockWebSocketSink mockSink;
  late SamsungController controller;
  const host = '192.168.1.105';

  setUp(() {
    mockPersistence = MockDevicePersistenceService();
    mockChannel = MockWebSocketChannel();
    mockSink = MockWebSocketSink();

    when(mockChannel.sink).thenReturn(mockSink);
    when(
      mockChannel.stream,
    ).thenAnswer((_) => StreamController<dynamic>().stream);
    when(mockSink.close(any, any)).thenAnswer((_) async => null);

    controller = SamsungController(
      host: host,
      persistence: mockPersistence,
      channelFactory: (_) => mockChannel,
    );
  });

  group('verifyFingerprint (TOFU decision)', () {
    const fingerprint = 'aa:bb:cc';

    test('pins on first contact when nothing is stored', () {
      expect(
        verifyFingerprint(stored: null, presented: fingerprint),
        CertificateVerdict.pinNew,
      );
    });

    test('trusts a certificate matching the stored pin', () {
      expect(
        verifyFingerprint(stored: fingerprint, presented: fingerprint),
        CertificateVerdict.trusted,
      );
    });

    test('rejects a certificate contradicting the stored pin', () {
      expect(
        verifyFingerprint(stored: fingerprint, presented: 'dd:ee:ff'),
        CertificateVerdict.rejected,
      );
    });
  });

  group('CertificatePinMismatchException', () {
    test('carries the host and a message that does not leak internals', () {
      const e = CertificatePinMismatchException('192.168.1.5');
      expect(e.host, '192.168.1.5');
      expect(e.message, contains('security certificate'));
      expect(e.message, isNot(contains('sha256')));
    });
  });

  group('SamsungController', () {
    test('connect() persists pairing token from stream', () async {
      final controllerStream = StreamController<dynamic>();
      when(mockChannel.stream).thenAnswer((_) => controllerStream.stream);
      when(mockPersistence.loadSamsungToken(any)).thenAnswer((_) async => null);
      when(
        mockPersistence.loadCertFingerprint(any),
      ).thenAnswer((_) async => null);

      await controller.connect();

      final connectMessage = jsonEncode({
        'event': 'ms.channel.connect',
        'data': {'token': '12345'},
      });
      controllerStream.add(connectMessage);

      await Future.delayed(const Duration(milliseconds: 100));
      verify(mockPersistence.saveSamsungToken(host, '12345')).called(1);

      await controllerStream.close();
    });

    test('sendKey(RemoteKey.mute) sends KEY_MUTE payload', () async {
      when(
        mockPersistence.loadSamsungToken(any),
      ).thenAnswer((_) async => 'token');
      await controller.connect();

      await controller.sendKey(RemoteKey.mute);

      final captured =
          verify(mockSink.add(captureAny)).captured.first as String;
      final payload = jsonDecode(captured) as Map<String, dynamic>;
      final params = payload['params'] as Map<String, dynamic>;
      expect(payload['method'], 'ms.remote.control');
      expect(params['DataOfCmd'], 'KEY_MUTE');
    });

    test('sendText truncates to 500 chars', () async {
      when(
        mockPersistence.loadSamsungToken(any),
      ).thenAnswer((_) async => 'token');
      await controller.connect();

      final longText = 'x' * 600;
      await controller.sendText(longText);

      final captured =
          verify(mockSink.add(captureAny)).captured.first as String;
      final payload = jsonDecode(captured) as Map<String, dynamic>;
      final params = payload['params'] as Map<String, dynamic>;
      final decodedCmd = utf8.decode(base64Decode(params['Cmd'] as String));
      expect(decodedCmd.length, 500);
    });

    test('heartbeat sends ping every 30s', () async {
      fakeAsync((async) {
        when(
          mockPersistence.loadSamsungToken(any),
        ).thenAnswer((_) async => 'token');
        controller.connect();
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 31));
        verify(mockSink.add('ping')).called(1);
      });
    });

    test('pong timeout triggers disconnect after 5s', () async {
      fakeAsync((async) {
        when(
          mockPersistence.loadSamsungToken(any),
        ).thenAnswer((_) async => 'token');
        controller.connect();
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 30));
        verify(mockSink.add('ping')).called(1);

        // No pong received, wait 5 more seconds
        async.elapse(const Duration(seconds: 5));
        expect(controller.isConnected, isFalse);
      });
    });

    test('inbound pong cancels the disconnect deadline', () {
      fakeAsync((async) {
        final inbound = StreamController<dynamic>();
        when(mockChannel.stream).thenAnswer((_) => inbound.stream);
        when(
          mockPersistence.loadSamsungToken(any),
        ).thenAnswer((_) async => 'token');

        controller.connect();
        async.flushMicrotasks();

        // Heartbeat fires at 30s and arms a 5s pong deadline.
        async.elapse(const Duration(seconds: 30));
        verify(mockSink.add('ping')).called(1);

        // The TV answers. This must cancel the deadline.
        inbound.add('pong');
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 10));

        expect(
          controller.isConnected,
          isTrue,
          reason: 'a pong reply must cancel the disconnect deadline',
        );
        inbound.close();
      });
    });

    test('holds a session for 10 minutes while the TV answers', () {
      fakeAsync((async) {
        final inbound = StreamController<dynamic>();
        when(mockChannel.stream).thenAnswer((_) => inbound.stream);
        when(
          mockPersistence.loadSamsungToken(any),
        ).thenAnswer((_) async => 'token');

        controller.connect();
        async.flushMicrotasks();

        // Phase 1 exit gate, virtual-clock form: 20 heartbeat cycles. Before
        // the C-1 fix the session died on the first one, at T+35s.
        for (var minute = 0; minute < 20; minute++) {
          async.elapse(const Duration(seconds: 30));
          inbound.add('pong');
          async.flushMicrotasks();
          expect(
            controller.isConnected,
            isTrue,
            reason: 'session dropped during heartbeat cycle $minute',
          );
        }

        verify(mockSink.add('ping')).called(20);
        inbound.close();
      });
    });

    test('announces an unrequested disconnect on the health stream', () {
      fakeAsync((async) {
        final inbound = StreamController<dynamic>();
        when(mockChannel.stream).thenAnswer((_) => inbound.stream);
        when(
          mockPersistence.loadSamsungToken(any),
        ).thenAnswer((_) async => 'token');

        controller.connect();
        async.flushMicrotasks();

        final events = <ControllerHealth>[];
        controller.health.listen(events.add);
        async.flushMicrotasks();

        // Nobody asked to disconnect; the heartbeat deadline fires.
        async.elapse(const Duration(seconds: 36));
        async.flushMicrotasks();

        expect(
          events,
          contains(ControllerHealth.disconnected),
          reason: 'a session the app did not end must still be announced',
        );
        inbound.close();
      });
    });

    test('a non-JSON frame does not tear down the stream', () {
      fakeAsync((async) {
        final inbound = StreamController<dynamic>();
        when(mockChannel.stream).thenAnswer((_) => inbound.stream);
        when(
          mockPersistence.loadSamsungToken(any),
        ).thenAnswer((_) async => 'token');

        controller.connect();
        async.flushMicrotasks();

        // Some Tizen revisions emit bare text frames. Decoding must not throw
        // out of the listener.
        inbound.add('not json at all');
        async.flushMicrotasks();

        expect(controller.isConnected, isTrue);
        inbound.close();
      });
    });
  });
}
