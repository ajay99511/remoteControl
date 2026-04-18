import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/remote_key.dart';
import 'device_controller.dart';

/// Concrete [DeviceController] for Roku devices using the
/// External Control Protocol (ECP).
///
/// ECP is a simple REST API: key presses are sent as HTTP POST
/// requests to `http://{host}:{port}/keypress/{key}`.
/// Text input sends one `Lit_<char>` keypress per character.
///
/// See: https://developer.roku.com/docs/developer-program/dev-tools/external-control-api.md
class RokuController implements DeviceController {
  final String host;
  final int port;
  final http.Client _client;
  bool _connected = false;

  RokuController({required this.host, this.port = 8060, http.Client? client})
    : _client = client ?? http.Client();

  /// Roku ECP key name mapping.
  static const Map<RemoteKey, String> _keyMap = {
    RemoteKey.up: 'Up',
    RemoteKey.down: 'Down',
    RemoteKey.left: 'Left',
    RemoteKey.right: 'Right',
    RemoteKey.select: 'Select',
    RemoteKey.back: 'Back',
    RemoteKey.home: 'Home',
    RemoteKey.playPause: 'Play',
    RemoteKey.volumeUp: 'VolumeUp',
    RemoteKey.volumeDown: 'VolumeDown',
    RemoteKey.mute: 'VolumeMute',
    RemoteKey.power: 'Power',
    RemoteKey.rewind: 'Rev',
    RemoteKey.fastForward: 'Fwd',
  };

  /// Common Roku App IDs.
  static const Map<String, String> _appIds = {
    'netflix': '12',
    'youtube': '837',
    'prime video': '13',
    'disney+': '291097',
    'hulu': '2285',
    'spotify': '22297',
  };

  Uri _ecpUri(String path) => Uri.parse('http://$host:$port/$path');

  @override
  Future<void> connect() async {
    try {
      final response = await _client
          .get(_ecpUri('query/device-info'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        _connected = true;
        debugPrint('RokuController: Connected to $host:$port');
      } else {
        throw Exception('Roku responded with status ${response.statusCode}');
      }
    } catch (e) {
      _connected = false;
      throw Exception('Roku not reachable at $host:$port — $e');
    }
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _client.close();
    debugPrint('RokuController: Disconnected from $host:$port');
  }

  @override
  Future<void> sendKey(RemoteKey key) async {
    if (!_connected) return;
    final ecpKey = _keyMap[key] ?? key.name;
    try {
      await _client.post(_ecpUri('keypress/$ecpKey'));
    } catch (e) {
      debugPrint('RokuController: Failed to send key $ecpKey — $e');
    }
  }

  @override
  Future<void> sendText(String text) async {
    if (!_connected) return;
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      final encoded = Uri.encodeComponent(char);
      try {
        await _client.post(_ecpUri('keypress/Lit_$encoded'));
      } catch (e) {
        debugPrint('RokuController: Failed to send char "$char" — $e');
      }
    }
  }

  @override
  Future<void> launchApp(String appName) async {
    if (!_connected) return;
    final appId = _appIds[appName.toLowerCase()];
    if (appId == null) {
      debugPrint('RokuController: App "$appName" not found in mapping.');
      return;
    }
    try {
      await _client.post(_ecpUri('launch/$appId'));
      debugPrint('RokuController: Launched app $appName ($appId)');
    } catch (e) {
      debugPrint('RokuController: Failed to launch $appName — $e');
    }
  }

  @override
  bool get isConnected => _connected;
}
