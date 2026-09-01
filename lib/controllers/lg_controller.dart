import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/app_logger.dart';
import '../models/app_id.dart';
import '../models/command_result.dart';
import '../models/remote_key.dart';
import '../services/device_persistence_service.dart';
import 'controller_health.dart';
import 'device_controller.dart';

/// Permissions requested when registering with a webOS TV.
///
/// webOS grants per-permission and denies calls outside the granted set, so
/// this list has to cover every SSAP URI the controller sends. It did not:
///
///   - `ssap://com.webos.service.ime/*` needs CONTROL_INPUT_TEXT, which was
///     absent. RemoteKey.ok and RemoteKey.select both route to
///     `sendEnterKey`, so a real TV denied the OK button.
///   - `ssap://media.controls/*` needs CONTROL_INPUT_MEDIA_PLAYBACK, also
///     absent, so play/rewind/fast-forward were denied.
///
/// It also asked for two it does not use: CHECK_3D, left over from the
/// set3DOn/set3DOff mapping removed as audit finding H-1, and
/// READ_INSTALLED_APPS, which nothing here reads. Asking a user to grant
/// capabilities the app never exercises is its own small breach of trust.
///
/// [ssapUriPermissions] records which permission covers which URI prefix, and
/// a test asserts the two stay in step.
const ssapPermissions = [
  'LAUNCH',
  'CONTROL_AUDIO',
  'CONTROL_POWER',
  'CONTROL_INPUT_TV',
  'CONTROL_INPUT_MEDIA_PLAYBACK',
  'CONTROL_INPUT_TEXT',
];

/// URI prefix -> the permission webOS requires for it.
const ssapUriPermissions = <String, String>{
  'ssap://system.launcher/': 'LAUNCH',
  'ssap://audio/': 'CONTROL_AUDIO',
  'ssap://system/': 'CONTROL_POWER',
  'ssap://tv/': 'CONTROL_INPUT_TV',
  'ssap://media.controls/': 'CONTROL_INPUT_MEDIA_PLAYBACK',
  'ssap://com.webos.service.ime/': 'CONTROL_INPUT_TEXT',
};

/// LG webOS TV controller via SSAP WebSocket on port 3000 (Requirement 2.4).
class LgController with HealthReporting implements DeviceController {
  final String host;
  final int port;
  final DevicePersistenceService _persistence;

  WebSocketChannel? _channel;
  bool _connected = false;
  Timer? _heartbeatTimer;
  Timer? _pongTimeoutTimer;
  String? _clientKey;

  /// Seam for tests, mirroring [SamsungController]. Production passes null and
  /// the real socket is opened by [WebSocketChannel.connect].
  final WebSocketChannel Function(Uri)? _channelFactory;

  /// Where this device's secrets are filed. Defaults to [host] so existing
  /// call sites behave as before, but the factory passes Device.credentialKey
  /// so a pairing token survives the router handing the TV a new address.
  final String _credentialKey;

  LgController({
    required this.host,
    this.port = 3000,
    required DevicePersistenceService persistence,
    WebSocketChannel Function(Uri)? channelFactory,
    String? credentialKey,
  }) : _persistence = persistence,
       _channelFactory = channelFactory,
       _credentialKey = credentialKey ?? host;

  @override
  Future<void> connect() async {
    try {
      _clientKey = await _persistence.loadLgClientKey(_credentialKey);
      final wsUrl = Uri.parse('ws://$host:$port');
      _channel =
          _channelFactory?.call(wsUrl) ?? WebSocketChannel.connect(wsUrl);

      // 1. Send register payload
      final registerPayload = {
        "type": "register",
        "id": "register_0",
        "payload": {
          "forcePairing": false,
          "pairingType": "PROMPT",
          "client-key": _clientKey,
          "manifest": {"permissions": ssapPermissions},
        },
      };

      _channel!.sink.add(jsonEncode(registerPayload));

      // 2. Listen for responses
      final completer = Completer<void>();
      _channel!.stream.listen(
        (message) {
          // Any inbound frame proves liveness, so clear the pong deadline
          // before any parsing that can throw. Testing the sentinel after
          // jsonDecode made this branch unreachable and guaranteed a
          // disconnect at T+35s.
          _pongTimeoutTimer?.cancel();

          if (message is! String || message == 'pong') return;

          final Map<String, dynamic> data;
          try {
            data = jsonDecode(message) as Map<String, dynamic>;
          } on FormatException catch (e, s) {
            log.d('LgController: ignoring non-JSON frame', e, s);
            return;
          }

          if (data['type'] == 'registered') {
            final payload = data['payload'] as Map<String, dynamic>?;
            _clientKey = payload?['client-key'] as String?;
            if (_clientKey != null) {
              unawaited(
                _persistence.saveLgClientKey(_credentialKey, _clientKey!),
              );
            }
            _connected = true;
            if (!completer.isCompleted) completer.complete();
            _startHeartbeat();
            reportHealth(ControllerHealth.connected);
            log.d('LgController: Connected to $host');
          } else if (data['type'] == 'error') {
            if (!completer.isCompleted) {
              completer.completeError(Exception(data['error']));
            }
          }
        },
        onDone: _handleDisconnect,
        onError: (Object e, StackTrace s) {
          if (!completer.isCompleted) completer.completeError(e, s);
          _handleDisconnect();
        },
        cancelOnError: false,
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
    final wasConnected = _connected;
    _connected = false;
    _heartbeatTimer?.cancel();
    _pongTimeoutTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    log.d('LgController: Disconnected from $host');
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
  Set<RemoteKey> get supportedKeys => _ssapUris.keys.toSet();

  @override
  Future<CommandResult> sendKey(RemoteKey key) async {
    if (!_connected || _channel == null) return const CommandNotConnected();

    final uri = _ssapUris[key];
    if (uri == null) return CommandUnsupported(key.name);

    final payload = {
      "type": "request",
      "id": "request_${DateTime.now().millisecondsSinceEpoch}",
      "uri": uri,
    };

    try {
      _channel!.sink.add(jsonEncode(payload));
      return const CommandSent();
    } catch (e, s) {
      log.e('LgController: Failed to send key ${key.name}', e, s);
      return CommandFailed(e, s);
    }
  }

  @override
  Future<CommandResult> sendText(String text) async {
    if (!_connected || _channel == null) return const CommandNotConnected();
    final payload = {
      "type": "request",
      "id": "request_text",
      "uri": "ssap://com.webos.service.ime/insertText",
      "payload": {"text": text, "replace": 0},
    };
    try {
      _channel!.sink.add(jsonEncode(payload));
      return const CommandSent();
    } catch (e, s) {
      log.e('LgController: Failed to send text', e, s);
      return CommandFailed(e, s);
    }
  }

  @override
  Future<CommandResult> launchApp(AppId appId) async {
    if (!_connected || _channel == null) return const CommandNotConnected();

    final lgAppId = _appIds[appId];
    if (lgAppId == null) return CommandUnsupported(appId.displayName);

    final payload = {
      "type": "request",
      "id": "request_launch",
      "uri": "ssap://system.launcher/launch",
      "payload": {"id": lgAppId},
    };

    try {
      _channel!.sink.add(jsonEncode(payload));
      log.d('LgController: Launched app ${appId.name} ($lgAppId)');
      return const CommandSent();
    } catch (e, s) {
      log.e('LgController: Failed to launch ${appId.name}', e, s);
      return CommandFailed(e, s);
    }
  }

  // webOS exposes no SSAP URI for D-pad arrows; they are reachable only over
  // the pointer input socket, obtained via
  // ssap://com.webos.service.networkinput/getPointerInputSocket.
  //
  // up/down were previously mapped to set3DOn/set3DOff, so the two most-used
  // navigation keys toggled the TV's 3D mode - not navigation, and hard for a
  // user to undo. Until the pointer socket is implemented, these keys report
  // as unsupported so the UI can say so instead of firing something unrelated.
  /// The SSAP URIs this controller can send, exposed so a test can check
  /// every one of them is covered by [ssapPermissions].
  @visibleForTesting
  static Iterable<String> get ssapUris => [
    ..._ssapUris.values,
    'ssap://com.webos.service.ime/insertText',
    'ssap://system.launcher/launch',
  ];

  static const Map<RemoteKey, String> _ssapUris = {
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
