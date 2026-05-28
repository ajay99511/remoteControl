import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/device_controller.dart';
import '../controllers/fire_tv_controller.dart';
import '../controllers/google_tv_controller.dart';
import '../controllers/ir_controller.dart';
import '../controllers/lg_controller.dart';
import '../controllers/mock_controller.dart';
import '../controllers/roku_controller.dart';
import '../controllers/samsung_controller.dart';
import '../controllers/vizio_controller.dart';
import '../core/app_logger.dart';
import '../exceptions/unsupported_device_exception.dart';
import '../models/app_id.dart';
import '../models/device.dart';
import '../models/remote_key.dart';
import '../services/connectivity_service.dart';
import '../services/device_persistence_service.dart';

/// Connection status for the active device session.
enum ConnectionStatus { disconnected, connecting, connected, error }

/// Immutable state for the active device connection.
class DeviceConnectionState {
  final ConnectionStatus status;
  final Device? device;
  final String? errorMessage;

  const DeviceConnectionState({
    this.status = ConnectionStatus.disconnected,
    this.device,
    this.errorMessage,
  });

  DeviceConnectionState copyWith({
    ConnectionStatus? status,
    Device? device,
    String? errorMessage,
    bool clearError = false,
  }) =>
      DeviceConnectionState(
        status: status ?? this.status,
        device: device ?? this.device,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

/// Riverpod [Notifier] that manages the connection to a selected device.
class ConnectionNotifier extends Notifier<DeviceConnectionState> {
  DeviceController? _controller;
  int _retryCount = 0;
  static const _maxRetries = 4;
  static const _retryDelays = [1, 2, 4, 8]; // seconds

  late final DevicePersistenceService _persistence;
  late final ConnectivityService _connectivity;
  StreamSubscription? _connectivitySub;

  @override
  DeviceConnectionState build() {
    _persistence = ref.read(devicePersistenceProvider);
    _connectivity = ref.read(connectivityServiceProvider);
    
    _connectivitySub = _connectivity.onConnectivityChanged.listen(_onConnectivityChanged);
    
    ref.onDispose(() {
      _connectivitySub?.cancel();
      _controller?.disconnect();
    });

    _tryAutoReconnect();

    return const DeviceConnectionState();
  }

  Future<void> _tryAutoReconnect() async {
    final saved = await _persistence.loadDevice();
    if (saved != null) {
      log.d('ConnectionNotifier: Found saved device ${saved.name}, attempting auto-reconnect');
      await connect(saved);
    }
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.none)) {
      log.w('ConnectionNotifier: Network connectivity lost');
      state = state.copyWith(
        status: ConnectionStatus.error,
        errorMessage: 'Wi-Fi connection lost',
      );
    } else if (state.status == ConnectionStatus.error && state.device != null) {
      log.i('ConnectionNotifier: Connectivity restored, attempting reconnect');
      connect(state.device!);
    }
  }

  /// Connect to a discovered device.
  Future<void> connect(Device device) async {
    state = DeviceConnectionState(
      status: ConnectionStatus.connecting,
      device: device,
    );
    _retryCount = 0;
    await _connectWithBackoff(device);
  }

  Future<void> _connectWithBackoff(Device device) async {
    try {
      _controller = _buildController(device);
      await _controller!.connect();
      await _persistence.saveDevice(device);
      
      state = DeviceConnectionState(
        status: ConnectionStatus.connected,
        device: device,
      );
      _retryCount = 0;
      log.d('ConnectionNotifier: Successfully connected to ${device.name}');
    } catch (e) {
      if (_retryCount < _maxRetries) {
        final delay = _retryDelays[_retryCount];
        log.w('ConnectionNotifier: Connection failed, retrying in ${delay}s (Attempt ${_retryCount + 1}/$_maxRetries) — $e');
        _retryCount++;
        await Future.delayed(Duration(seconds: delay));
        await _connectWithBackoff(device);
      } else {
        log.e('ConnectionNotifier: Connection failed after $_maxRetries retries', e);
        state = DeviceConnectionState(
          status: ConnectionStatus.error,
          device: device,
          errorMessage: e.toString(),
        );
      }
    }
  }

  /// Disconnect from the current device.
  Future<void> disconnect() async {
    try {
      await _controller?.disconnect();
    } catch (e) {
      log.e('ConnectionNotifier: Error during disconnect', e);
    }
    _controller = null;
    await _persistence.clearDevice();
    state = const DeviceConnectionState();
  }

  /// Send a remote-control key press to the connected device.
  Future<void> sendKey(RemoteKey key) async {
    if (_controller == null || !_controller!.isConnected) return;
    try {
      await _controller!.sendKey(key);
    } catch (e) {
      log.e('ConnectionNotifier: sendKey failed', e);
    }
  }

  /// Send text input to the connected device.
  Future<void> sendText(String text) async {
    if (_controller == null || !_controller!.isConnected) return;
    try {
      await _controller!.sendText(text);
    } catch (e) {
      log.e('ConnectionNotifier: sendText failed', e);
    }
  }

  /// Launch a specific app on the connected device.
  Future<void> launchApp(AppId appId) async {
    if (_controller == null || !_controller!.isConnected) return;
    try {
      await _controller!.launchApp(appId);
    } catch (e) {
      log.e('ConnectionNotifier: launchApp failed', e);
    }
  }

  /// Factory method — instantiate the correct controller for the device type.
  DeviceController _buildController(Device device) {
    if (device.id.startsWith('mock-')) {
      return MockController(deviceName: device.name);
    }

    final persistence = ref.read(devicePersistenceProvider);

    return switch (device.type) {
      DeviceType.roku => RokuController(
          host: device.ip!,
          port: device.port ?? 8060,
        ),
      DeviceType.samsung => SamsungController(
          host: device.ip!,
          port: device.port ?? 8001,
          persistence: persistence,
        ),
      DeviceType.lg => LgController(
          host: device.ip!,
          port: device.port ?? 3000,
          persistence: persistence,
        ),
      DeviceType.vizio => VizioController(
          host: device.ip!,
          port: device.port ?? 7345,
        ),
      DeviceType.fireTv => FireTvController(),
      DeviceType.googleTv => GoogleTvController(),
      DeviceType.ir => IrController(brand: device.model),
      DeviceType.unknown => throw UnsupportedDeviceException(device.type),
    };
  }
}

/// Global provider for the device connection.
final connectionProvider =
    NotifierProvider<ConnectionNotifier, DeviceConnectionState>(
      ConnectionNotifier.new,
    );
