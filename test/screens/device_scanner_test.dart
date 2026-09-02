import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:devicecontroller/models/device.dart';
import 'package:devicecontroller/controllers/device_controller_factory.dart';
import 'package:devicecontroller/providers/connection_provider.dart';
import 'package:devicecontroller/providers/scanner_provider.dart';
import 'package:devicecontroller/screens/device_scanner.dart';
import 'package:devicecontroller/services/connectivity_service.dart';
import 'package:devicecontroller/services/device_persistence_service.dart';
import 'package:devicecontroller/services/ssdp.dart';

import '../fakes/fake_controller.dart';
import '../fakes/fake_datagram_socket.dart';
import '../providers/connection_provider_test.mocks.dart';

const _device = Device(
  id: 'ssdp:abc',
  name: 'Living Room Roku',
  type: DeviceType.roku,
  model: 'Ultra',
  ip: '192.168.1.50',
  port: 8060,
  uid: 'ssdp:abc',
);

void main() {
  late MockDevicePersistenceService persistence;
  late MockConnectivityService connectivity;

  setUp(() {
    persistence = MockDevicePersistenceService();
    connectivity = MockConnectivityService();
    when(
      connectivity.onConnectivityChanged,
    ).thenAnswer((_) => const Stream.empty());
    when(persistence.loadDevice()).thenAnswer((_) async => null);
  });

  Future<ProviderContainer> pump(
    WidgetTester tester,
    ScannerState state,
  ) async {
    final container = ProviderContainer(
      overrides: [
        devicePersistenceProvider.overrideWithValue(persistence),
        connectivityServiceProvider.overrideWithValue(connectivity),
        mdnsEnabledProvider.overrideWithValue(false),
        ssdpSocketBinderProvider.overrideWithValue(
          () async => FakeDatagramSocket(),
        ),
        scannerProvider.overrideWith(() => _StubScanner(state)),
        // No real controller, so a tap never opens a socket.
        deviceControllerFactoryProvider.overrideWithValue(
          (_) => FakeController(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DeviceScannerScreen()),
      ),
    );
    await tester.pump();
    return container;
  }

  Future<void> teardownTree(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  group('remembered devices on the discovery screen', () {
    testWidgets('a device restored from storage is marked as such', (
      tester,
    ) async {
      await pump(
        tester,
        const ScannerState(devices: [_device], restored: {'ssdp:abc'}),
      );

      // Showing it immediately is the point, but an entry the network has not
      // confirmed must not look identical to one that just answered.
      expect(find.text('Saved'), findsOneWidget);

      await teardownTree(tester);
    });

    testWidgets('a device seen on the network carries no marker', (
      tester,
    ) async {
      await pump(tester, const ScannerState(devices: [_device]));

      expect(find.text('Saved'), findsNothing);

      await teardownTree(tester);
    });

    testWidgets('the marker is announced, not only drawn', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        const ScannerState(devices: [_device], restored: {'ssdp:abc'}),
      );

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.button == true &&
              (w.properties.label ?? '').contains('not seen on this network'),
        ),
        findsOneWidget,
        reason: 'a screen reader user gets the same warning as a sighted one',
      );

      handle.dispose();
      await teardownTree(tester);
    });
  });

  group('devices this app cannot drive', () {
    const chromecast = Device(
      id: 'mdns:_googlecast._tcp/Kitchen',
      name: 'Kitchen speaker',
      type: DeviceType.googleTv,
      model: 'googlecast',
      ip: '192.168.1.70',
      port: 8009,
      uid: 'mdns:_googlecast._tcp/Kitchen',
    );

    testWidgets('are marked instead of looking connectable', (tester) async {
      await pump(tester, const ScannerState(devices: [chromecast]));

      // Every _googlecast._tcp responder is discovered, and none of them can
      // be controlled: GoogleTvController.connect() throws on its first line.
      expect(find.text('Not supported'), findsOneWidget);

      await teardownTree(tester);
    });

    testWidgets('do not start a connection that cannot succeed', (
      tester,
    ) async {
      final container = await pump(
        tester,
        const ScannerState(devices: [chromecast]),
      );

      await tester.tap(find.text('Kitchen speaker'));
      await tester.pump();

      expect(
        container.read(connectionProvider).status,
        ConnectionStatus.disconnected,
        reason:
            'making the user wait out a retry chain to be told what we knew '
            'before they tapped is a worse answer than saying so up front',
      );

      await teardownTree(tester);
    });

    testWidgets('say why, rather than doing nothing at all', (tester) async {
      await pump(tester, const ScannerState(devices: [chromecast]));

      await tester.tap(find.text('Kitchen speaker'));
      await tester.pump();

      // A row that swallows the tap reads as broken; the user needs the
      // reason. Asserting the wording matters: before this change a tap
      // produced a "Connection failed" snackbar, which is the same shape of
      // evidence for an entirely different claim.
      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.textContaining('not supported', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('Connection failed'), findsNothing);

      await teardownTree(tester);
    });

    testWidgets('a controllable device still connects on tap', (tester) async {
      final container = await pump(
        tester,
        const ScannerState(devices: [_device]),
      );

      await tester.tap(find.text('Living Room Roku'));
      await tester.pump();

      expect(
        container.read(connectionProvider).status,
        isNot(ConnectionStatus.disconnected),
        reason: 'the ordinary path must be untouched',
      );

      await teardownTree(tester);
    });
  });

  group('when a scan finds nothing', () {
    testWidgets('names the things that are actually worth checking', (
      tester,
    ) async {
      await pump(tester, const ScannerState());

      // "Ensure you share the same Wi-Fi network" was the whole of the advice,
      // and it is the one thing a user has usually already done. The causes
      // that actually bite are invisible from the phone: a guest SSID or a
      // separate IoT band that looks like the same network, client isolation,
      // or a TV refusing external control.
      expect(find.textContaining('guest'), findsOneWidget);
      expect(find.textContaining('Manual IP'), findsWidgets);

      // No companion test for "not shown while scanning": that state is
      // unreachable. With no devices yet, the screen renders the radar and
      // never builds this at all. A guard for it was written, found to be
      // dead code, and removed rather than covered.

      await teardownTree(tester);
    });
  });
}

/// A scanner that reports fixed state without touching the network.
class _StubScanner extends ScannerNotifier {
  _StubScanner(this._state);

  final ScannerState _state;

  @override
  ScannerState build() => _state;

  @override
  Future<void> startScan() async {}

  @override
  Future<void> stopScan({bool isDisposing = false}) async {}
}
