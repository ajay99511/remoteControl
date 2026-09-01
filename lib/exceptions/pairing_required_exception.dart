/// Thrown when a device is reachable but refuses commands until the user
/// completes its pairing flow.
///
/// Distinct from a generic connection failure because it is *not* retryable:
/// retrying without a token produces the same 401 forever. It is also not a
/// bug - it is an expected outcome that the UI is meant to act on by starting
/// the pairing flow.
class PairingRequiredException implements Exception {
  final String host;

  const PairingRequiredException(this.host);

  String get message =>
      'This TV needs to be paired before it will accept commands. '
      'Check the TV screen for a PIN.';

  @override
  String toString() => 'PairingRequiredException($host): $message';
}
