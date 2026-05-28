import 'dart:async';
import 'dart:convert';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:devicecontroller/controllers/samsung_controller.dart';
import 'package:devicecontroller/models/app_id.dart';
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
    when(mockChannel.stream).thenAnswer((_) => StreamController<dynamic>().stream);
    when(mockSink.close(any, any)).thenAnswer((_) async => null);
    
    controller = SamsungController(
      host: host,
      persistence: mockPersistence,
      channelFactory: (_) => mockChannel,
    );
  });

  group('SamsungController', () {
    test('connect() persists pairing token from stream', () async {
      final controllerStream = StreamController<dynamic>();
      when(mockChannel.stream).thenAnswer((_) => controllerStream.stream);
      when(mockPersistence.loadSamsungToken(any)).thenAnswer((_) async => null);
      when(mockPersistence.loadCertFingerprint(any)).thenAnswer((_) async => null);

      await controller.connect();
      
      final connectMessage = jsonEncode({
        'event': 'ms.channel.connect',
        'data': {'token': '12345'}
      });
      controllerStream.add(connectMessage);

      await Future.delayed(const Duration(milliseconds: 100));
      verify(mockPersistence.saveSamsungToken(host, '12345')).called(1);
      
      await controllerStream.close();
    });

    test('sendKey(RemoteKey.mute) sends KEY_MUTE payload', () async {
      when(mockPersistence.loadSamsungToken(any)).thenAnswer((_) async => 'token');
      await controller.connect();

      await controller.sendKey(RemoteKey.mute);

      final captured = verify(mockSink.add(captureAny)).captured.first as String;
      final payload = jsonDecode(captured);
      expect(payload['method'], 'ms.remote.control');
      expect(payload['params']['DataOfCmd'], 'KEY_MUTE');
    });

    test('sendText truncates to 500 chars', () async {
      when(mockPersistence.loadSamsungToken(any)).thenAnswer((_) async => 'token');
      await controller.connect();

      final longText = 'x' * 600;
      await controller.sendText(longText);

      final captured = verify(mockSink.add(captureAny)).captured.first as String;
      final payload = jsonDecode(captured);
      final decodedCmd = utf8.decode(base64Decode(payload['params']['Cmd']));
      expect(decodedCmd.length, 500);
    });

    test('heartbeat sends ping every 30s', () async {
      fakeAsync((async) {
        when(mockPersistence.loadSamsungToken(any)).thenAnswer((_) async => 'token');
        controller.connect();
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 31));
        verify(mockSink.add('ping')).called(1);
      });
    });

    test('pong timeout triggers disconnect after 5s', () async {
      fakeAsync((async) {
        when(mockPersistence.loadSamsungToken(any)).thenAnswer((_) async => 'token');
        controller.connect();
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 30));
        verify(mockSink.add('ping')).called(1);
        
        // No pong received, wait 5 more seconds
        async.elapse(const Duration(seconds: 5));
        expect(controller.isConnected, isFalse);
      });
    });
  });
}
