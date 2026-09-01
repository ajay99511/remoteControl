import 'package:flutter_test/flutter_test.dart';

import 'package:devicecontroller/services/device_description.dart';

void main() {
  // A UPnP root description, shaped as a TV actually serves it at LOCATION.
  const upnpRoot = '''
<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <specVersion><major>1</major><minor>0</minor></specVersion>
  <device>
    <deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
    <friendlyName>Living Room</friendlyName>
    <manufacturer>Samsung Electronics</manufacturer>
    <modelName>UN55TU8000</modelName>
    <UDN>uuid:0d1a1b2c-3d4e-5f60-7182-93a4b5c6d7e8</UDN>
  </device>
</root>''';

  // Roku ECP query/device-info uses hyphenated element names.
  const rokuDeviceInfo = '''
<device-info>
  <udn>015e5108-9000-1046-8035-b0a737964dfb</udn>
  <serial-number>1GU48T017973</serial-number>
  <model-name>Roku Ultra</model-name>
  <friendly-device-name>Bedroom Roku</friendly-device-name>
  <power-mode>PowerOn</power-mode>
</device-info>''';

  group('parseDeviceDescription', () {
    test('reads a UPnP root description', () {
      final d = parseDeviceDescription(upnpRoot);

      expect(d.friendlyName, 'Living Room');
      expect(d.modelName, 'UN55TU8000');
      expect(d.manufacturer, 'Samsung Electronics');
      expect(d.udn, 'uuid:0d1a1b2c-3d4e-5f60-7182-93a4b5c6d7e8');
    });

    test('reads Roku ECP hyphenated element names', () {
      final d = parseDeviceDescription(rokuDeviceInfo);

      expect(d.friendlyName, 'Bedroom Roku');
      expect(d.modelName, 'Roku Ultra');
      expect(d.serialNumber, '1GU48T017973');
    });

    test('resolves XML entities in a name', () {
      // "Dad's TV" arrives escaped, and would otherwise display raw.
      final d = parseDeviceDescription(
        '<device><friendlyName>Dad&apos;s TV &amp; Soundbar</friendlyName>'
        '</device>',
      );

      expect(d.friendlyName, "Dad's TV & Soundbar");
    });

    test('tolerates attributes on the element', () {
      final d = parseDeviceDescription(
        '<friendlyName xml:lang="en">Kitchen</friendlyName>',
      );

      expect(d.friendlyName, 'Kitchen');
    });

    test('reports empty for a document with nothing useful', () {
      expect(parseDeviceDescription('<root></root>').isEmpty, isTrue);
      expect(parseDeviceDescription('').isEmpty, isTrue);
    });

    test('does not throw on malformed markup from an unknown host', () {
      // Anything on the LAN can answer a broadcast; a bad document must not
      // take the scan down.
      expect(
        () => parseDeviceDescription('<friendlyName>unclosed'),
        returnsNormally,
      );
      expect(() => parseDeviceDescription('<<<>>>'), returnsNormally);
    });
  });

  group('stableId', () {
    test('prefers the UDN and strips the uuid: scheme', () {
      expect(
        parseDeviceDescription(upnpRoot).stableId,
        'ssdp:0d1a1b2c-3d4e-5f60-7182-93a4b5c6d7e8',
      );
    });

    test('uses the serial when no UDN is offered', () {
      const d = DeviceDescription(serialNumber: '1GU48T017973');

      // Case is preserved: only the uuid: prefix check is case-insensitive.
      expect(d.stableId, 'ssdp:1GU48T017973');
    });

    test('is null when the device identifies itself with nothing', () {
      expect(const DeviceDescription(friendlyName: 'TV').stableId, isNull);
    });
  });
}
