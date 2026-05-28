import '../core/app_logger.dart';
import '../models/app_id.dart';
import '../models/remote_key.dart';
import 'device_controller.dart';

/// A mock [DeviceController] that simulates network connections
/// and remote control interactions for testing purposes.
class MockController implements DeviceController {
  final String deviceName;
  bool _connected = false;

  MockController({required this.deviceName});

  @override
  Future<void> connect() async {
    // Simulate connection delay
    await Future.delayed(const Duration(milliseconds: 1500));
    _connected = true;
    log.d('MockController: Successfully connected to $deviceName');
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    log.d('MockController: Disconnected from $deviceName');
  }

  @override
  bool get isConnected => _connected;

  @override
  Future<void> sendKey(RemoteKey key) async {
    if (!_connected) return;

    // Simulate small latency
    await Future.delayed(const Duration(milliseconds: 100));

    // Log the interaction instead of throwing network errors
    log.d('MockController ($deviceName): Received remote key -> ${key.name}');
  }

  @override
  Future<void> sendText(String text) async {
    if (!_connected) return;

    // Simulate text input latency
    await Future.delayed(const Duration(milliseconds: 200));
    log.d('MockController ($deviceName): Received text input -> "$text"');
  }

  @override
  Future<void> launchApp(AppId appId) async {
    if (!_connected) return;

    // Simulate app launch latency
    await Future.delayed(const Duration(milliseconds: 500));
    log.d('MockController ($deviceName): Launched app -> ${appId.displayName}');
  }
}
