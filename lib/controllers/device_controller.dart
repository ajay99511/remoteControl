import '../models/remote_key.dart';

/// Abstract interface for controlling a smart device.
///
/// Concrete implementations (e.g., [RokuController]) translate
/// [RemoteKey] presses and text input into protocol-specific
/// network commands.
abstract class DeviceController {
  /// Verify the device is reachable and establish a session.
  Future<void> connect();

  /// Tear down the session gracefully.
  Future<void> disconnect();

  /// Send a single remote-control key press to the device.
  Future<void> sendKey(RemoteKey key);

  /// Send a text string to the device (e.g., for search input).
  Future<void> sendText(String text);

  /// Whether the device is currently connected and reachable.
  bool get isConnected;
}
