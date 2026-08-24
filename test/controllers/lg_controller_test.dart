import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:devicecontroller/controllers/lg_controller.dart';
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

    inbound.add(jsonEncode({
      'type': 'registered',
      'payload': {'client-key': 'client-key-1'},
    }));
    async.flushMicrotasks();
    return inbound;
  }

  setUp(() {
    mockPersistence = MockDevicePersistenceService();
    mockChannel = MockWebSocketChannel();
    mockSink = MockWebSocketSink();

    when(mockChannel.sink).thenReturn(mockSink);
    when(mockChannel.stream)
        .thenAnswer((_) => StreamController<dynamic>().stream);
    when(mockSink.close(any, any)).thenAnswer((_) async => null);

    controller = LgController(
      host: host,
      persistence: mockPersistence,
      channelFactory: (_) => mockChannel,
    );
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
