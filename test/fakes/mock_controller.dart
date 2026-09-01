import 'package:devicecontroller/core/app_logger.dart';
import 'package:devicecontroller/models/app_id.dart';
import 'package:devicecontroller/models/command_result.dart';
import 'package:devicecontroller/models/remote_key.dart';
import 'package:devicecontroller/controllers/controller_health.dart';
import 'package:devicecontroller/controllers/device_controller.dart';

/// A fake [DeviceController] for tests.
///
/// Previously shipped in lib/ and was selected in production by a 'mock-'
/// prefix on a user-influenceable device id.
class MockController with HealthReporting implements DeviceController {
  final String deviceName;
  bool _connected = false;

  MockController({required this.deviceName});

  @override
  Future<void> connect() async {
    // Simulate connection delay
    await Future.delayed(const Duration(milliseconds: 1500));
    _connected = true;
    reportHealth(ControllerHealth.connected);
    log.d('MockController: Successfully connected to $deviceName');
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    reportHealth(ControllerHealth.disconnected);
    closeHealth();
    log.d('MockController: Disconnected from $deviceName');
  }

  @override
  bool get isConnected => _connected;

  @override
  Set<RemoteKey> get supportedKeys => RemoteKey.values.toSet();

  @override
  Future<CommandResult> sendKey(RemoteKey key) async {
    if (!_connected) return const CommandNotConnected();
    await Future.delayed(const Duration(milliseconds: 100));
    log.d('MockController ($deviceName): Received remote key -> ${key.name}');
    return const CommandSent();
  }

  @override
  Future<CommandResult> sendText(String text) async {
    if (!_connected) return const CommandNotConnected();
    await Future.delayed(const Duration(milliseconds: 200));
    log.d('MockController ($deviceName): Received text input -> "$text"');
    return const CommandSent();
  }

  @override
  Future<CommandResult> launchApp(AppId appId) async {
    if (!_connected) return const CommandNotConnected();
    await Future.delayed(const Duration(milliseconds: 500));
    log.d('MockController ($deviceName): Launched app -> ${appId.displayName}');
    return const CommandSent();
  }
}
