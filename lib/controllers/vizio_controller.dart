import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../core/app_logger.dart';
import '../core/certificate_pinning.dart';
import '../exceptions/certificate_pin_mismatch_exception.dart';
import '../exceptions/pairing_required_exception.dart';
import '../models/app_id.dart';
import '../models/command_result.dart';
import '../models/remote_key.dart';
import '../services/device_persistence_service.dart';
import 'controller_health.dart';
import 'device_controller.dart';

/// Vizio SmartCast REST API controller on port 7345 (Requirement 2.5).
class VizioController with HealthReporting implements DeviceController {
  final String host;
  final int port;

  /// Non-null only when a test injected one. Production builds a pinned
  /// client at connect time, because the pin has to be read from storage
  /// first and that is async.
  final http.Client? _injectedClient;
  http.Client? _client;

  bool _connected = false;
  String? _authToken;

  final DevicePersistenceService _persistence;

  /// Where this device's secrets are filed. Defaults to [host] so existing
  /// call sites behave as before, but the factory passes Device.credentialKey
  /// so a pairing token survives the router handing the TV a new address.
  final String _credentialKey;

  VizioController({
    required this.host,
    required DevicePersistenceService persistence,
    this.port = 7345,
    http.Client? client,
    String? credentialKey,
  }) : _persistence = persistence,
       _injectedClient = client,
       _client = client,
       _credentialKey = credentialKey ?? host;

  Uri _smartCastUri(String path) => Uri.parse('https://$host:$port/$path');

  @override
  Future<void> connect() async {
    // SmartCast serves HTTPS on 7345 with a self-signed certificate, which
    // the default client rejects outright - so connect() used to throw
    // HandshakeException before any of the status handling below ever ran.
    // Pin it on first use, the same way Samsung does.
    final pinning = PinningSession(
      host: _credentialKey,
      stored: await _persistence.loadCertFingerprint(_credentialKey),
    );
    _client = _injectedClient ?? IOClient(pinning.createClient());

    try {
      // Use the token from a previous pairing, if any. This storage API
      // existed but had no caller, so _authToken was permanently null and the
      // AUTH header was never sent.
      _authToken = await _persistence.loadVizioToken(_credentialKey);

      final response = await _client!
          .get(
            _smartCastUri('state/device/info'),
            headers: {'AUTH': ?_authToken},
          )
          .timeout(const Duration(seconds: 3));

      await pinning.commit(_persistence);

      switch (response.statusCode) {
        case 200:
          _connected = true;
          reportHealth(ControllerHealth.connected);
          log.d('VizioController: Connected to $host');
        case 401:
        case 403:
          // Reachable, but not paired. Recording this as success left an
          // unauthenticated session reporting as connected, after which every
          // command 401'd into a swallowed catch.
          throw PairingRequiredException(host);
        default:
          throw Exception('Vizio responded with status ${response.statusCode}');
      }
    } catch (e) {
      _connected = false;
      if (pinning.wasRejected) {
        log.e('VizioController: refusing $host on a changed certificate');
        throw CertificatePinMismatchException(host);
      }
      log.e('VizioController: Vizio not reachable at $host', e);
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    reportHealth(ControllerHealth.disconnected);
    closeHealth();
    log.d('VizioController: Disconnected from $host');
  }

  @override
  bool get isConnected => _connected;

  @override
  Set<RemoteKey> get supportedKeys => _keyMap.keys.toSet();

  @override
  Future<CommandResult> sendKey(RemoteKey key) async {
    if (!_connected) return const CommandNotConnected();

    final mapping = _keyMap[key];
    if (mapping == null) return CommandUnsupported(key.name);

    final payload = {
      "KEYLIST": [
        {
          "CODESET": mapping['codeset'],
          "CODE": mapping['code'],
          "ACTION": "KEYPRESS",
        },
      ],
    };

    try {
      await _client!
          .put(
            _smartCastUri('key_command/'),
            headers: {'Content-Type': 'application/json', 'AUTH': ?_authToken},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 3));
      return const CommandSent();
    } catch (e, s) {
      log.e('VizioController: Failed to send key ${key.name}', e, s);
      return CommandFailed(e, s);
    }
  }

  @override
  Future<CommandResult> sendText(String text) async =>
      // SmartCast exposes no text-entry endpoint on this API.
      const CommandUnsupported('text entry');

  @override
  Future<CommandResult> launchApp(AppId appId) async {
    if (!_connected) return const CommandNotConnected();
    // SmartCast app launch needs per-app payloads this controller does not
    // carry yet. Reported as unsupported rather than logged and forgotten.
    return CommandUnsupported(appId.displayName);
  }

  static const Map<RemoteKey, Map<String, int>> _keyMap = {
    RemoteKey.up: {'codeset': 3, 'code': 8},
    RemoteKey.down: {'codeset': 3, 'code': 0},
    RemoteKey.left: {'codeset': 3, 'code': 1},
    RemoteKey.right: {'codeset': 3, 'code': 7},
    RemoteKey.select: {'codeset': 3, 'code': 2},
    RemoteKey.ok: {'codeset': 3, 'code': 2},
    RemoteKey.back: {'codeset': 4, 'code': 0},
    RemoteKey.volumeUp: {'codeset': 5, 'code': 1},
    RemoteKey.volumeDown: {'codeset': 5, 'code': 0},
    RemoteKey.mute: {'codeset': 5, 'code': 3},
    RemoteKey.power: {'codeset': 11, 'code': 0},
    RemoteKey.home: {'codeset': 4, 'code': 3},
    RemoteKey.menu: {'codeset': 4, 'code': 8},
    RemoteKey.info: {'codeset': 4, 'code': 6},
    RemoteKey.guide: {'codeset': 4, 'code': 7},
    RemoteKey.channelUp: {'codeset': 8, 'code': 1},
    RemoteKey.channelDown: {'codeset': 8, 'code': 0},
    RemoteKey.playPause: {'codeset': 2, 'code': 2},
    RemoteKey.rewind: {'codeset': 2, 'code': 0},
    RemoteKey.fastForward: {'codeset': 2, 'code': 1},
  };
}
