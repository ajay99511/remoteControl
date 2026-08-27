import 'package:flutter_test/flutter_test.dart';

import 'package:devicecontroller/models/device.dart';
import 'package:devicecontroller/providers/discovery_parsers.dart';

void main() {
  String ssdp(List<String> headers) =>
      ['HTTP/1.1 200 OK', ...headers, '', ''].join('\r\n');

  group('parseSsdpResponse', () {
    test('maps a Roku SERVER header to port 8060', () {
      final device = parseSsdpResponse(
        ssdp([
          'SERVER: Roku UPnP/1.0 MiniUPnPd/1.4',
          'LOCATION: http://192.168.1.50:8060/',
        ]),
        '192.168.1.50',
      );

      expect(device?.type, DeviceType.roku);
      expect(device?.port, 8060);
      expect(device?.ip, '192.168.1.50');
    });

    test('maps a webOS SERVER header to LG on 3000', () {
      final device = parseSsdpResponse(
        ssdp(['SERVER: WebOS/1.0 UPnP/1.0']),
        '192.168.1.60',
      );

      expect(device?.type, DeviceType.lg);
      expect(device?.port, 3000);
    });

    test('honours the Samsung port named in LOCATION', () {
      final legacy = parseSsdpResponse(
        ssdp(['LOCATION: http://192.168.1.70:8001/api']),
        '192.168.1.70',
      );
      final modern = parseSsdpResponse(
        ssdp(['LOCATION: http://192.168.1.70:8002/api']),
        '192.168.1.70',
      );

      expect(legacy?.port, 8001);
      expect(modern?.port, 8002);
    });

    test('maps a Vizio LOCATION to 7345', () {
      final device = parseSsdpResponse(
        ssdp(['LOCATION: https://192.168.1.80:7345/']),
        '192.168.1.80',
      );

      expect(device?.type, DeviceType.vizio);
    });

    test('trusts the datagram source, not an address in the payload', () {
      // A hostile responder can claim any LOCATION it likes.
      final device = parseSsdpResponse(
        ssdp(['SERVER: Roku', 'LOCATION: http://10.9.9.9:8060/']),
        '192.168.1.50',
      );

      expect(device?.ip, '192.168.1.50');
    });

    test('ignores a non-200 response', () {
      expect(
        parseSsdpResponse('HTTP/1.1 404 Not Found\r\n\r\n', '10.0.0.1'),
        isNull,
      );
    });

    test('ignores a device it cannot control', () {
      expect(
        parseSsdpResponse(ssdp(['SERVER: SomePrinter/2.0']), '10.0.0.1'),
        isNull,
      );
    });

    test('survives a truncated header', () {
      expect(
        () => parseSsdpResponse(ssdp(['LOCATION:', 'SERVER:']), '10.0.0.1'),
        returnsNormally,
      );
    });

    test('survives a header with no colon at all', () {
      expect(
        () => parseSsdpResponse(ssdp(['GARBAGE']), '10.0.0.1'),
        returnsNormally,
      );
    });

    test('survives an empty body and an empty source', () {
      expect(parseSsdpResponse('', '10.0.0.1'), isNull);
      expect(parseSsdpResponse(ssdp(['SERVER: Roku']), ''), isNull);
    });

    test('accepts bare-LF line endings', () {
      final device = parseSsdpResponse(
        'HTTP/1.1 200 OK\nSERVER: Roku\n\n',
        '192.168.1.50',
      );

      expect(device?.type, DeviceType.roku);
    });
  });

  group('parseMdnsService', () {
    test('promotes a Roku on port 80 to 8060', () {
      final device = parseMdnsService(
        name: 'Roku Living Room',
        host: 'roku.local',
        port: 80,
        type: '_roku._tcp',
        addresses: ['192.168.1.50'],
      );

      expect(device?.type, DeviceType.roku);
      expect(device?.port, 8060);
    });

    test('prefers a resolved address over the hostname', () {
      final device = parseMdnsService(
        name: 'Samsung TV',
        host: 'tv.local',
        port: 8002,
        type: '_samsungtv._tcp',
        addresses: ['192.168.1.70'],
      );

      expect(device?.ip, '192.168.1.70');
    });

    test('falls back to the hostname when nothing resolved', () {
      final device = parseMdnsService(
        name: 'Samsung TV',
        host: 'tv.local',
        port: 8002,
        type: '_samsungtv._tcp',
      );

      expect(device?.ip, 'tv.local');
    });

    test('leaves an AirPlay responder unidentified', () {
      final device = parseMdnsService(
        name: 'Some Speaker',
        host: 'x.local',
        port: 7000,
        type: '_airplay._tcp',
        addresses: ['192.168.1.90'],
      );

      expect(device?.type, DeviceType.unknown);
    });

    test('rejects an announcement with no name or no address', () {
      expect(
        parseMdnsService(name: '', host: 'x.local', port: 80, type: '_roku._tcp'),
        isNull,
      );
      expect(
        parseMdnsService(name: 'Roku', host: '', port: 80, type: '_roku._tcp'),
        isNull,
      );
    });
  });

  group('mergeDiscovered', () {
    const roku = Device(
      id: '192.168.1.50:8060',
      name: 'Roku',
      type: DeviceType.roku,
      model: 'SSDP Discovered',
      ip: '192.168.1.50',
      port: 8060,
    );

    test('adds a host it has not seen', () {
      expect(mergeDiscovered(const [], roku), hasLength(1));
    });

    test('does not list one television twice on different ports', () {
      // mDNS normalises a Samsung to 8002 while SSDP may report 8001; keying
      // on (ip, port) produced two entries for one TV, only one of which
      // could connect.
      const sameTvOtherPort = Device(
        id: '192.168.1.50:80',
        name: 'Roku',
        type: DeviceType.roku,
        model: 'mDNS',
        ip: '192.168.1.50',
        port: 80,
      );

      final merged = mergeDiscovered([roku], sameTvOtherPort);

      expect(merged, hasLength(1));
      expect(merged.single.port, 8060, reason: 'the first answer wins');
    });

    test('upgrades an unknown type when a later probe identifies it', () {
      const unidentified = Device(
        id: '192.168.1.50:80',
        name: 'Unknown',
        type: DeviceType.unknown,
        model: 'airplay',
        ip: '192.168.1.50',
        port: 80,
      );

      final merged = mergeDiscovered([unidentified], roku);

      expect(merged.single.type, DeviceType.roku);
      expect(merged.single.port, 8060);
    });

    test('returns the same list when nothing changed', () {
      const known = [roku];

      expect(identical(mergeDiscovered(known, roku), known), isTrue);
    });

    test('keeps genuinely different hosts apart', () {
      const other = Device(
        id: '192.168.1.51:8060',
        name: 'Bedroom Roku',
        type: DeviceType.roku,
        model: 'SSDP Discovered',
        ip: '192.168.1.51',
        port: 8060,
      );

      expect(mergeDiscovered([roku], other), hasLength(2));
    });
  });
}
