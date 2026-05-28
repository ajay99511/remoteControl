import '../exceptions/unsupported_device_exception.dart';
import '../models/app_id.dart';
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
  Future<void> sendKey(RemoteKey key) async =>
      throw UnsupportedDeviceException(DeviceType.googleTv);

  @override
  Future<void> sendText(String text) async =>
      throw UnsupportedDeviceException(DeviceType.googleTv);

  @override
  Future<void> launchApp(AppId appId) async =>
      throw UnsupportedDeviceException(DeviceType.googleTv);

  @override
  bool get isConnected => false;
}
