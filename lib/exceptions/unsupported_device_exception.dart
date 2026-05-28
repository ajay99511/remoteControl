import '../models/device.dart';

/// Thrown when no DeviceController exists for a given DeviceType.
class UnsupportedDeviceException implements Exception {
  final DeviceType deviceType;

  const UnsupportedDeviceException(this.deviceType);

  String get message =>
      'No controller available for device type: ${deviceType.name}. '
      'This device is not yet supported.';

  @override
  String toString() => 'UnsupportedDeviceException: $message';
}
