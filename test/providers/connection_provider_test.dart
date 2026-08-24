import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:devicecontroller/controllers/device_controller.dart';
import 'package:devicecontroller/controllers/device_controller_factory.dart';
import 'package:devicecontroller/exceptions/unsupported_device_exception.dart';
import 'package:devicecontroller/models/device.dart';
import 'package:devicecontroller/models/remote_key.dart';
import 'package:devicecontroller/providers/connection_provider.dart';
import 'package:devicecontroller/services/connectivity_service.dart';
import 'package:devicecontroller/services/device_persistence_service.dart';

import '../fakes/fake_controller.dart';
import 'connection_provider_test.mocks.dart';

@GenerateMocks([DevicePersistenceService, ConnectivityService])
void main() {
  late MockDevicePersistenceService mockPersistence;
  late MockConnectivityService mockConnectivity;

  const testDevice = Device(
    id: 'roku-1',
    name: 'Living Room Roku',
    type: DeviceType.roku,
    model: 'Ultra',
    ip: '192.168.1.50',
  );

  /// Builds a container whose controller factory the test controls, so no
  /// socket is ever opened.
  ProviderContainer containerWith(DeviceController controller) {
    return ProviderContainer(
      overrides: [
        devicePersistenceProvider.overrideWithValue(mockPersistence),
        connectivityServiceProvider.overrideWithValue(mockConnectivity),
        deviceControllerFactoryProvider.overrideWithValue((_) => controller),
      ],
    );
  }

  setUp(() {
    mockPersistence = MockDevicePersistenceService();
    mockConnectivity = MockConnectivityService();

    when(mockConnectivity.onConnectivityChanged)
        .thenAnswer((_) => const Stream.empty());
    when(mockPersistence.loadDevice()).thenAnswer((_) async => null);
  });

  group('ConnectionNotifier connect', () {
    test('reaches connected and persists the device', () async {
      final container = containerWith(FakeController());
      addTearDown(container.dispose);

      await container.read(connectionProvider.notifier).connect(testDevice);

      expect(container.read(connectionProvider).status,
          ConnectionStatus.connected);
      verify(mockPersistence.saveDevice(testDevice)).called(1);
    });

    test('retries a transient failure and gives up after 4 attempts', () {
      fakeAsync((async) {
        final fake = FakeController(
          connectError: const SocketException('no route to host'),
        );
        final container = containerWith(fake);
        addTearDown(container.dispose);

        container.read(connectionProvider.notifier).connect(testDevice);
        async.flushMicrotasks();
        // 1 + 2 + 4 + 8 = 15s of backoff across four retries.
        async.elapse(const Duration(seconds: 30));

        expect(
            container.read(connectionProvider).status, ConnectionStatus.error);
        expect(fake.connectCalls, 5,
            reason: 'one initial attempt plus four retries');
      });
    });

    test('does not retry a permanent failure', () {
      fakeAsync((async) {
        final fake = FakeController(
          connectError: const UnsupportedDeviceException(DeviceType.fireTv),
        );
        final container = containerWith(fake);
        addTearDown(container.dispose);

        container.read(connectionProvider.notifier).connect(testDevice);
        async.flushMicrotasks();

        expect(
            container.read(connectionProvider).status, ConnectionStatus.error);
        expect(fake.connectCalls, 1, reason: 'a permanent error is final');
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('surfaces a readable message, not a raw exception toString', () {
      fakeAsync((async) {
        final container = containerWith(FakeController(
          connectError: const UnsupportedDeviceException(DeviceType.googleTv),
        ));
        addTearDown(container.dispose);

        container.read(connectionProvider.notifier).connect(testDevice);
        async.flushMicrotasks();

        final message = container.read(connectionProvider).errorMessage;
        expect(message, isNotNull);
        expect(message, isNot(contains('Exception')));
        expect(message, isNot(contains('#0')));
      });
    });
  });

  group('ConnectionNotifier session health', () {
    test('a transport-initiated drop moves the session to error', () async {
      final fake = FakeController();
      final container = containerWith(fake);
      addTearDown(container.dispose);

      await container.read(connectionProvider.notifier).connect(testDevice);
      expect(container.read(connectionProvider).status,
          ConnectionStatus.connected);

      // The TV goes away without the app asking. Before the health stream this
      // stopped inside the controller, and the UI went on showing CONNECTED
      // over a dead transport while dropping every key press.
      fake.dropSession();
      await Future<void>.delayed(Duration.zero);

      expect(container.read(connectionProvider).status, ConnectionStatus.error);
      expect(container.read(connectionProvider).errorMessage,
          contains('Lost connection'));
    });

    test('commands report failure once the session is gone', () async {
      final fake = FakeController();
      final container = containerWith(fake);
      addTearDown(container.dispose);

      await container.read(connectionProvider.notifier).connect(testDevice);
      fake.dropSession();
      await Future<void>.delayed(Duration.zero);

      final result = await container
          .read(connectionProvider.notifier)
          .sendKey(RemoteKey.up);

      expect(result.isSuccess, isFalse);
    });

    test('a command succeeds while the session is live', () async {
      final container = containerWith(FakeController());
      addTearDown(container.dispose);

      await container.read(connectionProvider.notifier).connect(testDevice);
      final result = await container
          .read(connectionProvider.notifier)
          .sendKey(RemoteKey.up);

      expect(result.isSuccess, isTrue);
    });
  });

  group('ConnectionNotifier lifecycle', () {
    test('auto-reconnects to a saved device on build', () async {
      when(mockPersistence.loadDevice()).thenAnswer((_) async => testDevice);
      final container = containerWith(FakeController());
      addTearDown(container.dispose);

      container.read(connectionProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(container.read(connectionProvider).device, testDevice);
    });

    test('reconnects when Wi-Fi is restored after an error', () async {
      final connectivity = StreamController<List<ConnectivityResult>>();
      addTearDown(connectivity.close);
      when(mockConnectivity.onConnectivityChanged)
          .thenAnswer((_) => connectivity.stream);

      final container = containerWith(FakeController());
      addTearDown(container.dispose);
      final notifier = container.read(connectionProvider.notifier);

      await notifier.connect(testDevice);
      connectivity.add([ConnectivityResult.none]);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(connectionProvider).status, ConnectionStatus.error);

      connectivity.add([ConnectivityResult.wifi]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(container.read(connectionProvider).status,
          anyOf(ConnectionStatus.connecting, ConnectionStatus.connected));
    });

    test('disconnect() clears persistence', () async {
      final container = containerWith(FakeController());
      addTearDown(container.dispose);

      await container.read(connectionProvider.notifier).disconnect();

      verify(mockPersistence.clearDevice()).called(1);
    });
  });
}
