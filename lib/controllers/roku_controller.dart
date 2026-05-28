import 'dart:async';
import 'package:http/http.dart' as http;

import '../core/app_logger.dart';
import '../models/app_id.dart';
import '../models/remote_key.dart';
import 'device_controller.dart';

/// Concrete [DeviceController] for Roku devices using the
/// External Control Protocol (ECP).
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
    RemoteKey.ok: 'Select',
    RemoteKey.back: 'Back',
    RemoteKey.exit: 'Home',
    RemoteKey.home: 'Home',
    RemoteKey.menu: 'InstantReplay',
    RemoteKey.info: 'Info',
    RemoteKey.guide: 'Guide',
    RemoteKey.search: 'Search',
    RemoteKey.settings: 'Settings',
    RemoteKey.playPause: 'Play',
    RemoteKey.rewind: 'Rev',
    RemoteKey.fastForward: 'Fwd',
    RemoteKey.replay: 'InstantReplay',
    RemoteKey.instantReplay: 'InstantReplay',
    RemoteKey.volumeUp: 'VolumeUp',
    RemoteKey.volumeDown: 'VolumeDown',
    RemoteKey.mute: 'VolumeMute',
    RemoteKey.channelUp: 'ChannelUp',
    RemoteKey.channelDown: 'ChannelDown',
    RemoteKey.inputSource: 'InputTuner',
    RemoteKey.subtitles: 'Subtitle',
    RemoteKey.power: 'Power',
    RemoteKey.sleep: 'Sleep',
    RemoteKey.star: 'Star',
  };

  /// Common Roku App IDs.
  static const Map<AppId, String> _appIds = {
    AppId.netflix: '12',
    AppId.youtube: '837',
    AppId.primeVideo: '13',
    AppId.disneyPlus: '291097',
    AppId.hulu: '2285',
    AppId.spotify: '22297',
  };

  Uri _ecpUri(String path) => Uri.parse('http://$host:$port/$path');

  @override
  Future<void> connect() async {
    try {
      final response = await _client
          .get(_ecpUri('query/device-info'))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        _connected = true;
        log.d('RokuController: Connected to $host:$port');
      } else {
        throw Exception('Roku responded with status ${response.statusCode}');
      }
    } catch (e) {
      _connected = false;
      log.e('RokuController: Roku not reachable at $host:$port', e);
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _client.close();
    log.d('RokuController: Disconnected from $host:$port');
  }

  @override
  Future<void> sendKey(RemoteKey key) async {
    if (!_connected) return;
    final ecpKey = _keyMap[key];
    if (ecpKey == null) {
      log.d('RokuController: Key ${key.name} not supported on Roku.');
      return;
    }
    try {
      await _client
          .post(_ecpUri('keypress/$ecpKey'))
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      log.e('RokuController: Failed to send key $ecpKey', e);
    }
  }

  @override
  Future<void> sendText(String text) async {
    if (!_connected) return;
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      final encoded = Uri.encodeComponent(char);
      try {
        await _client
            .post(_ecpUri('keypress/Lit_$encoded'))
            .timeout(const Duration(seconds: 3));
      } catch (e) {
        log.e('RokuController: Failed to send char "$char"', e);
      }
    }
  }

  @override
  Future<void> launchApp(AppId appId) async {
    if (!_connected) return;
    final rokuAppId = _appIds[appId];
    if (rokuAppId == null) {
      log.w('RokuController: App ${appId.name} not found in mapping.');
      return;
    }
    try {
      await _client
          .post(_ecpUri('launch/$rokuAppId'))
          .timeout(const Duration(seconds: 3));
      log.d('RokuController: Launched app ${appId.name} ($rokuAppId)');
    } catch (e) {
      log.e('RokuController: Failed to launch ${appId.name}', e);
    }
  }

  @override
  bool get isConnected => _connected;
}
