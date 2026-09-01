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
import 'package:devicecontroller/services/device_resolver.dart';

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

    when(
      mockConnectivity.onConnectivityChanged,
    ).thenAnswer((_) => const Stream.empty());
    when(mockPersistence.loadDevice()).thenAnswer((_) async => null);
  });

  group('ConnectionNotifier connect', () {
    test('reaches connected and persists the device', () async {
      final container = containerWith(FakeController());
      addTearDown(container.dispose);

      await container.read(connectionProvider.notifier).connect(testDevice);

      expect(
        container.read(connectionProvider).status,
        ConnectionStatus.connected,
      );
      verify(mockPersistence.saveDevice(testDevice)).called(1);
    });

    test('remembers the device so the next scan can show it at once', () async {
      final container = containerWith(FakeController());
      addTearDown(container.dispose);

      await container.read(connectionProvider.notifier).connect(testDevice);

      // Only devices that actually connected are worth remembering; a failed
      // attempt against a mistyped address is not a device the user owns.
      verify(mockPersistence.rememberDevice(testDevice)).called(1);
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
          container.read(connectionProvider).status,
          ConnectionStatus.error,
        );
        expect(
          fake.connectCalls,
          5,
          reason: 'one initial attempt plus four retries',
        );
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
          container.read(connectionProvider).status,
          ConnectionStatus.error,
        );
        expect(fake.connectCalls, 1, reason: 'a permanent error is final');
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('disposing mid-retry does not write to a dead notifier', () {
      fakeAsync((async) {
        final fake = FakeController(
          connectError: const SocketException('no route to host'),
        );
        final container = containerWith(fake);

        container.read(connectionProvider.notifier).connect(testDevice);
        async.flushMicrotasks();

        // The user navigates away during the backoff window. ref.onDispose
        // cancelled the connectivity subscription but nothing cancelled the
        // in-flight retry chain, so the next `state =` hit a disposed
        // Notifier and threw StateError.
        container.dispose();

        expect(
          () => async.elapse(const Duration(seconds: 30)),
          returnsNormally,
          reason: 'a superseded chain must not touch state after dispose',
        );
      });
    });

    test('a newer connect supersedes an in-flight retry chain', () {
      fakeAsync((async) {
        const unreachable = Device(
          id: 'unreachable',
          name: 'Unplugged TV',
          type: DeviceType.roku,
          model: 'Ultra',
          ip: '192.168.1.99',
        );
        final failing = FakeController(
          connectError: const SocketException('no route to host'),
        );
        final healthy = FakeController();

        final container = ProviderContainer(
          overrides: [
            devicePersistenceProvider.overrideWithValue(mockPersistence),
            connectivityServiceProvider.overrideWithValue(mockConnectivity),
            deviceControllerFactoryProvider.overrideWithValue(
              (device) => device.id == unreachable.id ? failing : healthy,
            ),
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(connectionProvider.notifier);

        // Chain 1 starts retrying an unreachable TV.
        notifier.connect(unreachable);
        async.flushMicrotasks();

        // The user picks a different, working TV while chain 1 is sleeping.
        // Both chains previously ran concurrently sharing one _retryCount, and
        // chain 1 eventually overwrote the good state with its own failure.
        notifier.connect(testDevice);
        async.elapse(const Duration(seconds: 60));

        expect(
          container.read(connectionProvider).status,
          ConnectionStatus.connected,
          reason: 'a superseded chain must not overwrite a newer result',
        );
        expect(container.read(connectionProvider).device, testDevice);
      });
    });

    test('surfaces a readable message, not a raw exception toString', () {
      fakeAsync((async) {
        final container = containerWith(
          FakeController(
            connectError: const UnsupportedDeviceException(DeviceType.googleTv),
          ),
        );
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
      expect(
        container.read(connectionProvider).status,
        ConnectionStatus.connected,
      );

      // The TV goes away without the app asking. Before the health stream this
      // stopped inside the controller, and the UI went on showing CONNECTED
      // over a dead transport while dropping every key press.
      fake.dropSession();
      await Future<void>.delayed(Duration.zero);

      expect(container.read(connectionProvider).status, ConnectionStatus.error);
      expect(
        container.read(connectionProvider).errorMessage,
        contains('Lost connection'),
      );
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
      when(
        mockConnectivity.onConnectivityChanged,
      ).thenAnswer((_) => connectivity.stream);

      final container = containerWith(FakeController());
      addTearDown(container.dispose);
      final notifier = container.read(connectionProvider.notifier);

      await notifier.connect(testDevice);
      connectivity.add([ConnectivityResult.none]);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(connectionProvider).status, ConnectionStatus.error);

      connectivity.add([ConnectivityResult.wifi]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        container.read(connectionProvider).status,
        anyOf(ConnectionStatus.connecting, ConnectionStatus.connected),
      );
    });

    test('does not chase a LAN address over cellular', () async {
      final connectivity = StreamController<List<ConnectivityResult>>();
      addTearDown(connectivity.close);
      when(
        mockConnectivity.onConnectivityChanged,
      ).thenAnswer((_) => connectivity.stream);

      final fake = FakeController();
      final container = containerWith(fake);
      addTearDown(container.dispose);
      final notifier = container.read(connectionProvider.notifier);

      await notifier.connect(testDevice);
      final attemptsWhileOnWifi = fake.connectCalls;

      // The user leaves the house. Mobile data is not `none`, so the old
      // check read this as "still online" and started a retry chain against
      // an unreachable private address.
      connectivity.add([ConnectivityResult.mobile]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(container.read(connectionProvider).status, ConnectionStatus.error);
      expect(
        fake.connectCalls,
        attemptsWhileOnWifi,
        reason: 'cellular cannot reach the TV; do not spend attempts on it',
      );
    });

    test('resumes reconnecting once wifi returns', () async {
      final connectivity = StreamController<List<ConnectivityResult>>();
      addTearDown(connectivity.close);
      when(
        mockConnectivity.onConnectivityChanged,
      ).thenAnswer((_) => connectivity.stream);

      final container = containerWith(FakeController());
      addTearDown(container.dispose);
      final notifier = container.read(connectionProvider.notifier);

      await notifier.connect(testDevice);
      connectivity.add([ConnectivityResult.mobile]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(container.read(connectionProvider).status, ConnectionStatus.error);

      connectivity.add([ConnectivityResult.wifi]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        container.read(connectionProvider).status,
        ConnectionStatus.connected,
      );
    });

    test('disconnect() clears persistence', () async {
      final container = containerWith(FakeController());
      addTearDown(container.dispose);

      await container.read(connectionProvider.notifier).disconnect();

      verify(mockPersistence.clearDevice()).called(1);
    });
  });

  group('ConnectionNotifier re-resolution', () {
    /// The television the user knows, at the address it held last time.
    const moved = Device(
      id: 'ssdp:lg-1',
      name: 'Bedroom TV',
      type: DeviceType.lg,
      model: 'OLED55',
      ip: '192.168.1.60',
      port: 3000,
      uid: 'ssdp:lg-1',
    );

    /// A container whose controllers succeed only at [liveAddress], and whose
    /// resolver reports the device living there.
    ProviderContainer containerFor({
      required String liveAddress,
      Device? resolvesTo,
      void Function(Device)? onResolve,
    }) => ProviderContainer(
      overrides: [
        devicePersistenceProvider.overrideWithValue(mockPersistence),
        connectivityServiceProvider.overrideWithValue(mockConnectivity),
        deviceControllerFactoryProvider.overrideWithValue(
          (device) => device.ip == liveAddress
              ? FakeController()
              : FakeController(
                  connectError: const SocketException('no route to host'),
                ),
        ),
        deviceAddressResolverProvider.overrideWithValue((device) async {
          onResolve?.call(device);
          return resolvesTo;
        }),
      ],
    );

    test('reconnects to a device that changed address', () async {
      final container = containerFor(
        liveAddress: '192.168.1.88',
        resolvesTo: moved.copyWith(ip: '192.168.1.88'),
      );
      addTearDown(container.dispose);

      await container.read(connectionProvider.notifier).connect(moved);

      final state = container.read(connectionProvider);
      expect(state.status, ConnectionStatus.connected);
      expect(
        state.device!.ip,
        '192.168.1.88',
        reason: 'a DHCP lease renewal is the ordinary case, not a failure',
      );
      // The corrected address is what gets remembered, or the next launch
      // repeats the same doomed attempt.
      verify(
        mockPersistence.rememberDevice(
          argThat(predicate<Device>((d) => d.ip == '192.168.1.88')),
        ),
      ).called(1);
    });

    test('looks for it once, not once per retry', () {
      // Virtual clock: this chain spends its whole retry budget, and the real
      // backoff ceilings add fifteen seconds to the suite for no extra proof.
      fakeAsync((async) {
        var lookups = 0;
        final container = containerFor(
          liveAddress: '192.168.1.88',
          resolvesTo: null,
          onResolve: (_) => lookups++,
        );
        addTearDown(container.dispose);

        container.read(connectionProvider.notifier).connect(moved);
        async.elapse(const Duration(seconds: 60));
        async.flushMicrotasks();

        expect(
          container.read(connectionProvider).status,
          ConnectionStatus.error,
        );
        expect(
          lookups,
          1,
          reason:
              'five multicast sweeps per connect attempt is a burst of '
              'broadcast traffic for one answer that was not going to change',
        );
      });
    });

    test('does not look for a device that has no stable id', () async {
      var lookups = 0;
      final container = containerFor(
        liveAddress: '192.168.1.88',
        resolvesTo: null,
        onResolve: (_) => lookups++,
      );
      addTearDown(container.dispose);

      // testDevice was entered by hand: nothing to match an answer against.
      await container.read(connectionProvider.notifier).connect(testDevice);

      expect(lookups, 0);
    });

    test('a failure that re-resolution cannot fix still reports an error', () {
      fakeAsync((async) {
        final container = containerFor(
          liveAddress: '192.168.1.88',
          resolvesTo: moved,
        );
        addTearDown(container.dispose);

        // The resolver finds it exactly where it already was, so the address
        // was never the problem.
        container.read(connectionProvider.notifier).connect(moved);
        async.elapse(const Duration(seconds: 60));
        async.flushMicrotasks();

        expect(
          container.read(connectionProvider).status,
          ConnectionStatus.error,
        );
      });
    });
  });
}
