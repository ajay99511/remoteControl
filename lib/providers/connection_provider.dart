import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/device_controller.dart';
import '../controllers/mock_controller.dart';
import '../controllers/roku_controller.dart';
import '../models/device.dart';
import '../models/remote_key.dart';

/// Connection status for the active device session.
enum ConnectionStatus { disconnected, connecting, connected, error }

/// Immutable state for the active device connection.
class DeviceConnectionState {
  final ConnectionStatus status;
  final Device? device;
  final DeviceController? controller;
  final String? errorMessage;

  const DeviceConnectionState({
    this.status = ConnectionStatus.disconnected,
    this.device,
    this.controller,
    this.errorMessage,
  });

  DeviceConnectionState copyWith({
    ConnectionStatus? status,
    Device? device,
    DeviceController? controller,
    String? errorMessage,
  }) => DeviceConnectionState(
    status: status ?? this.status,
    device: device ?? this.device,
    controller: controller ?? this.controller,
    errorMessage: errorMessage,
  );
}

/// Riverpod [Notifier] that manages the connection to a selected device.
///
/// Instantiates the appropriate [DeviceController] based on the device
/// type, establishes the connection, and provides methods for sending
/// remote-control commands.
class ConnectionNotifier extends Notifier<DeviceConnectionState> {
  @override
  DeviceConnectionState build() => const DeviceConnectionState();

  /// Connect to a discovered device.
  Future<void> connect(Device device) async {
    state = DeviceConnectionState(
      status: ConnectionStatus.connecting,
      device: device,
    );

    try {
      final controller = _buildController(device);
      await controller.connect();
      state = DeviceConnectionState(
        status: ConnectionStatus.connected,
        device: device,
        controller: controller,
      );
      debugPrint('ConnectionNotifier: Connected to ${device.name}');
    } catch (e) {
      debugPrint('ConnectionNotifier: Connection failed — $e');
      state = DeviceConnectionState(
        status: ConnectionStatus.error,
        device: device,
        errorMessage: e.toString(),
      );
    }
  }

  /// Disconnect from the current device.
  Future<void> disconnect() async {
    try {
      await state.controller?.disconnect();
    } catch (e) {
      debugPrint('ConnectionNotifier: Error during disconnect — $e');
    }
    state = const DeviceConnectionState();
  }

  /// Send a remote-control key press to the connected device.
  Future<void> sendKey(RemoteKey key) async {
    if (state.controller == null || !state.controller!.isConnected) return;
    try {
      await state.controller!.sendKey(key);
    } catch (e) {
      debugPrint('ConnectionNotifier: sendKey failed — $e');
    }
  }

  /// Send text input to the connected device.
  Future<void> sendText(String text) async {
    if (state.controller == null || !state.controller!.isConnected) return;
    try {
      await state.controller!.sendText(text);
    } catch (e) {
      debugPrint('ConnectionNotifier: sendText failed — $e');
    }
  }

  /// Factory method — instantiate the correct controller for the device type.
  DeviceController _buildController(Device device) {
    if (device.id.startsWith('mock-')) {
      return MockController(deviceName: device.name);
    }

    switch (device.type) {
      case 'roku':
        return RokuController(
          host: device.ip ?? device.id,
          port: device.port ?? 8060,
        );
      default:
        // For now, treat any unknown device as a Roku target
        // (user can connect via IP to a Roku on port 8060).
        return RokuController(
          host: device.ip ?? device.id,
          port: device.port ?? 8060,
        );
    }
  }
}

/// Global provider for the device connection.
final connectionProvider =
    NotifierProvider<ConnectionNotifier, DeviceConnectionState>(
      ConnectionNotifier.new,
    );
