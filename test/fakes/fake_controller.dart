import 'dart:async';

import 'package:devicecontroller/controllers/controller_health.dart';
import 'package:devicecontroller/controllers/device_controller.dart';
import 'package:devicecontroller/models/app_id.dart';
import 'package:devicecontroller/models/command_result.dart';
import 'package:devicecontroller/models/remote_key.dart';

/// A controller whose behaviour the test dictates.
///
/// Exists so provider tests can exercise connect/retry/health paths without
/// touching a socket. The suite previously connected to 0.0.0.0 for real and
/// sat through four genuine 3-second timeouts to test the retry policy.
class FakeController with HealthReporting implements DeviceController {
  /// Thrown by [connect] when set. Lets a test choose the failure type, which
  /// is what the retry policy branches on.
  final Object? connectError;

  /// Number of times [connect] has been called.
  int connectCalls = 0;

  bool _connected = false;

  FakeController({this.connectError});

  @override
  Future<void> connect() async {
    connectCalls++;
    if (connectError != null) {
      _connected = false;
      throw connectError!;
    }
    _connected = true;
    reportHealth(ControllerHealth.connected);
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    reportHealth(ControllerHealth.disconnected);
    closeHealth();
  }

  /// Simulates the transport losing the session on its own - a heartbeat
  /// deadline, a socket close, or the TV being switched off at the wall.
  void dropSession() {
    _connected = false;
    reportHealth(ControllerHealth.disconnected);
  }

  @override
  bool get isConnected => _connected;

  @override
  Set<RemoteKey> get supportedKeys => RemoteKey.values.toSet();

  @override
  Future<CommandResult> sendKey(RemoteKey key) async =>
      _connected ? const CommandSent() : const CommandNotConnected();

  @override
  Future<CommandResult> sendText(String text) async =>
      _connected ? const CommandSent() : const CommandNotConnected();

  @override
  Future<CommandResult> launchApp(AppId appId) async =>
      _connected ? const CommandSent() : const CommandNotConnected();
}
