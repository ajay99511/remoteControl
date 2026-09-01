import 'dart:io';

import 'package:crypto/crypto.dart';

import '../services/device_persistence_service.dart';
import 'app_logger.dart';

/// Outcome of comparing a presented certificate against the pinned one.
enum CertificateVerdict {
  /// No pin recorded yet: trust this certificate and remember it.
  pinNew,

  /// Presented fingerprint matches the pin.
  trusted,

  /// Presented fingerprint contradicts the pin. Refuse, and do not downgrade.
  rejected,
}

/// The Trust-On-First-Use decision, kept pure so the security rule is testable
/// without a socket. [stored] is the pin from secure storage, [presented] the
/// SHA-256 of the certificate the device just offered.
CertificateVerdict verifyFingerprint({
  required String? stored,
  required String presented,
}) {
  if (stored == null) return CertificateVerdict.pinNew;
  return stored == presented
      ? CertificateVerdict.trusted
      : CertificateVerdict.rejected;
}

/// One TLS handshake's worth of pinning state.
///
/// Consumer TVs present self-signed certificates, so the default trust store
/// rejects them and the choice of whether to proceed is ours. This records
/// which choice was made, so the caller can distinguish "we refused this
/// certificate" from "this device has no TLS at all" - both surface as
/// HandshakeException, and conflating them is what made Samsung's pinning
/// unenforceable (audit C-2).
///
/// Shared by Samsung and Vizio. It stayed inside SamsungController while there
/// was only one consumer.
class PinningSession {
  final String host;
  final String? _stored;

  CertificateVerdict? _verdict;
  String? _presented;

  PinningSession({required this.host, required String? stored})
    : _stored = stored;

  /// True when this session refused the certificate the device offered.
  /// The caller must fail rather than retry over a plaintext transport.
  bool get wasRejected => _verdict == CertificateVerdict.rejected;

  /// SHA-256 of the certificate this session last evaluated, or null if no
  /// handshake has happened yet.
  String? get presentedFingerprint => _presented;

  /// Applies the TOFU decision to one certificate's DER bytes.
  ///
  /// Separated from [createClient] so the security rule can be exercised
  /// without a TLS handshake - dart:io exposes badCertificateCallback as a
  /// setter only, so a client's policy is otherwise unobservable.
  CertificateVerdict evaluate(List<int> der) {
    final fingerprint = sha256.convert(der).toString();
    _presented = fingerprint;
    _verdict = verifyFingerprint(stored: _stored, presented: fingerprint);

    switch (_verdict!) {
      case CertificateVerdict.pinNew:
        log.i('PinningSession: pinning new certificate for $host');
      case CertificateVerdict.trusted:
        break;
      case CertificateVerdict.rejected:
        log.e('PinningSession: TOFU mismatch for $host - refusing');
    }
    return _verdict!;
  }

  /// An [HttpClient] that applies the TOFU decision to this host.
  HttpClient createClient() =>
      HttpClient()
        ..badCertificateCallback = (cert, certHost, certPort) =>
            evaluate(cert.der) != CertificateVerdict.rejected;

  /// Persists a newly seen pin.
  ///
  /// Call only after the handshake has actually succeeded: recording a
  /// fingerprint for a connection that then failed would pin a certificate we
  /// never really talked to. Awaited so a storage failure is not dropped.
  Future<void> commit(DevicePersistenceService persistence) async {
    if (_verdict == CertificateVerdict.pinNew && _presented != null) {
      await persistence.saveCertFingerprint(host, _presented!);
    }
  }
}
