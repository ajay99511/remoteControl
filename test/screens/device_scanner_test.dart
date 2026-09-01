import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:devicecontroller/models/device.dart';
import 'package:devicecontroller/providers/scanner_provider.dart';
import 'package:devicecontroller/screens/device_scanner.dart';
import 'package:devicecontroller/services/connectivity_service.dart';
import 'package:devicecontroller/services/device_persistence_service.dart';

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

  Future<void> pump(WidgetTester tester, ScannerState state) async {
    final container = ProviderContainer(
      overrides: [
        devicePersistenceProvider.overrideWithValue(persistence),
        connectivityServiceProvider.overrideWithValue(connectivity),
        mdnsEnabledProvider.overrideWithValue(false),
        ssdpSocketBinderProvider.overrideWithValue(
          () async => FakeDatagramSocket(),
        ),
        scannerProvider.overrideWith(() => _StubScanner(state)),
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
