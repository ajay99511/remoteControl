import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devicecontroller/providers/scanner_provider.dart';

import '../fakes/fake_datagram_socket.dart';

void main() {
  late FakeDatagramSocket socket;

  /// A container whose network is entirely under the test's control: mDNS off,
  /// UDP socket faked. Nothing here touches the real network.
  ProviderContainer makeContainer() => ProviderContainer(
        overrides: [
          mdnsEnabledProvider.overrideWithValue(false),
          ssdpSocketBinderProvider.overrideWithValue(() async => socket),
        ],
      );

  setUp(() => socket = FakeDatagramSocket());

  group('ScannerNotifier SSDP probe', () {
    test('sends three M-SEARCH probes 500ms apart', () {
      fakeAsync((async) {
        final container = makeContainer();
        addTearDown(container.dispose);

        container.read(scannerProvider.notifier).startScan();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));

        expect(socket.sent, hasLength(3),
            reason: 'a single M-SEARCH is routinely dropped on Wi-Fi');
        expect(socket.broadcastEnabled, isTrue);
      });
    });

    test('closes the socket when the listen window expires', () {
      fakeAsync((async) {
        final container = makeContainer();
        addTearDown(container.dispose);

        container.read(scannerProvider.notifier).startScan();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));
        expect(socket.closed, isFalse);

        async.elapse(const Duration(seconds: 10));

        expect(socket.closed, isTrue);
      });
    });
  });

  group('ScannerNotifier lifecycle', () {
    test('clears isScanning when the scan window closes', () {
      fakeAsync((async) {
        final container = makeContainer();
        addTearDown(container.dispose);

        container.read(scannerProvider.notifier).startScan();
        async.flushMicrotasks();
        expect(container.read(scannerProvider).isScanning, isTrue);

        async.elapse(const Duration(seconds: 11));

        expect(container.read(scannerProvider).isScanning, isFalse);
      });
    });

    test('closes the socket on dispose instead of leaking it', () {
      fakeAsync((async) {
        final container = makeContainer();

        container.read(scannerProvider.notifier).startScan();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));
        expect(socket.closed, isFalse);

        // The user navigates away mid-scan. The socket used to stay bound and
        // listening for the rest of its 8-second window, once per rescan.
        container.dispose();

        expect(socket.closed, isTrue);
      });
    });

    test('disposing mid-scan does not write to a dead notifier', () {
      fakeAsync((async) {
        final container = makeContainer();

        container.read(scannerProvider.notifier).startScan();
        async.flushMicrotasks();
        container.dispose();

        // The 10s deadline used to wake up afterwards and assign state on a
        // disposed Notifier, throwing StateError.
        expect(
          () => async.elapse(const Duration(seconds: 30)),
          returnsNormally,
        );
      });
    });

    test('stopScan releases the socket', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(scannerProvider.notifier);
      await notifier.startScan();
      await notifier.stopScan();

      expect(socket.closed, isTrue);
      expect(container.read(scannerProvider).isScanning, isFalse);
    });

    test('a rescan does not leave the previous socket open', () async {
      final first = socket;
      final container = makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(scannerProvider.notifier);
      await notifier.startScan();
      await notifier.stopScan();

      socket = FakeDatagramSocket();
      await notifier.startScan();

      expect(first.closed, isTrue, reason: 'the first socket must be released');
    });
  });
}
