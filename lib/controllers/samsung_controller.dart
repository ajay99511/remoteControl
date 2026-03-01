import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/remote_key.dart';
import 'device_controller.dart';

/// Concrete [DeviceController] for Samsung Smart TVs (Tizen).
///
/// Communicates with the TV using a WebSocket connection on port 8001/8002.
/// First connection attempt will typically prompt the user to allow the
/// remote control on the TV screen.
class SamsungController implements DeviceController {
  final String host;
  final int port;
  WebSocketChannel? _channel;
  bool _connected = false;

  SamsungController({required this.host, this.port = 8001});

  static const Map<RemoteKey, String> _keyMap = {
    RemoteKey.up: 'KEY_UP',
    RemoteKey.down: 'KEY_DOWN',
    RemoteKey.left: 'KEY_LEFT',
    RemoteKey.right: 'KEY_RIGHT',
    RemoteKey.select: 'KEY_ENTER',
    RemoteKey.back: 'KEY_RETURN',
    RemoteKey.home: 'KEY_HOME',
    RemoteKey.playPause:
        'KEY_PLAY', // Some TVs use KEY_PLAY/KEY_PAUSE separately
    RemoteKey.volumeUp: 'KEY_VOLUP',
    RemoteKey.volumeDown: 'KEY_VOLDOWN',
    RemoteKey.mute: 'KEY_MUTE',
    RemoteKey.power: 'KEY_POWER',
    RemoteKey.rewind: 'KEY_REWIND',
    RemoteKey.fastForward: 'KEY_FF',
  };

  @override
  Future<void> connect() async {
    try {
      final nameBase64 = base64Encode(utf8.encode('FlutterRemote'));

      try {
        // Attempt 1: Modern WSS on port 8002 (Tizen 2016+)
        final wssUrl = Uri.parse(
          'wss://$host:8002/api/v2/channels/samsung.remote.control?name=$nameBase64',
        );
        final httpClient = HttpClient()
          ..badCertificateCallback =
              ((X509Certificate cert, String certHost, int certPort) => true);

        final socket = await WebSocket.connect(
          wssUrl.toString(),
          customClient: httpClient,
        ).timeout(const Duration(seconds: 3));
        _channel = IOWebSocketChannel(socket);
        _connected = true;
        debugPrint('SamsungController: Connected to $host:8002 via wss');
        return;
      } catch (e) {
        debugPrint(
          'SamsungController: wss://8002 failed ($e), falling back to ws://8001',
        );
      }

      // Attempt 2: Legacy WS on port 8001
      final wsUrl = Uri.parse(
        'ws://$host:8001/api/v2/channels/samsung.remote.control?name=$nameBase64',
      );
      _channel = WebSocketChannel.connect(wsUrl);
      await _channel!.ready.timeout(const Duration(seconds: 4));

      _connected = true;
      debugPrint('SamsungController: Connected to $host:8001 via ws');
    } catch (e) {
      _connected = false;
      throw Exception('Samsung TV not reachable at $host — $e');
    }
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    if (_channel != null) {
      await _channel!.sink.close();
      _channel = null;
    }
    debugPrint('SamsungController: Disconnected from $host:$port');
  }

  @override
  bool get isConnected => _connected;

  @override
  Future<void> sendKey(RemoteKey key) async {
    if (!_connected || _channel == null) return;

    final samsungKey = _keyMap[key] ?? key.name;
    final payload = {
      "method": "ms.remote.control",
      "params": {
        "Cmd": "Click",
        "DataOfCmd": samsungKey,
        "Option": "false",
        "TypeOfRemote": "SendRemoteKey",
      },
    };

    try {
      _channel!.sink.add(jsonEncode(payload));
    } catch (e) {
      debugPrint('SamsungController: Failed to send key $samsungKey — $e');
    }
  }

  @override
  Future<void> sendText(String text) async {
    // Currently Samsung text input is handled differently or not fully supported
    // via this exact REST API without a specific input focus.
    debugPrint(
      'SamsungController: Text input not fully supported yet ($text).',
    );
  }
}
