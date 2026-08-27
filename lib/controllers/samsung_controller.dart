import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/app_logger.dart';
import '../core/certificate_pinning.dart';
import '../exceptions/certificate_pin_mismatch_exception.dart';
import '../models/app_id.dart';
import '../models/command_result.dart';
import '../models/remote_key.dart';
import '../services/device_persistence_service.dart';
import 'controller_health.dart';
import 'device_controller.dart';

/// Concrete [DeviceController] for Samsung Smart TVs (Tizen).
class SamsungController with HealthReporting implements DeviceController {
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
  }) : _persistence = persistence,
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
    RemoteKey.digit0: 'KEY_0',
    RemoteKey.digit1: 'KEY_1',
    RemoteKey.digit2: 'KEY_2',
    RemoteKey.digit3: 'KEY_3',
    RemoteKey.digit4: 'KEY_4',
    RemoteKey.digit5: 'KEY_5',
    RemoteKey.digit6: 'KEY_6',
    RemoteKey.digit7: 'KEY_7',
    RemoteKey.digit8: 'KEY_8',
    RemoteKey.digit9: 'KEY_9',
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

  static const _clientName = 'FlutterRemote';
  static const _securePort = 8002; // Tizen 2016+ (WSS)
  static const _legacyPort = 8001; // pre-2016 (plaintext WS)
  static const _connectTimeout = Duration(seconds: 3);
  static const _channelPath = '/api/v2/channels/samsung.remote.control';

  @override
  Future<void> connect() async {
    try {
      final nameBase64 = base64Encode(utf8.encode(_clientName));
      final token = await _persistence.loadSamsungToken(host);
      final tokenQuery = token != null ? '&token=$token' : '';
      final query = 'name=$nameBase64$tokenQuery';

      final wssUrl = Uri.parse('wss://$host:$_securePort$_channelPath?$query');

      if (_channelFactory != null) {
        _channel = _channelFactory(wssUrl);
        _onConnected('mock-wss:$_securePort');
        return;
      }

      try {
        await _connectSecure(wssUrl);
        return;
      } on CertificatePinMismatchException {
        // Fail CLOSED. A pin mismatch is precisely the attack TOFU exists to
        // detect; downgrading to plaintext here would hand the attacker the
        // pairing token that travels in the query string.
        rethrow;
      } catch (e) {
        log.d(
          'SamsungController: wss://$host:$_securePort unavailable, '
          'trying legacy ws://$host:$_legacyPort ($e)',
        );
      }

      // Attempt 2: legacy plaintext WS, only for TVs that never offered TLS.
      final wsUrl = Uri.parse('ws://$host:$_legacyPort$_channelPath?$query');
      _channel = IOWebSocketChannel(
        await WebSocket.connect(wsUrl.toString()).timeout(_connectTimeout),
      );
      _onConnected('ws:$_legacyPort');
    } catch (e) {
      _connected = false;
      log.e('SamsungController: Samsung TV not reachable at $host', e);
      rethrow;
    }
  }

  /// Opens the pinned WSS channel, or throws.
  ///
  /// Throws [CertificatePinMismatchException] when the presented certificate
  /// contradicts the pin recorded on first use. The caller must not fall back
  /// to plaintext on that exception.
  Future<void> _connectSecure(Uri wssUrl) async {
    final pinning = PinningSession(
      host: host,
      stored: await _persistence.loadCertFingerprint(host),
    );

    // Ownership of the socket transfers to _channel below, and
    // _handleDisconnect closes it; the lint cannot follow that hand-off.
    // ignore: close_sinks
    final WebSocket socket;
    try {
      socket = await WebSocket.connect(
        wssUrl.toString(),
        customClient: pinning.createClient(),
      ).timeout(_connectTimeout);
    } catch (e) {
      if (pinning.wasRejected) throw CertificatePinMismatchException(host);
      rethrow;
    }

    await pinning.commit(_persistence);

    _channel = IOWebSocketChannel(socket);
    _onConnected('wss:$_securePort');
  }

  void _onConnected(String protocol) {
    _connected = true;
    log.d('SamsungController: Connected to $host via $protocol');
    reportHealth(ControllerHealth.connected);

    _channel!.stream.listen(
      (message) {
        // Any inbound frame proves liveness, so clear the pong deadline before
        // any parsing that can throw. Testing the sentinel after jsonDecode
        // made this branch unreachable and guaranteed a disconnect at T+35s.
        _pongTimeoutTimer?.cancel();

        if (message is! String || message == 'pong') return;

        final Map<String, dynamic> data;
        try {
          data = jsonDecode(message) as Map<String, dynamic>;
        } on FormatException catch (e, s) {
          // Some Tizen revisions emit bare text frames. They are liveness
          // evidence, not an error, and must not escape the listener.
          log.d('SamsungController: ignoring non-JSON frame', e, s);
          return;
        }

        if (data['event'] == 'ms.channel.connect') {
          final payload = data['data'] as Map<String, dynamic>?;
          final token = payload?['token'] as String?;
          if (token != null) {
            unawaited(_persistence.saveSamsungToken(host, token));
          }
        }
      },
      onDone: _handleDisconnect,
      onError: (Object e, StackTrace s) {
        log.e('SamsungController: WebSocket error', e, s);
        _handleDisconnect();
      },
      cancelOnError: false,
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
    final wasConnected = _connected;
    _connected = false;
    _heartbeatTimer?.cancel();
    _pongTimeoutTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    log.d('SamsungController: Disconnected from $host');
    // Announce it even when the app did not ask - a heartbeat timeout or a
    // socket close reaches here too, and used to stop dead at this line.
    if (wasConnected) reportHealth(ControllerHealth.disconnected);
  }

  @override
  Future<void> disconnect() async {
    _handleDisconnect();
    closeHealth();
  }

  @override
  bool get isConnected => _connected;

  @override
  Set<RemoteKey> get supportedKeys => _keyMap.keys.toSet();

  @override
  Future<CommandResult> sendKey(RemoteKey key) async {
    if (!_connected || _channel == null) return const CommandNotConnected();

    final samsungKey = _keyMap[key];
    if (samsungKey == null) return CommandUnsupported(key.name);

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
      return const CommandSent();
    } catch (e, s) {
      log.e('SamsungController: Failed to send key $samsungKey', e, s);
      return CommandFailed(e, s);
    }
  }

  @override
  Future<CommandResult> sendText(String text) async {
    if (!_connected || _channel == null) return const CommandNotConnected();

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
      return const CommandSent();
    } catch (e, s) {
      log.e('SamsungController: Failed to send text', e, s);
      return CommandFailed(e, s);
    }
  }

  @override
  Future<CommandResult> launchApp(AppId appId) async {
    if (!_connected || _channel == null) return const CommandNotConnected();

    final samsungAppId = _appIds[appId];
    if (samsungAppId == null) return CommandUnsupported(appId.displayName);

    final payload = {
      "method": "ms.channel.emit",
      "params": {
        "event": "ed.apps.launch",
        "to": "host",
        "data": {"appId": samsungAppId, "action_type": "DEEP_LINK"},
      },
    };

    try {
      _channel!.sink.add(jsonEncode(payload));
      log.d('SamsungController: Launched app ${appId.name} ($samsungAppId)');
      return const CommandSent();
    } catch (e, s) {
      log.e('SamsungController: Failed to launch ${appId.name}', e, s);
      return CommandFailed(e, s);
    }
  }
}
