import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:devicecontroller/controllers/device_controller_factory.dart';
import 'package:devicecontroller/models/device.dart';
import 'package:devicecontroller/providers/connection_provider.dart';
import 'package:devicecontroller/screens/remote.dart';
import 'package:devicecontroller/services/connectivity_service.dart';
import 'package:devicecontroller/services/device_persistence_service.dart';

import '../fakes/fake_controller.dart';
import '../providers/connection_provider_test.mocks.dart';

/// Disposes the widget tree so the test does not end with pending timers.
///
/// The remote screen runs several .animate(onPlay: repeat) loops that never
/// settle. That testability cost is finding M-2; Phase 3 removes the
/// perpetual ones.
Future<void> settle(WidgetTester tester) async {
  // Flush the zero-duration timer flutter_animate schedules from initState,
  // then drop the tree so the repeating tickers are cancelled.
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  const device = Device(
    id: 'roku-1',
    name: 'Living Room Roku',
    type: DeviceType.roku,
    model: 'Ultra',
    ip: '192.168.1.50',
  );

  late MockDevicePersistenceService persistence;
  late MockConnectivityService connectivity;

  setUp(() {
    persistence = MockDevicePersistenceService();
    connectivity = MockConnectivityService();
    when(connectivity.onConnectivityChanged)
        .thenAnswer((_) => const Stream.empty());
    when(persistence.loadDevice()).thenAnswer((_) async => null);
  });

  Future<ProviderContainer> pumpRemote(
    WidgetTester tester,
    FakeController controller,
  ) async {
    final container = ProviderContainer(
      overrides: [
        devicePersistenceProvider.overrideWithValue(persistence),
        connectivityServiceProvider.overrideWithValue(connectivity),
        deviceControllerFactoryProvider.overrideWithValue((_) => controller),
      ],
    );
    addTearDown(container.dispose);

    await container.read(connectionProvider.notifier).connect(device);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: RemoteScreen(device: device, onDisconnect: () {}),
        ),
      ),
    );
    await tester.pump();

    return container;
  }

  testWidgets('shows CONNECTED while the session is live', (tester) async {
    await pumpRemote(tester, FakeController());

    expect(find.text('CONNECTED'), findsOneWidget);
    await settle(tester);
  });

  testWidgets('tells the user when the session is lost', (tester) async {
    final controller = FakeController();
    await pumpRemote(tester, controller);

    // The TV goes away on its own. Nothing the user did caused this, and
    // before the health stream the screen went on claiming CONNECTED while
    // silently dropping every press.
    controller.dropSession();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('Lost connection'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await settle(tester);
  });

  testWidgets('reports a key press that could not be delivered',
      (tester) async {
    final controller = FakeController();
    await pumpRemote(tester, controller);

    controller.dropSession();
    await tester.pump(const Duration(milliseconds: 50));

    // Dismiss the connection-loss snackbar so the next one is unambiguous.
    ScaffoldMessenger.of(tester.element(find.byType(RemoteScreen)))
        .hideCurrentSnackBar();
    await tester.pump();

    await tester.tap(find.widgetWithText(Column, 'BACK').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.byType(SnackBar),
      findsOneWidget,
      reason: 'a press that reached no TV must not pass silently',
    );
    await settle(tester);
  });

  testWidgets('a delivered key press raises no error', (tester) async {
    await pumpRemote(tester, FakeController());

    await tester.tap(find.widgetWithText(Column, 'BACK').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(SnackBar), findsNothing);
    await settle(tester);
  });
}
