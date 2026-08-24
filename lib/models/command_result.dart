/// The outcome of sending one command to a device.
///
/// Commands previously returned `Future<void>`, a signature that can express
/// "I finished" but not "I failed" or "I cannot do that". Every controller
/// therefore caught its own exception, wrote a log line and returned normally,
/// so no failure could reach the user - the app confirmed with a haptic and
/// did nothing.
///
/// [CommandUnsupported] and [CommandNotConnected] are *expected* outcomes and
/// belong in the return type rather than in exception control flow; only
/// [CommandFailed] represents something going wrong.
sealed class CommandResult {
  const CommandResult();

  /// True when the device actually received the command.
  bool get isSuccess => this is CommandSent;
}

/// The command was handed to the transport successfully.
final class CommandSent extends CommandResult {
  const CommandSent();
}

/// This transport has no mapping for the request - for example a D-pad arrow
/// on webOS, or text entry on Vizio SmartCast. Not an error: the UI should
/// say so, and ideally not offer the control at all.
final class CommandUnsupported extends CommandResult {
  /// What was unsupported, named for a human ('Left', 'Netflix').
  final String what;

  const CommandUnsupported(this.what);
}

/// The command arrived while no session was established.
final class CommandNotConnected extends CommandResult {
  const CommandNotConnected();
}

/// The command reached the transport and failed there.
final class CommandFailed extends CommandResult {
  final Object cause;
  final StackTrace stackTrace;

  const CommandFailed(this.cause, this.stackTrace);
}
