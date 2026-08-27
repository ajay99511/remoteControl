import 'dart:async';
import 'package:http/http.dart' as http;

import '../core/app_logger.dart';
import '../models/app_id.dart';
import '../models/command_result.dart';
import '../models/remote_key.dart';
import 'controller_health.dart';
import 'device_controller.dart';

/// Concrete [DeviceController] for Roku devices using the
/// External Control Protocol (ECP).
class RokuController with HealthReporting implements DeviceController {
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
        reportHealth(ControllerHealth.connected);
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
    reportHealth(ControllerHealth.disconnected);
    closeHealth();
    log.d('RokuController: Disconnected from $host:$port');
  }

  @override
  Set<RemoteKey> get supportedKeys => _keyMap.keys.toSet();

  @override
  Future<CommandResult> sendKey(RemoteKey key) async {
    if (!_connected) return const CommandNotConnected();
    final ecpKey = _keyMap[key];
    if (ecpKey == null) return CommandUnsupported(key.name);
    try {
      await _client
          .post(_ecpUri('keypress/$ecpKey'))
          .timeout(const Duration(seconds: 3));
      return const CommandSent();
    } catch (e, s) {
      log.e('RokuController: Failed to send key $ecpKey', e, s);
      return CommandFailed(e, s);
    }
  }

  /// Roku ECP requires one POST per character, so long input is many round
  /// trips. Capped for parity with SamsungController, and paced because the
  /// device drops keypresses above roughly 20/s.
  static const _maxTextLength = 500;
  static const _interKeyDelay = Duration(milliseconds: 60);

  @override
  Future<CommandResult> sendText(String text) async {
    if (!_connected) return const CommandNotConnected();
    if (text.length > _maxTextLength) {
      log.w(
        'RokuController: truncating ${text.length} chars to $_maxTextLength',
      );
      text = text.substring(0, _maxTextLength);
    }
    final runes = text.runes.toList();
    for (var i = 0; i < runes.length; i++) {
      if (!_connected) return const CommandNotConnected();
      final char = String.fromCharCode(runes[i]);
      try {
        await _client
            .post(_ecpUri('keypress/Lit_${Uri.encodeComponent(char)}'))
            .timeout(const Duration(seconds: 3));
      } catch (e, s) {
        // Abort rather than skip: continuing would type a different string
        // than the user asked for, silently.
        log.e('RokuController: failed after $i of ${runes.length} chars', e, s);
        return CommandFailed(e, s);
      }
      if (i + 1 < runes.length) await Future<void>.delayed(_interKeyDelay);
    }
    return const CommandSent();
  }

  @override
  Future<CommandResult> launchApp(AppId appId) async {
    if (!_connected) return const CommandNotConnected();
    final rokuAppId = _appIds[appId];
    if (rokuAppId == null) return CommandUnsupported(appId.displayName);
    try {
      await _client
          .post(_ecpUri('launch/$rokuAppId'))
          .timeout(const Duration(seconds: 3));
      log.d('RokuController: Launched app ${appId.name} ($rokuAppId)');
      return const CommandSent();
    } catch (e, s) {
      log.e('RokuController: Failed to launch ${appId.name}', e, s);
      return CommandFailed(e, s);
    }
  }

  @override
  bool get isConnected => _connected;
}
