import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/app_logger.dart';
import '../models/app_id.dart';
import '../models/remote_key.dart';
import 'device_controller.dart';

/// Vizio SmartCast REST API controller on port 7345 (Requirement 2.5).
class VizioController implements DeviceController {
  final String host;
  final int port;
  final http.Client _client;

  bool _connected = false;
  String? _authToken;

  VizioController({
    required this.host,
    this.port = 7345,
    http.Client? client,
  }) : _client = client ?? http.Client();

  Uri _smartCastUri(String path) =>
      Uri.parse('https://$host:$port/$path');

  @override
  Future<void> connect() async {
    // Note: Vizio requires a pairing flow to get an auth token.
    // This implementation assumes the token is either not needed for basic
    // commands or handled via a separate pairing process.
    // For this hardened version, we'll try a basic GET to see if it's reachable.
    try {
      final response = await _client
          .get(_smartCastUri('state/device/info'))
          .timeout(const Duration(seconds: 3));
      
      // In a real scenario, we'd handle the 401 and start pairing.
      if (response.statusCode == 200 || response.statusCode == 401) {
        _connected = true;
        log.d('VizioController: Connected to $host');
      } else {
        throw Exception('Vizio responded with status ${response.statusCode}');
      }
    } catch (e) {
      _connected = false;
      log.e('VizioController: Vizio not reachable at $host', e);
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    log.d('VizioController: Disconnected from $host');
  }

  @override
  bool get isConnected => _connected;

  @override
  Future<void> sendKey(RemoteKey key) async {
    if (!_connected) return;

    final mapping = _keyMap[key];
    if (mapping == null) {
      log.d('VizioController: Key ${key.name} not supported on Vizio.');
      return;
    }

    final payload = {
      "KEYLIST": [
        {
          "CODESET": mapping['codeset'],
          "CODE": mapping['code'],
          "ACTION": "KEYPRESS"
        }
      ]
    };

    try {
      await _client.put(
        _smartCastUri('key_command/'),
        headers: {
          'Content-Type': 'application/json',
          if (_authToken != null) 'X-Auth-Token': _authToken!,
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 3));
    } catch (e) {
      log.e('VizioController: Failed to send key ${key.name}', e);
    }
  }

  @override
  Future<void> sendText(String text) async {
    // Vizio SmartCast doesn't support direct text input via this API easily.
    log.d('VizioController: sendText not supported.');
  }

  @override
  Future<void> launchApp(AppId appId) async {
    if (!_connected) return;
    
    // Vizio app launching is complex and requires specific payloads.
    log.d('VizioController: launchApp ${appId.name} called (stub).');
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
