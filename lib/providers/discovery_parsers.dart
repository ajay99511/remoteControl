import '../models/device.dart';

/// Pure parsing of discovery responses into [Device]s.
///
/// Separated from [ScannerNotifier] because this is the code that ingests
/// input from anything on the local network, and it was previously unreachable
/// from a test: the only scanner test had an empty body and a comment saying
/// the private method could not be called cleanly.
///
/// Every function here returns null rather than throwing. A malformed or
/// hostile response from one host must not take a whole scan down.

/// Parses one SSDP `M-SEARCH` response.
///
/// [sourceIp] is the datagram's source address, trusted over any address the
/// payload claims. Returns null when the response is not a success, or names
/// no device type we can control.
Device? parseSsdpResponse(String response, String sourceIp) {
  if (sourceIp.isEmpty) return null;
  if (!response.toUpperCase().contains('HTTP/1.1 200 OK')) return null;

  final headers = _parseHeaders(response);
  final server = (headers['SERVER'] ?? '').toLowerCase();
  final location = (headers['LOCATION'] ?? '').toLowerCase();

  final DeviceType type;
  final String name;
  final int port;

  if (server.contains('roku') || location.contains(':8060')) {
    type = DeviceType.roku;
    name = 'Roku Device';
    port = 8060;
  } else if (server.contains('samsung') ||
      location.contains('samsung') ||
      location.contains(':8001') ||
      location.contains(':8002')) {
    type = DeviceType.samsung;
    name = 'Samsung TV';
    port = location.contains(':8001') ? 8001 : 8002;
  } else if (server.contains('webos') || location.contains(':3000')) {
    type = DeviceType.lg;
    name = 'LG webOS TV';
    port = 3000;
  } else if (location.contains(':7345')) {
    type = DeviceType.vizio;
    name = 'Vizio SmartCast TV';
    port = 7345;
  } else {
    return null;
  }

  return Device(
    id: '$sourceIp:$port',
    name: name,
    type: type,
    model: 'SSDP Discovered',
    ip: sourceIp,
    port: port,
  );
}

/// Splits an SSDP response into upper-cased header keys.
///
/// Splits on `\r?\n` rather than `\r\n`: a responder that terminates lines
/// with bare LF used to yield no parsed headers at all, so the device was
/// silently missed rather than listed.
///
/// Generic key/value parsing also replaces the fixed-width `substring(7)` /
/// `substring(9)` reads. Those were safe - the `startsWith` guard bounds them -
/// but they only ever recognised two header names.
Map<String, String> _parseHeaders(String response) {
  final headers = <String, String>{};
  for (final line in response.split(RegExp(r'\r?\n'))) {
    final separator = line.indexOf(':');
    if (separator <= 0) continue;
    final key = line.substring(0, separator).trim().toUpperCase();
    headers[key] = line.substring(separator + 1).trim();
  }
  return headers;
}

/// Parses one mDNS/NSD service announcement.
///
/// [addresses] are the resolved IPs, preferred over [host] when present.
Device? parseMdnsService({
  required String name,
  required String host,
  required int port,
  required String type,
  List<String> addresses = const [],
}) {
  final ip = addresses.isNotEmpty ? addresses.first : host;
  if (name.isEmpty || ip.isEmpty) return null;

  final lowerName = name.toLowerCase();
  var deviceType = DeviceType.unknown;
  var resolvedPort = port;

  if (port == 8060 || lowerName.contains('roku') || type.contains('_roku')) {
    deviceType = DeviceType.roku;
    if (resolvedPort == 80 || resolvedPort == 0) resolvedPort = 8060;
  } else if (lowerName.contains('samsung') || type.contains('samsung')) {
    deviceType = DeviceType.samsung;
    if (resolvedPort == 80 || resolvedPort == 0) resolvedPort = 8002;
  } else if (type.contains('_googlecast')) {
    deviceType = DeviceType.googleTv;
  }
  // _airplay announcements carry no vendor, so they stay unknown.

  return Device(
    id: '$ip:$resolvedPort',
    name: name,
    type: deviceType,
    model: type.replaceAll('._tcp', '').replaceAll('_', ''),
    ip: ip,
    port: resolvedPort,
  );
}

/// Merges [candidate] into [known], keyed by host.
///
/// Deduping on (ip, port) let one television appear two or three times: mDNS
/// normalises a Samsung to 8002 while SSDP may report 8001, and an `_http._tcp`
/// responder keeps port 80 where its SSDP record says 8060. The user then saw
/// several entries for one TV, some of which connected and some of which did
/// not.
///
/// A later announcement only fills gaps; it never overwrites a more specific
/// answer that arrived first.
List<Device> mergeDiscovered(List<Device> known, Device candidate) {
  final index = known.indexWhere((d) => d.ip == candidate.ip);
  if (index < 0) return [...known, candidate];

  final existing = known[index];
  final merged = existing.copyWith(
    type: existing.type == DeviceType.unknown ? candidate.type : existing.type,
    name: existing.name.isEmpty ? candidate.name : existing.name,
    port:
        existing.type == DeviceType.unknown &&
            candidate.type != DeviceType.unknown
        ? candidate.port
        : existing.port,
  );
  if (merged == existing) return known;

  final next = [...known];
  next[index] = merged;
  return next;
}
