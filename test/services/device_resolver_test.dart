import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devicecontroller/models/device.dart';
import 'package:devicecontroller/services/device_resolver.dart';

import '../fakes/fake_datagram_socket.dart';

void main() {
  late FakeDatagramSocket socket;

  /// A television the user has connected to before, at the address it held
  /// then. The router has since handed that address to something else.
  const known = Device(
    id: 'ssdp:roku:ecp:1GU48T017973',
    name: 'Living Room',
    type: DeviceType.roku,
    model: 'Roku Ultra',
    ip: '192.168.1.50',
    port: 8060,
    uid: 'ssdp:roku:ecp:1GU48T017973',
  );

  Datagram reply(String ip, String usn) => Datagram(
    utf8.encode(
      'HTTP/1.1 200 OK\r\n'
      'SERVER: Roku UPnP/1.0 MiniUPnPd/1.4\r\n'
      'LOCATION: http://$ip:8060/\r\n'
      'USN: $usn\r\n\r\n',
    ),
    InternetAddress(ip),
    1900,
  );

  setUp(() => socket = FakeDatagramSocket());

  group('resolveDeviceAddress', () {
    test('finds the same television at its new address', () async {
      socket.deliver(reply('192.168.1.77', 'uuid:roku:ecp:1GU48T017973'));

      final found = await resolveDeviceAddress(
        known,
        bind: () async => socket,
        timeout: const Duration(seconds: 2),
      );

      expect(found, isNotNull);
      expect(found!.ip, '192.168.1.77');
      // Identity, name and the port it was paired on all survive; only the
      // address the router controls is allowed to change.
      expect(found.uid, known.uid);
      expect(found.name, 'Living Room');
      expect(found.port, 8060);
    });

    test('ignores a different device answering the same probe', () {
      fakeAsync((async) {
        socket.deliver(reply('192.168.1.90', 'uuid:some-other-tv'));

        Device? result;
        var done = false;
        resolveDeviceAddress(
          known,
          bind: () async => socket,
          timeout: const Duration(seconds: 2),
        ).then((d) {
          result = d;
          done = true;
        });

        // The socket binds on a microtask; nothing is scheduled until it has.
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 3));
        async.flushMicrotasks();

        expect(done, isTrue);
        expect(
          result,
          isNull,
          reason:
              'reconnecting to whatever answered first is how a remote '
              'ends up driving the neighbour television',
        );
      });
    });

    test('gives up when nothing answers, and closes the socket', () {
      fakeAsync((async) {
        var done = false;
        resolveDeviceAddress(
          known,
          bind: () async => socket,
          timeout: const Duration(seconds: 2),
        ).then((_) => done = true);

        // The socket binds on a microtask; nothing is scheduled until it has.
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 3));
        async.flushMicrotasks();

        expect(done, isTrue);
        expect(socket.closed, isTrue, reason: 'a bounded probe must not leak');
      });
    });

    test('releases the socket once it has found what it came for', () async {
      socket.deliver(reply('192.168.1.77', 'uuid:roku:ecp:1GU48T017973'));

      await resolveDeviceAddress(
        known,
        bind: () async => socket,
        timeout: const Duration(seconds: 2),
      );

      expect(socket.closed, isTrue);
    });

    test('asks for every search target', () async {
      socket.deliver(reply('192.168.1.77', 'uuid:roku:ecp:1GU48T017973'));

      await resolveDeviceAddress(
        known,
        bind: () async => socket,
        timeout: const Duration(seconds: 2),
      );

      final sent = socket.sent.map(utf8.decode).join();
      expect(sent, contains('ST: roku:ecp'));
      expect(sent, contains('ST: ssdp:all'));
      expect(sent, contains('M-SEARCH * HTTP/1.1'));
    });

    test('a device with no stable id is not looked for at all', () async {
      // Nothing to match an answer against, so any reply would be a guess.
      const manual = Device(
        id: '192.168.1.50:8060',
        name: 'Manual',
        type: DeviceType.roku,
        model: '',
        ip: '192.168.1.50',
        port: 8060,
      );

      var bound = false;
      final found = await resolveDeviceAddress(
        manual,
        bind: () async {
          bound = true;
          return socket;
        },
      );

      expect(found, isNull);
      expect(bound, isFalse, reason: 'no probe worth sending');
    });

    test('a socket that will not bind resolves to null, not a throw', () async {
      final found = await resolveDeviceAddress(
        known,
        bind: () async => throw const SocketException('no interface'),
      );

      expect(found, isNull);
    });
  });
}
