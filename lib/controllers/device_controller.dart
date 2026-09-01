import 'controller_health.dart';
import '../models/app_id.dart';
import '../models/command_result.dart';
import '../models/remote_key.dart';

/// Abstract interface for controlling a smart device.
///
/// Concrete implementations (e.g., [RokuController]) translate
/// [RemoteKey] presses and text input into protocol-specific
/// network commands.
abstract class DeviceController {
  /// Verify the device is reachable and establish a session.
  ///
  /// Throws on failure. Callers distinguish retryable transport errors from
  /// permanent ones (`UnsupportedDeviceException`,
  /// `CertificatePinMismatchException`, `PairingRequiredException`) by type.
  Future<void> connect();

  /// Tear down the session gracefully.
  Future<void> disconnect();

  /// Send a single remote-control key press to the device.
  Future<CommandResult> sendKey(RemoteKey key);

  /// Send a text string to the device (e.g., for search input).
  Future<CommandResult> sendText(String text);

  /// Launch a specific app on the device.
  Future<CommandResult> launchApp(AppId appId);

  /// Keys this transport can actually deliver.
  ///
  /// Lets the UI disable a control rather than accept a press and drop it.
  Set<RemoteKey> get supportedKeys;

  /// Emits whenever the transport's session state changes, including drops
  /// the app did not initiate (heartbeat timeout, socket close, TV powered
  /// off). Without this the app cannot notice a session it did not end.
  Stream<ControllerHealth> get health;

  /// Whether the device is currently connected and reachable.
  bool get isConnected;
}
