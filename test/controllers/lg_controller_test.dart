import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:devicecontroller/controllers/controller_health.dart';
import 'package:devicecontroller/controllers/lg_controller.dart';
import 'package:devicecontroller/models/command_result.dart';
import 'package:devicecontroller/models/remote_key.dart';
import 'package:devicecontroller/services/device_persistence_service.dart';

import 'lg_controller_test.mocks.dart';

@GenerateMocks([DevicePersistenceService, WebSocketChannel, WebSocketSink])
void main() {
  late MockDevicePersistenceService mockPersistence;
  late MockWebSocketChannel mockChannel;
  late MockWebSocketSink mockSink;
  late LgController controller;
  const host = '192.168.1.120';

  /// Drives [LgController.connect] to the connected state inside [async],
  /// returning the stream the fake TV writes to.
  StreamController<dynamic> connectAndRegister(FakeAsync async) {
    final inbound = StreamController<dynamic>();
    when(mockChannel.stream).thenAnswer((_) => inbound.stream);
    when(mockPersistence.loadLgClientKey(any)).thenAnswer((_) async => null);

    controller.connect();
    async.flushMicrotasks();

    inbound.add(
      jsonEncode({
        'type': 'registered',
        'payload': {'client-key': 'client-key-1'},
      }),
    );
    async.flushMicrotasks();
    return inbound;
  }

  setUp(() {
    mockPersistence = MockDevicePersistenceService();
    mockChannel = MockWebSocketChannel();
    mockSink = MockWebSocketSink();

    when(mockChannel.sink).thenReturn(mockSink);
    when(
      mockChannel.stream,
    ).thenAnswer((_) => StreamController<dynamic>().stream);
    when(mockSink.close(any, any)).thenAnswer((_) async => null);

    controller = LgController(
      host: host,
      persistence: mockPersistence,
      channelFactory: (_) => mockChannel,
    );
  });

  group('SSAP permissions', () {
    test('cover every URI the controller can send', () {
      // webOS denies calls outside the granted set, so a URI with no covering
      // permission is a button that silently does nothing on real hardware.
      for (final uri in LgController.ssapUris) {
        final prefix = ssapUriPermissions.keys.firstWhere(
          uri.startsWith,
          orElse: () => '',
        );
        expect(prefix, isNotEmpty, reason: '$uri maps to no known permission');
        expect(
          ssapPermissions,
          contains(ssapUriPermissions[prefix]),
          reason:
              '$uri needs ${ssapUriPermissions[prefix]}, which is not '
              'requested at registration',
        );
      }
    });

    test('include the two that were missing', () {
      // RemoteKey.ok routes to ssap://com.webos.service.ime/sendEnterKey, so
      // without CONTROL_INPUT_TEXT a real TV denied the OK button.
      expect(ssapPermissions, contains('CONTROL_INPUT_TEXT'));
      expect(ssapPermissions, contains('CONTROL_INPUT_MEDIA_PLAYBACK'));
    });

    test('request nothing the controller does not use', () {
      // CHECK_3D was left over from the set3DOn/set3DOff mapping removed as
      // audit finding H-1; READ_INSTALLED_APPS was never read.
      expect(ssapPermissions, isNot(contains('CHECK_3D')));
      expect(ssapPermissions, isNot(contains('READ_INSTALLED_APPS')));

      final used = ssapUriPermissions.entries
          .where((e) => LgController.ssapUris.any((u) => u.startsWith(e.key)))
          .map((e) => e.value)
          .toSet();
      expect(ssapPermissions.toSet(), used);
    });

    test('the registration payload carries them', () {
      fakeAsync((async) {
        final inbound = connectAndRegister(async);

        final register = verify(mockSink.add(captureAny)).captured
            .whereType<String>()
            .map((f) => jsonDecode(f) as Map<String, dynamic>)
            .firstWhere((f) => f['type'] == 'register');
        final payload = register['payload'] as Map<String, dynamic>;
        final manifest = payload['manifest'] as Map<String, dynamic>;

        expect(manifest['permissions'], ssapPermissions);
        inbound.close();
      });
    });
  });

  group('LgController', () {
    test('registers and persists the client key returned by the TV', () {
      fakeAsync((async) {
        final inbound = connectAndRegister(async);

        expect(controller.isConnected, isTrue);
        verify(mockPersistence.saveLgClientKey(host, 'client-key-1')).called(1);
        inbound.close();
      });
    });

    test('inbound pong cancels the disconnect deadline', () {
      fakeAsync((async) {
        final inbound = connectAndRegister(async);

        // Heartbeat fires at 30s and arms a 5s pong deadline.
        async.elapse(const Duration(seconds: 30));
        verify(mockSink.add('ping')).called(1);

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
        final inbound = connectAndRegister(async);

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

    test('a non-JSON frame does not tear down the stream', () {
      fakeAsync((async) {
        final inbound = connectAndRegister(async);

        inbound.add('unparseable');
        async.flushMicrotasks();

        expect(controller.isConnected, isTrue);
        inbound.close();
      });
    });

    test('silence past the pong deadline disconnects', () {
      fakeAsync((async) {
        final inbound = connectAndRegister(async);

        async.elapse(const Duration(seconds: 30));
        verify(mockSink.add('ping')).called(1);

        // No reply from the TV.
        async.elapse(const Duration(seconds: 6));

        expect(controller.isConnected, isFalse);
        inbound.close();
      });
    });

    test('announces an unrequested disconnect on the health stream', () {
      fakeAsync((async) {
        final inbound = connectAndRegister(async);
        final events = <ControllerHealth>[];
        controller.health.listen(events.add);
        async.flushMicrotasks();

        // Nobody asked to disconnect; the heartbeat deadline fires.
        async.elapse(const Duration(seconds: 36));
        async.flushMicrotasks();

        expect(
          events,
          contains(ControllerHealth.disconnected),
          reason:
              'a session the app did not end must still be announced, or '
              'the UI goes on showing CONNECTED over a dead transport',
        );
        inbound.close();
      });
    });

    test('does not announce a disconnect it never connected from', () {
      fakeAsync((async) {
        final events = <ControllerHealth>[];
        controller.health.listen(events.add);
        async.flushMicrotasks();

        controller.disconnect();
        async.flushMicrotasks();

        expect(events, isEmpty);
      });
    });

    test('D-pad keys emit nothing rather than toggling 3D mode', () {
      fakeAsync((async) {
        final inbound = connectAndRegister(async);

        final results = <CommandResult>[];
        for (final key in [
          RemoteKey.up,
          RemoteKey.down,
          RemoteKey.left,
          RemoteKey.right,
        ]) {
          controller.sendKey(key).then(results.add);
        }
        async.flushMicrotasks();

        expect(results, hasLength(4));
        expect(
          results,
          everyElement(isA<CommandUnsupported>()),
          reason: 'the UI must be told, not left to assume success',
        );

        final frames = verify(
          mockSink.add(captureAny),
        ).captured.whereType<String>().join('\n');
        expect(
          frames,
          isNot(contains('set3D')),
          reason:
              'up/down were wired to the TV 3D toggle, which is not '
              'navigation and is hard for a user to undo',
        );
        expect(frames, isNot(contains('"type":"request"')));
        inbound.close();
      });
    });

    test('sendKey(volumeUp) emits the ssap://audio/volumeUp request', () {
      fakeAsync((async) {
        final inbound = connectAndRegister(async);

        controller.sendKey(RemoteKey.volumeUp);
        async.flushMicrotasks();

        final frames = verify(mockSink.add(captureAny)).captured;
        final request = frames
            .whereType<String>()
            .map((f) => jsonDecode(f) as Map<String, dynamic>)
            .firstWhere((f) => f['type'] == 'request');
        expect(request['uri'], 'ssap://audio/volumeUp');
        inbound.close();
      });
    });
  });
}
