import 'dart:async';

/// Whether a transport currently holds a usable session.
///
/// The `DeviceController` interface used to be one-directional: the app could
/// tell a transport what to do, but a transport had no way to say anything
/// back. So when a heartbeat deadline fired and the controller tore its own
/// session down, nothing reached the app, and the UI kept rendering
/// "CONNECTED" over a remote that silently dropped every press.
enum ControllerHealth {
  /// A session is established and commands can be delivered.
  connected,

  /// The session is gone. The app did not necessarily ask for this.
  disconnected,
}

/// Supplies the `health` stream required by `DeviceController`.
///
/// Shared rather than repeated because all seven implementations need exactly
/// this plumbing and it changes for exactly one reason.
mixin HealthReporting {
  final StreamController<ControllerHealth> _health =
      StreamController<ControllerHealth>.broadcast();

  Stream<ControllerHealth> get health => _health.stream;

  /// Announces a transition. Safe to call after [closeHealth].
  void reportHealth(ControllerHealth value) {
    if (!_health.isClosed) _health.add(value);
  }

  /// Releases the stream. Call from the controller's terminal teardown.
  void closeHealth() {
    if (!_health.isClosed) _health.close();
  }
}
