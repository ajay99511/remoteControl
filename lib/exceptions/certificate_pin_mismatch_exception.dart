/// Thrown when a device presents a TLS certificate whose SHA-256 fingerprint
/// differs from the one pinned on first use (TOFU).
///
/// This is deliberately a distinct type rather than a generic failure: it is
/// the one connection error that must NEVER be retried and must never fall
/// back to a plaintext transport, because a mismatch is exactly the signal
/// that pinning exists to detect.
class CertificatePinMismatchException implements Exception {
  final String host;

  const CertificatePinMismatchException(this.host);

  String get message =>
      "This TV's security certificate has changed since you last connected. "
      'It may not be your TV. Remove and re-pair the device if you replaced it.';

  @override
  String toString() => 'CertificatePinMismatchException($host): $message';
}
