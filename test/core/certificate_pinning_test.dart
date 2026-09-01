import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:devicecontroller/core/certificate_pinning.dart';

import '../controllers/vizio_controller_test.mocks.dart';

void main() {
  final certA = utf8.encode('certificate-a');
  final certB = utf8.encode('certificate-b');

  /// The fingerprint a session derives for [der], as production would.
  String fingerprintOf(List<int> der) {
    final probe = PinningSession(host: 'probe', stored: null)..evaluate(der);
    return probe.presentedFingerprint!;
  }

  group('verifyFingerprint', () {
    test('pins on first contact when nothing is stored', () {
      expect(
        verifyFingerprint(stored: null, presented: 'aa'),
        CertificateVerdict.pinNew,
      );
    });

    test('trusts a certificate matching the stored pin', () {
      expect(
        verifyFingerprint(stored: 'aa', presented: 'aa'),
        CertificateVerdict.trusted,
      );
    });

    test('rejects a certificate contradicting the stored pin', () {
      expect(
        verifyFingerprint(stored: 'aa', presented: 'bb'),
        CertificateVerdict.rejected,
      );
    });
  });

  group('PinningSession', () {
    late MockDevicePersistenceService persistence;

    setUp(() => persistence = MockDevicePersistenceService());

    test('reports no rejection before any handshake', () {
      final session = PinningSession(host: 'tv', stored: 'aa');

      expect(session.wasRejected, isFalse);
      expect(session.presentedFingerprint, isNull);
    });

    test('pins an unseen certificate and records it on commit', () async {
      final session = PinningSession(host: 'tv', stored: null);

      expect(session.evaluate(certA), CertificateVerdict.pinNew);
      expect(session.wasRejected, isFalse);

      await session.commit(persistence);

      verify(
        persistence.saveCertFingerprint('tv', session.presentedFingerprint!),
      ).called(1);
    });

    test('trusts the same certificate on a later connection', () {
      final session = PinningSession(host: 'tv', stored: fingerprintOf(certA));

      expect(session.evaluate(certA), CertificateVerdict.trusted);
      expect(session.wasRejected, isFalse);
    });

    test('refuses a substituted certificate and re-pins nothing', () async {
      final session = PinningSession(host: 'tv', stored: fingerprintOf(certA));

      // The MITM case: a different certificate for a host already met. It
      // must not be accepted, and must not overwrite the good pin.
      expect(session.evaluate(certB), CertificateVerdict.rejected);
      expect(session.wasRejected, isTrue);

      await session.commit(persistence);

      verifyNever(persistence.saveCertFingerprint(any, any));
    });

    test('commits nothing when the certificate was already trusted', () async {
      final session = PinningSession(host: 'tv', stored: fingerprintOf(certA))
        ..evaluate(certA);

      await session.commit(persistence);

      verifyNever(persistence.saveCertFingerprint(any, any));
    });

    test('derives a stable fingerprint for the same bytes', () {
      expect(fingerprintOf(certA), fingerprintOf(certA));
      expect(fingerprintOf(certA), isNot(fingerprintOf(certB)));
    });
  });
}
