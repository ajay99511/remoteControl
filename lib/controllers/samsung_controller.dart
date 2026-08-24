import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/app_logger.dart';
import '../exceptions/certificate_pin_mismatch_exception.dart';
import '../models/app_id.dart';
import '../models/remote_key.dart';
import '../services/device_persistence_service.dart';
import 'device_controller.dart';

/// Outcome of comparing a presented certificate against the pinned one.
enum CertificateVerdict {
  /// No pin recorded yet: trust this certificate and remember it.
  pinNew,

  /// Presented fingerprint matches the pin.
  trusted,

  /// Presented fingerprint contradicts the pin. Refuse, and do not downgrade.
  rejected,
}

/// The Trust-On-First-Use decision, kept pure so the security rule is testable
/// without a socket. [stored] is the pin from secure storage, [presented] the
/// SHA-256 of the certificate the device just offered.
CertificateVerdict verifyFingerprint({
  required String? stored,
  required String presented,
}) {
  if (stored == null) return CertificateVerdict.pinNew;
  return stored == presented
      ? CertificateVerdict.trusted
      : CertificateVerdict.rejected;
}

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
    final storedFingerprint = await _persistence.loadCertFingerprint(host);
    CertificateVerdict? verdict;
    String? presented;

    final httpClient = HttpClient()
      ..badCertificateCallback = (cert, certHost, certPort) {
        presented = sha256.convert(cert.der).toString();
        verdict = verifyFingerprint(
          stored: storedFingerprint,
          presented: presented!,
        );
        switch (verdict!) {
          case CertificateVerdict.pinNew:
            log.i('SamsungController: pinning new certificate for $host');
            return true;
          case CertificateVerdict.trusted:
            return true;
          case CertificateVerdict.rejected:
            log.e(
              'SamsungController: TOFU mismatch for $host - refusing connection',
            );
            return false;
        }
      };

    final WebSocket socket;
    try {
      socket = await WebSocket.connect(
        wssUrl.toString(),
        customClient: httpClient,
      ).timeout(_connectTimeout);
    } catch (e) {
      // Distinguish "we refused this certificate" from "the TV has no TLS".
      // Both surface as a HandshakeException, and conflating them is what
      // made the pin unenforceable.
      if (verdict == CertificateVerdict.rejected) {
        throw CertificatePinMismatchException(host);
      }
      rethrow;
    }

    // Commit the pin only once the handshake has actually succeeded, and await
    // it so a storage failure is not silently dropped.
    if (verdict == CertificateVerdict.pinNew && presented != null) {
      await _persistence.saveCertFingerprint(host, presented!);
    }

    _channel = IOWebSocketChannel(socket);
    _onConnected('wss:$_securePort');
  }

  void _onConnected(String protocol) {
    _connected = true;
    log.d('SamsungController: Connected to $host via $protocol');
    
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
          final token = data['data']?['token'] as String?;
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
