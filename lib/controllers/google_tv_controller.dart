import '../exceptions/unsupported_device_exception.dart';
import '../models/app_id.dart';
import '../models/command_result.dart';
import '../models/device.dart';
import '../models/remote_key.dart';
import 'device_controller.dart';

/// Google TV / Android TV stub — returns UnsupportedDeviceException (Requirement 2.7).
class GoogleTvController implements DeviceController {
  @override
  Future<void> connect() async =>
      throw UnsupportedDeviceException(DeviceType.googleTv);

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
