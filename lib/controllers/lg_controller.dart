import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/app_logger.dart';
import '../models/app_id.dart';
import '../models/remote_key.dart';
import '../services/device_persistence_service.dart';
import 'device_controller.dart';

/// LG webOS TV controller via SSAP WebSocket on port 3000 (Requirement 2.4).
class LgController implements DeviceController {
  final String host;
  final int port;
  final DevicePersistenceService _persistence;

  WebSocketChannel? _channel;
  bool _connected = false;
  Timer? _heartbeatTimer;
  Timer? _pongTimeoutTimer;
  String? _clientKey;

  LgController({
    required this.host,
    this.port = 3000,
    required DevicePersistenceService persistence,
  }) : _persistence = persistence;

  @override
  Future<void> connect() async {
    try {
      _clientKey = await _persistence.loadLgClientKey(host);
      final wsUrl = Uri.parse('ws://$host:$port');
      _channel = WebSocketChannel.connect(wsUrl);

      // 1. Send register payload
      final registerPayload = {
        "type": "register",
        "id": "register_0",
        "payload": {
          "forcePairing": false,
          "pairingType": "PROMPT",
          "client-key": _clientKey,
          "manifest": {
            "permissions": [
              "LAUNCH",
              "CONTROL_AUDIO",
              "CONTROL_POWER",
              "CONTROL_INPUT_TV",
              "READ_INSTALLED_APPS",
              "CHECK_3D"
            ]
          }
        }
      };

      _channel!.sink.add(jsonEncode(registerPayload));

      // 2. Listen for responses
      final completer = Completer<void>();
      _channel!.stream.listen(
        (message) {
          final data = jsonDecode(message);
          if (data['type'] == 'registered') {
            _clientKey = data['payload']['client-key'];
            if (_clientKey != null) {
              _persistence.saveLgClientKey(host, _clientKey!);
            }
            _connected = true;
            if (!completer.isCompleted) completer.complete();
            _startHeartbeat();
            log.d('LgController: Connected to $host');
          } else if (data['type'] == 'error') {
            if (!completer.isCompleted) completer.completeError(Exception(data['error']));
          } else if (message == 'pong') {
            _pongTimeoutTimer?.cancel();
          }
        },
        onDone: () => _handleDisconnect(),
        onError: (e) {
          if (!completer.isCompleted) completer.completeError(e);
          _handleDisconnect();
        },
      );

      await completer.future.timeout(const Duration(seconds: 10));
    } catch (e) {
      _connected = false;
      log.e('LgController: LG TV not reachable at $host', e);
      rethrow;
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_connected) {
        _channel?.sink.add('ping');
        _pongTimeoutTimer?.cancel();
        _pongTimeoutTimer = Timer(const Duration(seconds: 5), () {
          log.w('LgController: Pong timeout');
          _handleDisconnect();
        });
      }
    });
  }

  void _handleDisconnect() {
    _connected = false;
    _heartbeatTimer?.cancel();
    _pongTimeoutTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    log.d('LgController: Disconnected from $host');
  }

  @override
  Future<void> disconnect() async {
    _handleDisconnect();
  }

  @override
  bool get isConnected => _connected;

  @override
  Future<void> sendKey(RemoteKey key) async {
    if (!_connected || _channel == null) return;

    final uri = _ssapUris[key];
    if (uri == null) {
      log.d('LgController: Key ${key.name} not supported on LG.');
      return;
    }

    final payload = {
      "type": "request",
      "id": "request_${DateTime.now().millisecondsSinceEpoch}",
      "uri": uri,
    };

    try {
      _channel!.sink.add(jsonEncode(payload));
    } catch (e) {
      log.e('LgController: Failed to send key ${key.name}', e);
    }
  }

  @override
  Future<void> sendText(String text) async {
    if (!_connected || _channel == null) return;
    // LG text input is complex via SSAP, typically uses com.webos.service.ime/insertText
    final payload = {
      "type": "request",
      "id": "request_text",
      "uri": "ssap://com.webos.service.ime/insertText",
      "payload": {"text": text, "replace": 0}
    };
    _channel!.sink.add(jsonEncode(payload));
  }

  @override
  Future<void> launchApp(AppId appId) async {
    if (!_connected || _channel == null) return;

    final lgAppId = _appIds[appId];
    if (lgAppId == null) {
      log.w('LgController: App ${appId.name} not found in mapping.');
      return;
    }

    final payload = {
      "type": "request",
      "id": "request_launch",
      "uri": "ssap://system.launcher/launch",
      "payload": {"id": lgAppId}
    };

    try {
      _channel!.sink.add(jsonEncode(payload));
      log.d('LgController: Launched app ${appId.name} ($lgAppId)');
    } catch (e) {
      log.e('LgController: Failed to launch ${appId.name}', e);
    }
  }

  static const Map<RemoteKey, String> _ssapUris = {
    RemoteKey.up: 'ssap://com.webos.service.tv.display/set3DOn', // Placeholder, LG often uses pointer
    RemoteKey.down: 'ssap://com.webos.service.tv.display/set3DOff',
    RemoteKey.volumeUp: 'ssap://audio/volumeUp',
    RemoteKey.volumeDown: 'ssap://audio/volumeDown',
    RemoteKey.mute: 'ssap://audio/setMute',
    RemoteKey.channelUp: 'ssap://tv/channelUp',
    RemoteKey.channelDown: 'ssap://tv/channelDown',
    RemoteKey.home: 'ssap://system.launcher/open',
    RemoteKey.back: 'ssap://system.launcher/close',
    RemoteKey.power: 'ssap://system/turnOff',
    RemoteKey.playPause: 'ssap://media.controls/play',
    RemoteKey.rewind: 'ssap://media.controls/rewind',
    RemoteKey.fastForward: 'ssap://media.controls/fastForward',
    RemoteKey.ok: 'ssap://com.webos.service.ime/sendEnterKey',
    RemoteKey.select: 'ssap://com.webos.service.ime/sendEnterKey',
  };

  static const Map<AppId, String> _appIds = {
    AppId.netflix: 'netflix',
    AppId.youtube: 'youtube.leanback.v4',
    AppId.primeVideo: 'amazon',
    AppId.disneyPlus: 'disneyplus',
    AppId.hulu: 'hulu',
    AppId.spotify: 'spotify',
  };
}
