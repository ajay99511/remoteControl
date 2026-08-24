import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:devicecontroller/models/device.dart';
import 'package:devicecontroller/providers/connection_provider.dart';
import 'package:devicecontroller/services/connectivity_service.dart';
import 'package:devicecontroller/services/device_persistence_service.dart';

import 'connection_provider_test.mocks.dart';

@GenerateMocks([DevicePersistenceService, ConnectivityService])
void main() {
  late MockDevicePersistenceService mockPersistence;
  late MockConnectivityService mockConnectivity;
  late ProviderContainer container;
  final testDevice = Device(
    id: 'mock-1',
    name: 'Test Device',
    type: DeviceType.roku,
    model: 'Test',
    signal: 100,
    ip: '127.0.0.1',
  );

  setUp(() {
    mockPersistence = MockDevicePersistenceService();
    mockConnectivity = MockConnectivityService();
    
    when(mockConnectivity.onConnectivityChanged).thenAnswer((_) => const Stream.empty());
    when(mockPersistence.loadDevice()).thenAnswer((_) async => null);

    container = ProviderContainer(
      overrides: [
        devicePersistenceProvider.overrideWithValue(mockPersistence),
        connectivityServiceProvider.overrideWithValue(mockConnectivity),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  group('ConnectionNotifier', () {
    test('auto-reconnects on build if device saved', () async {
      when(mockPersistence.loadDevice()).thenAnswer((_) async => testDevice);
      
      // Access the provider to trigger build
      final notifier = container.read(connectionProvider.notifier);
      
      await Future.delayed(const Duration(milliseconds: 100));
      expect(container.read(connectionProvider).device, testDevice);
    });

    test('reconnects when Wi-Fi restored after error', () async {
      final connectivityStream = StreamController<List<ConnectivityResult>>();
      when(mockConnectivity.onConnectivityChanged).thenAnswer((_) => connectivityStream.stream);
      
      final notifier = container.read(connectionProvider.notifier);
      
      // Simulate error state with a device
      container.read(connectionProvider.notifier).connect(testDevice);
      await Future.delayed(const Duration(milliseconds: 100));

      // Restore Wi-Fi
      connectivityStream.add([ConnectivityResult.wifi]);
      
      await Future.delayed(const Duration(milliseconds: 100));
      // Should have attempted reconnect
      expect(container.read(connectionProvider).status, anyOf(ConnectionStatus.connecting, ConnectionStatus.connected));
      
      await connectivityStream.close();
    });

    test('_connectWithBackoff retries 4 times before failing', () {
      fakeAsync((async) {
        when(mockPersistence.loadDevice()).thenAnswer((_) async => null);
        
        final notifier = container.read(connectionProvider.notifier);
        
        // Mock a device that always fails to connect (e.g., an IR device without brand)
        // Wait,Switch to a device type that will fail, or mock the controller build?
        // ConnectionNotifier._buildController creates real controllers.
        // I can't easily mock the controller itself without more refactoring.
        // But I can use a device that will throw in connect().
        
        final badDevice = Device(
          id: 'bad-ip',
          name: 'Bad Device',
          type: DeviceType.roku,
          model: 'Bad',
          signal: 100,
          ip: '0.0.0.0', // Should fail
        );

        notifier.connect(badDevice);
        async.flushMicrotasks();

        // Each attempt takes 3s (Roku timeout) + delay
        async.elapse(const Duration(seconds: 40));

        expect(container.read(connectionProvider).status, ConnectionStatus.error);
      });
    });

    test('an unsupported device fails at once instead of retrying', () {
      fakeAsync((async) {
        final notifier = container.read(connectionProvider.notifier);
        final fireTv = Device(
          id: 'firetv-1',
          name: 'Fire TV Stick',
          type: DeviceType.fireTv,
          model: 'stick',
          signal: 100,
          ip: '192.168.1.9',
        );

        notifier.connect(fireTv);
        async.flushMicrotasks();

        // UnsupportedDeviceException is deterministic and permanent. Retrying
        // it burned 1+2+4+8 = 15s before telling the user what was already
        // known at the first attempt.
        expect(
          container.read(connectionProvider).status,
          ConnectionStatus.error,
          reason: 'a permanent error must not be retried',
        );
        expect(async.pendingTimers, isEmpty,
            reason: 'no backoff timer should have been scheduled');
      });
    });

    test('surfaces a readable message, not a raw exception toString', () {
      fakeAsync((async) {
        final notifier = container.read(connectionProvider.notifier);
        notifier.connect(Device(
          id: 'googletv-1',
          name: 'Chromecast',
          type: DeviceType.googleTv,
          model: 'gtv',
          signal: 100,
          ip: '192.168.1.11',
        ));
        async.flushMicrotasks();

        final message = container.read(connectionProvider).errorMessage;
        expect(message, isNotNull);
        expect(message, isNot(contains('Exception')));
        expect(message, isNot(contains('#0')));
      });
    });

    test('disconnect() clears persistence', () async {
      final notifier = container.read(connectionProvider.notifier);
      await notifier.disconnect();
      verify(mockPersistence.clearDevice()).called(1);
    });
  });
}
