import '../exceptions/unsupported_device_exception.dart';
import '../models/app_id.dart';
import '../models/command_result.dart';
import '../models/device.dart';
import '../models/remote_key.dart';
import 'controller_health.dart';
import 'device_controller.dart';

/// Amazon Fire TV stub — returns UnsupportedDeviceException (Requirement 2.6).
class FireTvController with HealthReporting implements DeviceController {
  @override
  Future<void> connect() async =>
      throw UnsupportedDeviceException(DeviceType.fireTv);

  @override
  Future<void> disconnect() async {}

  @override
  Set<RemoteKey> get supportedKeys => const {};

  @override
  Future<CommandResult> sendKey(RemoteKey key) async =>
      CommandUnsupported(key.name);

  @override
  Future<CommandResult> sendText(String text) async =>
      const CommandUnsupported('text entry');

  @override
  Future<CommandResult> launchApp(AppId appId) async =>
      CommandUnsupported(appId.displayName);

  @override
  bool get isConnected => false;
}
