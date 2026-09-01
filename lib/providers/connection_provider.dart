import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/controller_health.dart';
import '../controllers/device_controller.dart';
import '../controllers/device_controller_factory.dart';
import '../core/app_logger.dart';
import '../exceptions/certificate_pin_mismatch_exception.dart';
import '../exceptions/pairing_required_exception.dart';
import '../exceptions/unsupported_device_exception.dart';
import '../models/app_id.dart';
import '../models/command_result.dart';
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
  }) => DeviceConnectionState(
    status: status ?? this.status,
    device: device ?? this.device,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
  );
}

/// Riverpod [Notifier] that manages the connection to a selected device.
class ConnectionNotifier extends Notifier<DeviceConnectionState> {
  DeviceController? _controller;

  static const _maxRetries = 4;
  static const _baseDelay = Duration(seconds: 1);

  /// Identifies the current attempt chain. Any newer call to [connect] wins,
  /// so a chain that has been superseded stops instead of racing the winner
  /// for the right to assign state.
  int _attemptEpoch = 0;
  bool _disposed = false;
  final Random _rng = Random();

  late final DevicePersistenceService _persistence;
  late final ConnectivityService _connectivity;
  late final DeviceControllerFactory _makeController;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  StreamSubscription<ControllerHealth>? _healthSub;

  @override
  DeviceConnectionState build() {
    _persistence = ref.read(devicePersistenceProvider);
    _connectivity = ref.read(connectivityServiceProvider);
    _makeController = ref.read(deviceControllerFactoryProvider);

    _connectivitySub = _connectivity.onConnectivityChanged.listen(
      _onConnectivityChanged,
    );

    ref.onDispose(() {
      _disposed = true;
      _connectivitySub?.cancel();
      _healthSub?.cancel();
      _controller?.disconnect();
    });

    _tryAutoReconnect();

    return const DeviceConnectionState();
  }

  Future<void> _tryAutoReconnect() async {
    final saved = await _persistence.loadDevice();
    if (saved != null) {
      log.d(
        'ConnectionNotifier: Found saved device ${saved.name}, attempting auto-reconnect',
      );
      await connect(saved);
    }
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    if (_disposed) return;

    // Anything other than wifi/ethernet cannot reach a device on the LAN.
    // Testing only for `none` meant a drop to mobile data read as "still
    // online", and every foreground on cellular started a full retry chain
    // against an unreachable private address.
    if (!canReachLocalNetwork(results)) {
      if (state.status == ConnectionStatus.disconnected) return;
      log.w('ConnectionNotifier: no local network transport available');
      state = state.copyWith(
        status: ConnectionStatus.error,
        errorMessage: 'Not on a Wi-Fi network.',
      );
      return;
    }

    if (state.status == ConnectionStatus.error && state.device != null) {
      log.i('ConnectionNotifier: local network back, attempting reconnect');
      unawaited(connect(state.device!));
    }
  }

  /// Connect to a discovered device.
  Future<void> connect(Device device) async {
    state = DeviceConnectionState(
      status: ConnectionStatus.connecting,
      device: device,
    );
    await _connectWithBackoff(device);
  }

  /// Whether another attempt could plausibly succeed.
  ///
  /// These three are deterministic and permanent: the device type has no
  /// implementation, the certificate contradicts its pin, or the TV wants a
  /// pairing code. Retrying any of them produces the identical failure four
  /// more times while the user waits 15 seconds for news we already had.
  static bool _isRetryable(Object e) =>
      e is! UnsupportedDeviceException &&
      e is! CertificatePinMismatchException &&
      e is! PairingRequiredException &&
      // A device with no address cannot acquire one by waiting.
      e is! ArgumentError;

  /// A message safe to put in front of a user: no stack frames, no exception
  /// class names, and an action to take where one exists.
  static String _userMessage(Object e) => switch (e) {
    UnsupportedDeviceException() => e.message,
    CertificatePinMismatchException() => e.message,
    PairingRequiredException() => e.message,
    TimeoutException() =>
      'The device did not respond. Check that it is powered on and on '
          'this Wi-Fi network.',
    SocketException() => 'Could not reach the device on this network.',
    _ => 'Could not connect to the device.',
  };

  /// Attempts to connect, retrying transient failures with full-jitter
  /// exponential backoff.
  ///
  /// A loop rather than recursion: the previous version recursed once per
  /// retry, grew the stack, and shared a single mutable _retryCount across any
  /// number of concurrent chains. ConnectivityService synthesises a
  /// restore event on every foreground resume, so concurrent chains were
  /// routine, not exotic.
  Future<void> _connectWithBackoff(Device device) async {
    final epoch = ++_attemptEpoch;

    for (var attempt = 0; attempt <= _maxRetries; attempt++) {
      if (_isSuperseded(epoch)) return;

      try {
        final controller = _makeController(device);
        _controller = controller;
        await controller.connect();
        await _persistence.saveDevice(device);
        // Remembered only once it has actually answered: a device that never
        // connected is a typo, not something to offer on the next scan.
        await _persistence.rememberDevice(device);

        if (_isSuperseded(epoch)) return;
        _watchHealth(controller, device);
        state = DeviceConnectionState(
          status: ConnectionStatus.connected,
          device: device,
        );
        log.d('ConnectionNotifier: Successfully connected to ${device.name}');
        return;
      } catch (e, s) {
        final lastAttempt = attempt == _maxRetries;
        if (!_isRetryable(e) || lastAttempt) {
          log.e(
            'ConnectionNotifier: Connection to ${device.name} failed',
            e,
            s,
          );
          if (_isSuperseded(epoch)) return;
          state = DeviceConnectionState(
            status: ConnectionStatus.error,
            device: device,
            errorMessage: _userMessage(e),
          );
          return;
        }

        // Full jitter (AWS "Exponential Backoff and Jitter"): a delay drawn
        // from [0, ceiling] rather than the ceiling itself, so retries from
        // multiple clients do not re-synchronise.
        final ceiling = _baseDelay * (1 << attempt);
        log.w(
          'ConnectionNotifier: attempt ${attempt + 1}/$_maxRetries for '
          '${device.name} failed, backing off - $e',
        );
        await Future<void>.delayed(
          Duration(milliseconds: _rng.nextInt(ceiling.inMilliseconds + 1)),
        );
      }
    }
  }

  /// True when this chain must stop touching state: either the notifier is
  /// gone, or a newer connect attempt has taken over.
  bool _isSuperseded(int epoch) => _disposed || epoch != _attemptEpoch;

  /// Reflect transport-initiated session loss in app state.
  ///
  /// Without this the controller could tear its own session down - on a
  /// heartbeat timeout, a socket close, or the TV being switched off - and
  /// the UI would carry on showing CONNECTED over a remote that dropped every
  /// press.
  void _watchHealth(DeviceController controller, Device device) {
    _healthSub?.cancel();
    _healthSub = controller.health.listen((health) {
      if (health != ControllerHealth.disconnected) return;
      if (state.status != ConnectionStatus.connected) return;
      log.w('ConnectionNotifier: ${device.name} dropped the session');
      state = DeviceConnectionState(
        status: ConnectionStatus.error,
        device: device,
        errorMessage: 'Lost connection to ${device.name}.',
      );
    });
  }

  /// Disconnect from the current device.
  Future<void> disconnect() async {
    await _healthSub?.cancel();
    _healthSub = null;
    try {
      await _controller?.disconnect();
    } catch (e) {
      log.e('ConnectionNotifier: Error during disconnect', e);
    }
    _controller = null;
    await _persistence.clearDevice();
    state = const DeviceConnectionState();
  }

  /// Keys the active transport can actually deliver.
  Set<RemoteKey> get supportedKeys => _controller?.supportedKeys ?? const {};

  /// Send a remote-control key press to the connected device.
  Future<CommandResult> sendKey(RemoteKey key) =>
      _run('sendKey ${key.name}', (c) => c.sendKey(key));

  /// Send text input to the connected device.
  Future<CommandResult> sendText(String text) =>
      _run('sendText', (c) => c.sendText(text));

  /// Launch a specific app on the connected device.
  Future<CommandResult> launchApp(AppId appId) =>
      _run('launchApp ${appId.name}', (c) => c.launchApp(appId));

  /// Runs one command and reports the outcome instead of swallowing it.
  ///
  /// A failure also moves the session into the error state, so a transport
  /// that has died stops presenting itself as connected.
  Future<CommandResult> _run(
    String label,
    Future<CommandResult> Function(DeviceController) action,
  ) async {
    final controller = _controller;
    if (controller == null || !controller.isConnected) {
      return const CommandNotConnected();
    }
    try {
      final result = await action(controller);
      if (result is CommandFailed) {
        log.e(
          'ConnectionNotifier: $label failed',
          result.cause,
          result.stackTrace,
        );
        state = state.copyWith(
          status: ConnectionStatus.error,
          errorMessage: _userMessage(result.cause),
        );
      }
      return result;
    } catch (e, s) {
      log.e('ConnectionNotifier: $label threw', e, s);
      state = state.copyWith(
        status: ConnectionStatus.error,
        errorMessage: _userMessage(e),
      );
      return CommandFailed(e, s);
    }
  }
}

/// Global provider for the device connection.
final connectionProvider =
    NotifierProvider<ConnectionNotifier, DeviceConnectionState>(
      ConnectionNotifier.new,
    );
