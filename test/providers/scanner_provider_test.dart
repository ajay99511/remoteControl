import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devicecontroller/models/device.dart';
import 'package:devicecontroller/providers/scanner_provider.dart';
import 'package:devicecontroller/services/device_description.dart';
import 'package:devicecontroller/services/ssdp.dart';

import '../fakes/fake_datagram_socket.dart';

void main() {
  late FakeDatagramSocket socket;

  /// A container whose network is entirely under the test's control: mDNS off,
  /// UDP socket faked, descriptions stubbed. Nothing touches the real network.
  ProviderContainer makeContainer({
    DeviceDescription? describesAs,
    List<Device> knownDevices = const [],
  }) => ProviderContainer(
    overrides: [
      mdnsEnabledProvider.overrideWithValue(false),
      ssdpSocketBinderProvider.overrideWithValue(() async => socket),
      deviceDescriptionFetcherProvider.overrideWithValue(
        (_) async => describesAs,
      ),
      knownDevicesLoaderProvider.overrideWithValue(() async => knownDevices),
    ],
  );

  /// An SSDP reply as a Roku sends one, pointing at its description.
  /// An SSDP reply as a Roku sends one, pointing at its description.
  Datagram ssdpReply(String ip) => Datagram(
    utf8.encode(
      'HTTP/1.1 200 OK\r\n'
      'SERVER: Roku UPnP/1.0 MiniUPnPd/1.4\r\n'
      'LOCATION: http://$ip:8060/\r\n'
      'USN: uuid:roku:ecp:1GU48T017973\r\n\r\n',
    ),
    InternetAddress(ip),
    1900,
  );

  setUp(() => socket = FakeDatagramSocket());

  group('ScannerNotifier SSDP probe', () {
    test('probes every search target, several rounds', () {
      fakeAsync((async) {
        final container = makeContainer();
        addTearDown(container.dispose);

        container.read(scannerProvider.notifier).startScan();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));

        final sent = socket.sent.map(utf8.decode).toList();

        // Asking only for ssdp:all makes every UPnP device on the segment
        // answer; real remotes ask for what they can control.
        expect(sent.where((m) => m.contains('ST: roku:ecp')), hasLength(3));
        expect(
          sent.where((m) => m.contains('ST: urn:dial-multiscreen-org')),
          hasLength(3),
        );
        expect(sent.where((m) => m.contains('ST: ssdp:all')), hasLength(3));
        expect(socket.broadcastEnabled, isTrue);
      });
    });

    test('sends a well-formed M-SEARCH', () {
      fakeAsync((async) {
        final container = makeContainer();
        addTearDown(container.dispose);

        container.read(scannerProvider.notifier).startScan();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));

        final probe = utf8.decode(socket.sent.first);

        expect(probe, startsWith('M-SEARCH * HTTP/1.1\r\n'));
        expect(probe, contains('HOST: 239.255.255.250:1900\r\n'));
        expect(probe, contains('MAN: "ssdp:discover"\r\n'));
        // UPnP requires MX between 1 and 5.
        final mx = int.parse(RegExp(r'MX: (\d+)').firstMatch(probe)!.group(1)!);
        expect(mx, inInclusiveRange(1, 5));
        // A request must end with a blank line.
        expect(probe, endsWith('\r\n\r\n'));
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

  group('ScannerNotifier device naming', () {
    test('adopts the name the device gives for itself', () async {
      final container = makeContainer(
        describesAs: const DeviceDescription(
          friendlyName: 'Living Room',
          modelName: 'Roku Ultra',
        ),
      );
      addTearDown(container.dispose);

      await container.read(scannerProvider.notifier).startScan();
      socket.deliver(ssdpReply('192.168.1.50'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final device = container.read(scannerProvider).devices.single;
      // Without reading the description the scanner could only infer from the
      // SERVER header, so every Roku in the house was "Roku Device".
      expect(device.name, 'Living Room');
      expect(device.model, 'Roku Ultra');
    });

    test(
      'keeps the inferred name when the device will not describe itself',
      () async {
        final container = makeContainer(describesAs: null);
        addTearDown(container.dispose);

        await container.read(scannerProvider.notifier).startScan();
        socket.deliver(ssdpReply('192.168.1.50'));
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final device = container.read(scannerProvider).devices.single;
        expect(device.name, 'Roku Device');
        expect(device.type, DeviceType.roku);
      },
    );

    test(
      'describes each device once however many targets it answers',
      () async {
        var fetches = 0;
        final container = ProviderContainer(
          overrides: [
            mdnsEnabledProvider.overrideWithValue(false),
            ssdpSocketBinderProvider.overrideWithValue(() async => socket),
            deviceDescriptionFetcherProvider.overrideWithValue((_) async {
              fetches++;
              return const DeviceDescription(friendlyName: 'Living Room');
            }),
            knownDevicesLoaderProvider.overrideWithValue(() async => const []),
          ],
        );
        addTearDown(container.dispose);

        await container.read(scannerProvider.notifier).startScan();
        // A TV answers every search target we send, from the same LOCATION.
        for (var i = 0; i < 4; i++) {
          socket.deliver(ssdpReply('192.168.1.50'));
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(fetches, 1, reason: 'one description request per device');
        expect(container.read(scannerProvider).devices, hasLength(1));
      },
    );
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

  group('ScannerNotifier remembered devices', () {
    const saved = Device(
      id: 'ssdp:roku:ecp:1GU48T017973',
      name: 'Living Room',
      type: DeviceType.roku,
      model: 'Roku Ultra',
      ip: '192.168.1.50',
      port: 8060,
      uid: 'ssdp:roku:ecp:1GU48T017973',
    );

    test('shows them before the network has answered anything', () async {
      final container = makeContainer(knownDevices: [saved]);
      addTearDown(container.dispose);

      await container.read(scannerProvider.notifier).startScan();

      // A discovery sweep takes seconds. A device the user has already
      // connected to should not make them watch an empty list first.
      final state = container.read(scannerProvider);
      expect(state.devices.single.name, 'Living Room');
      expect(state.restored, contains(saved.credentialKey));
    });

    test('a live sighting takes over the remembered entry', () async {
      final container = makeContainer(knownDevices: [saved]);
      addTearDown(container.dispose);

      await container.read(scannerProvider.notifier).startScan();
      // Same television, new address after a DHCP lease renewal.
      socket.deliver(ssdpReply('192.168.1.77'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = container.read(scannerProvider);
      expect(
        state.devices,
        hasLength(1),
        reason: 'one television must not appear once per address it has held',
      );
      expect(state.devices.single.ip, '192.168.1.77');
      expect(
        state.restored,
        isEmpty,
        reason: 'it has answered, so it is no longer only a memory',
      );
    });

    test('a remembered device is kept alongside a new one', () async {
      final container = makeContainer(knownDevices: [saved]);
      addTearDown(container.dispose);

      await container.read(scannerProvider.notifier).startScan();
      socket.deliver(
        Datagram(
          utf8.encode(
            'HTTP/1.1 200 OK\r\n'
            'SERVER: WebOS UPnP/1.0\r\n'
            'LOCATION: http://192.168.1.90:3000/\r\n'
            'USN: uuid:lg-9999\r\n\r\n',
          ),
          InternetAddress('192.168.1.90'),
          1900,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = container.read(scannerProvider);
      expect(state.devices.map((d) => d.ip), ['192.168.1.50', '192.168.1.90']);
      expect(state.restored, {saved.credentialKey});
    });
  });
}
