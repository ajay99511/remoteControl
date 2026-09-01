import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The SSDP wire details, in one place.
///
/// Two things speak SSDP: the scanner's discovery sweep, and the resolver
/// that re-finds a device the user already knows after its address changes.
/// They must ask the same question the same way, so the targets, the port and
/// the request format live here rather than in either of them.

const ssdpMulticastAddress = '239.255.255.250';
const ssdpPort = 1900;

/// Search targets, most specific first.
///
/// `ssdp:all` alone asks every UPnP device on the segment to answer, which is
/// noisy, slower to filter, and something some access points rate-limit. Real
/// remotes ask for what they can control: Roku defines `roku:ecp`, and DIAL is
/// the multiscreen standard Roku, Samsung and Vizio all implement. `ssdp:all`
/// stays last so anything not covered still turns up.
const ssdpSearchTargets = [
  'roku:ecp',
  'urn:dial-multiscreen-org:service:dial:1',
  'urn:schemas-upnp-org:device:MediaRenderer:1',
  'ssdp:all',
];

/// An M-SEARCH request for one search target.
///
/// [mx] is the maximum seconds a device may wait before replying; UPnP
/// requires 1-5. Two keeps a sweep responsive without bunching every device's
/// answer into the same instant.
String ssdpMSearch(String searchTarget, {int mx = 2}) =>
    'M-SEARCH * HTTP/1.1\r\n'
    'HOST: $ssdpMulticastAddress:$ssdpPort\r\n'
    'MAN: "ssdp:discover"\r\n'
    'MX: $mx\r\n'
    'ST: $searchTarget\r\n\r\n';

/// Binds the UDP socket an SSDP probe listens on.
///
/// Injected so both callers can be tested without touching the network.
typedef DatagramSocketBinder = Future<RawDatagramSocket> Function();

final ssdpSocketBinderProvider = Provider<DatagramSocketBinder>(
  (_) =>
      () => RawDatagramSocket.bind(InternetAddress.anyIPv4, 0),
);
