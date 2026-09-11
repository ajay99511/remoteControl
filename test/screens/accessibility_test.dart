import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:devicecontroller/models/device.dart';
import 'package:devicecontroller/providers/scanner_provider.dart';
import 'package:devicecontroller/screens/device_scanner.dart';
import 'package:devicecontroller/screens/manual_connect_dialog.dart';
import 'package:devicecontroller/services/connectivity_service.dart';
import 'package:devicecontroller/services/device_persistence_service.dart';
import 'package:devicecontroller/services/ssdp.dart';

import '../fakes/fake_datagram_socket.dart';
import '../providers/connection_provider_test.mocks.dart';

/// Guards the accessibility claim rather than asserting it.
///
/// The hardening commit that preceded this work claimed "full Semantics and
/// tooltip support for all interactive elements"; the discovery screen - the
/// launch screen, and the only route to the remote - contained zero Semantics
/// widgets. These tests exist so that claim is machine-checkable.
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

  Future<void> pumpScanner(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        devicePersistenceProvider.overrideWithValue(persistence),
        connectivityServiceProvider.overrideWithValue(connectivity),
        mdnsEnabledProvider.overrideWithValue(false),
        ssdpSocketBinderProvider.overrideWithValue(
          () async => FakeDatagramSocket(),
        ),
        // Seed a device so the list, not the empty state, is under test.
        scannerProvider.overrideWith(_StubScanner.new),
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

  group('Discovery screen accessibility', () {
    testWidgets('every tap target is labelled', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpScanner(tester);

      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      handle.dispose();
      await teardownTree(tester);
    });

    testWidgets('tap targets meet the platform minimum size', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpScanner(tester);

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));

      handle.dispose();
      await teardownTree(tester);
    });

    testWidgets('a discovered device announces what it is', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpScanner(tester);

      // A screen reader previously read two unlabelled Text children with no
      // role, so the user never learned the row was actionable.
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.button == true &&
              (w.properties.label ?? '').contains('Living Room Roku') &&
              (w.properties.label ?? '').contains('roku'),
        ),
        findsOneWidget,
      );

      handle.dispose();
      await teardownTree(tester);
    });

    testWidgets('the action buttons expose a name and a role', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpScanner(tester);

      for (final name in ['Rescan', 'Manual IP']) {
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                w.properties.button == true &&
                w.properties.label == name,
          ),
          findsOneWidget,
          reason: '$name must expose a name and a button role',
        );
      }

      handle.dispose();
      await teardownTree(tester);
    });
  });

  group('Manual connect dialog accessibility', () {
    testWidgets('both inputs carry an associated label', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ManualConnectDialog())),
      );
      await tester.pump();

      // The visual labels used to be detached Text widgets that a screen
      // reader could not connect to the field.
      expect(find.text('IP Address'), findsOneWidget);
      expect(find.text('Port'), findsOneWidget);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      handle.dispose();
      await teardownTree(tester);
    });
  });
}

/// A scanner that reports one device without touching the network.
class _StubScanner extends ScannerNotifier {
  @override
  ScannerState build() => const ScannerState(
    devices: [
      Device(
        id: '192.168.1.50:8060',
        name: 'Living Room Roku',
        type: DeviceType.roku,
        model: 'Ultra',
        ip: '192.168.1.50',
        port: 8060,
      ),
    ],
  );

  @override
  Future<void> startScan() async {}

  @override
  Future<void> stopScan({bool isDisposing = false}) async {}
}
