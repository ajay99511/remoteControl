import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/app_logger.dart';
import '../models/app_id.dart';
import '../models/remote_key.dart';
import '../services/device_persistence_service.dart';
import 'device_controller.dart';

/// Concrete [DeviceController] for Samsung Smart TVs (Tizen).
class SamsungController implements DeviceController {
  final String host;
  final int port;
  final DevicePersistenceService _persistence;

  WebSocketChannel? _channel;
  bool _connected = false;
  Timer? _heartbeatTimer;
  Timer? _pongTimeoutTimer;

  final WebSocketChannel Function(Uri)? _channelFactory;

  SamsungController({
    required this.host,
    this.port = 8001,
    required DevicePersistenceService persistence,
    WebSocketChannel Function(Uri)? channelFactory,
  })  : _persistence = persistence,
        _channelFactory = channelFactory;

  static const Map<RemoteKey, String> _keyMap = {
    RemoteKey.up: 'KEY_UP',
    RemoteKey.down: 'KEY_DOWN',
    RemoteKey.left: 'KEY_LEFT',
    RemoteKey.right: 'KEY_RIGHT',
    RemoteKey.select: 'KEY_ENTER',
    RemoteKey.ok: 'KEY_ENTER',
    RemoteKey.back: 'KEY_RETURN',
    RemoteKey.exit: 'KEY_EXIT',
    RemoteKey.home: 'KEY_HOME',
    RemoteKey.menu: 'KEY_MENU',
    RemoteKey.info: 'KEY_INFO',
    RemoteKey.guide: 'KEY_GUIDE',
    RemoteKey.search: 'KEY_SEARCH',
    RemoteKey.settings: 'KEY_SETTINGS',
    RemoteKey.playPause: 'KEY_PLAY',
    RemoteKey.rewind: 'KEY_REWIND',
    RemoteKey.fastForward: 'KEY_FF',
    RemoteKey.replay: 'KEY_REPLAY',
    RemoteKey.instantReplay: 'KEY_INSTANT_REPLAY',
    RemoteKey.record: 'KEY_REC',
    RemoteKey.volumeUp: 'KEY_VOLUP',
    RemoteKey.volumeDown: 'KEY_VOLDOWN',
    RemoteKey.mute: 'KEY_MUTE',
    RemoteKey.channelUp: 'KEY_CHUP',
    RemoteKey.channelDown: 'KEY_CHDOWN',
    RemoteKey.inputSource: 'KEY_SOURCE',
    RemoteKey.aspectRatio: 'KEY_P_SIZE',
    RemoteKey.pip: 'KEY_PIP_ONOFF',
    RemoteKey.subtitles: 'KEY_SUBTITLE',
    RemoteKey.audioTrack: 'KEY_MTS',
    RemoteKey.power: 'KEY_POWER',
    RemoteKey.sleep: 'KEY_SLEEP',
    RemoteKey.star: 'KEY_TOOLS',
  };

  static const Map<AppId, String> _appIds = {
    AppId.netflix: '11101200001',
    AppId.youtube: '111299001912',
    AppId.primeVideo: '3201512006785',
    AppId.disneyPlus: '3201901017640',
    AppId.spotify: '3201608010191',
    AppId.hulu: '3201601007625',
    AppId.appleTv: '3201807016597',
  };

  @override
  Future<void> connect() async {
    try {
      final nameBase64 = base64Encode(utf8.encode('FlutterRemote'));
      final token = await _persistence.loadSamsungToken(host);
      final tokenQuery = token != null ? '&token=$token' : '';

      try {
        // Attempt 1: Modern WSS on port 8002 (Tizen 2016+) with TOFU
        final wssUrl = Uri.parse(
          'wss://$host:8002/api/v2/channels/samsung.remote.control?name=$nameBase64$tokenQuery',
        );

        if (_channelFactory != null) {
          _channel = _channelFactory!(wssUrl);
          _onConnected('mock-wss:8002');
          return;
        }

        final storedFingerprint = await _persistence.loadCertFingerprint(host);

        final httpClient = HttpClient()
          ..badCertificateCallback = (cert, certHost, certPort) {
            final fingerprint = sha256.convert(cert.der).toString();
            if (storedFingerprint == null) {
              log.i('SamsungController: Pinning new certificate for $host');
              _persistence.saveCertFingerprint(host, fingerprint);
              return true;
            }
            if (storedFingerprint == fingerprint) {
              return true;
            }
            log.e('SamsungController: TOFU mismatch for $host!');
            return false;
          };

        final socket = await WebSocket.connect(
          wssUrl.toString(),
          customClient: httpClient,
        ).timeout(const Duration(seconds: 3));

        _channel = IOWebSocketChannel(socket);
        _onConnected('wss:8002');
        return;
      } catch (e) {
        log.d('SamsungController: wss://8002 failed, trying ws://8001 ($e)');
      }

      // Attempt 2: Legacy WS on port 8001
      final wsUrl = Uri.parse(
        'ws://$host:8001/api/v2/channels/samsung.remote.control?name=$nameBase64$tokenQuery',
      );
      if (_channelFactory != null) {
        _channel = _channelFactory!(wsUrl);
      } else {
        _channel = IOWebSocketChannel(await WebSocket.connect(wsUrl.toString()).timeout(const Duration(seconds: 3)));
      }
      _onConnected('ws:8001');
    } catch (e) {
      _connected = false;
      log.e('SamsungController: Samsung TV not reachable at $host', e);
      rethrow;
    }
  }

  void _onConnected(String protocol) {
    _connected = true;
    log.d('SamsungController: Connected to $host via $protocol');
    
    _channel!.stream.listen(
      (message) {
        final data = jsonDecode(message);
        if (data['event'] == 'ms.channel.connect') {
          final token = data['data']['token'];
          if (token != null) {
            _persistence.saveSamsungToken(host, token);
          }
        } else if (message == 'pong') {
          _pongTimeoutTimer?.cancel();
        }
      },
      onDone: () => _handleDisconnect(),
      onError: (e) => log.e('SamsungController: WebSocket error', e),
    );

    _startHeartbeat();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_connected) {
        _channel?.sink.add('ping');
        _pongTimeoutTimer?.cancel();
        _pongTimeoutTimer = Timer(const Duration(seconds: 5), () {
          log.w('SamsungController: Pong timeout');
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
    log.d('SamsungController: Disconnected from $host');
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

    final samsungKey = _keyMap[key];
    if (samsungKey == null) {
      log.d('SamsungController: Key ${key.name} not supported on Samsung.');
      return;
    }

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
      log.e('SamsungController: Failed to send key $samsungKey', e);
    }
  }

  @override
  Future<void> sendText(String text) async {
    if (!_connected || _channel == null) return;

    // Truncate to 500 chars (Requirement 2.3)
    final safeText = text.length > 500 ? text.substring(0, 500) : text;
    final textBase64 = base64Encode(utf8.encode(safeText));

    final payload = {
      "method": "ms.remote.control",
      "params": {
        "Cmd": textBase64,
        "DataOfCmd": "base64",
        "Option": "false",
        "TypeOfRemote": "SendInputString",
      },
    };

    try {
      _channel!.sink.add(jsonEncode(payload));
      log.d('SamsungController: Sent text input');
    } catch (e) {
      log.e('SamsungController: Failed to send text', e);
    }
  }

  @override
  Future<void> launchApp(AppId appId) async {
    if (!_connected || _channel == null) return;

    final samsungAppId = _appIds[appId];
    if (samsungAppId == null) {
      log.w('SamsungController: App ${appId.name} not found in mapping.');
      return;
    }

    final payload = {
      "method": "ms.channel.emit",
      "params": {
        "event": "ed.apps.launch",
        "to": "host",
        "data": {
          "appId": samsungAppId,
          "action_type": "DEEP_LINK",
        },
      },
    };

    try {
      _channel!.sink.add(jsonEncode(payload));
      log.d('SamsungController: Launched app ${appId.name} ($samsungAppId)');
    } catch (e) {
      log.e('SamsungController: Failed to launch ${appId.name}', e);
    }
  }
}
