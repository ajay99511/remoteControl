import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../exceptions/unsupported_device_exception.dart';
import '../models/device.dart';
import '../services/device_persistence_service.dart';
import 'device_controller.dart';
import 'fire_tv_controller.dart';
import 'google_tv_controller.dart';
import 'ir_controller.dart';
import 'lg_controller.dart';
import 'roku_controller.dart';
import 'samsung_controller.dart';
import 'vizio_controller.dart';

/// Builds the transport for a device.
///
/// Injected rather than called directly so tests can substitute a fake. While
/// this lived as a private method on ConnectionNotifier the provider tests had
/// no way to avoid real controllers, and resorted to opening a real socket to
/// 0.0.0.0 and waiting out four genuine 3-second timeouts.
typedef DeviceControllerFactory = DeviceController Function(Device);

/// The production factory.
DeviceController buildDeviceController(
  Device device,
  DevicePersistenceService persistence,
) {
  return switch (device.type) {
    DeviceType.roku => RokuController(
      host: _requireHost(device),
      port: device.port ?? kDefaultPorts[DeviceType.roku]!,
    ),
    DeviceType.samsung => SamsungController(
      host: _requireHost(device),
      port: device.port ?? kDefaultPorts[DeviceType.samsung]!,
      persistence: persistence,
      credentialKey: device.credentialKey,
    ),
    DeviceType.lg => LgController(
      host: _requireHost(device),
      port: device.port ?? kDefaultPorts[DeviceType.lg]!,
      persistence: persistence,
      credentialKey: device.credentialKey,
    ),
    DeviceType.vizio => VizioController(
      host: _requireHost(device),
      port: device.port ?? kDefaultPorts[DeviceType.vizio]!,
      persistence: persistence,
      credentialKey: device.credentialKey,
    ),
    DeviceType.fireTv => FireTvController(),
    DeviceType.googleTv => GoogleTvController(),
    DeviceType.ir => IrController(brand: device.model),
    DeviceType.unknown => throw UnsupportedDeviceException(device.type),
  };
}

/// Replaces the `device.ip!` force-unwraps that would crash on a persisted
/// device with no address - reachable, since [Device.ip] is nullable and
/// fromJson will happily produce one.
String _requireHost(Device device) {
  final host = device.ip;
  if (host == null || host.isEmpty) {
    throw ArgumentError.value(
      device.ip,
      'device.ip',
      'a ${device.type.name} device needs a network address',
    );
  }
  return host;
}

final deviceControllerFactoryProvider = Provider<DeviceControllerFactory>((
  ref,
) {
  final persistence = ref.watch(devicePersistenceProvider);
  return (device) => buildDeviceController(device, persistence);
});
