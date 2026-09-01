import 'package:http/http.dart' as http;

import '../core/app_logger.dart';

/// What a device says about itself.
///
/// Both discovery protocols point at a self-description and this app was
/// ignoring both: SSDP responses carry a `LOCATION` URL serving a UPnP device
/// description, and Roku's ECP `query/device-info` returns the same kind of
/// document. Without reading them the scanner had to invent names, so every
/// Samsung on the network appeared identically as "Samsung TV" and a house
/// with two of them produced two indistinguishable rows.
class DeviceDescription {
  /// The name the owner gave the device on the TV itself.
  final String? friendlyName;
  final String? modelName;
  final String? manufacturer;

  /// Unique Device Name. UPnP's canonical identity, `uuid:<...>`.
  final String? udn;

  /// Roku reports a serial; most UPnP devices do not.
  final String? serialNumber;

  const DeviceDescription({
    this.friendlyName,
    this.modelName,
    this.manufacturer,
    this.udn,
    this.serialNumber,
  });

  bool get isEmpty =>
      friendlyName == null &&
      modelName == null &&
      manufacturer == null &&
      udn == null &&
      serialNumber == null;

  /// The most stable identifier this description offers, normalised to match
  /// the `ssdp:` namespace discovery already uses.
  String? get stableId {
    final canonical = udn ?? serialNumber;
    if (canonical == null || canonical.isEmpty) return null;
    final withoutScheme = canonical.toLowerCase().startsWith('uuid:')
        ? canonical.substring(5).trim()
        : canonical.trim();
    return withoutScheme.isEmpty ? null : 'ssdp:$withoutScheme';
  }

  @override
  String toString() =>
      'DeviceDescription(friendlyName: $friendlyName, model: $modelName, '
      'udn: $udn)';
}

/// Reads a UPnP device description or a Roku ECP device-info document.
///
/// Deliberately a tolerant leaf-element scan rather than a full XML parse.
/// Both documents are machine-generated, flat, and use unnamespaced element
/// names for the handful of fields wanted here, so a parser dependency would
/// buy accuracy this does not need. If the shape ever stops being predictable,
/// that judgement should be revisited rather than patched around.
DeviceDescription parseDeviceDescription(String xml) {
  String? first(List<String> tags) {
    for (final tag in tags) {
      final value = _element(xml, tag);
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  return DeviceDescription(
    // UPnP says <friendlyName>; Roku ECP says <friendly-device-name>, and
    // falls back to the model name when the owner never renamed it.
    friendlyName: first([
      'friendlyName',
      'friendly-device-name',
      'user-device-name',
    ]),
    modelName: first(['modelName', 'model-name', 'modelDescription']),
    manufacturer: first(['manufacturer', 'vendor-name']),
    udn: first(['UDN', 'udn']),
    serialNumber: first(['serialNumber', 'serial-number']),
  );
}

/// Extracts the text of the first `<tag>…</tag>`, or null.
String? _element(String xml, String tag) {
  final escaped = RegExp.escape(tag);
  final match = RegExp(
    '<$escaped(?:\\s[^>]*)?>(.*?)</$escaped>',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(xml);
  if (match == null) return null;
  return _unescape(match.group(1)!.trim());
}

/// Resolves the five predefined XML entities. Device descriptions routinely
/// contain them - an apostrophe in "Dad's TV" arrives as `&apos;`.
String _unescape(String value) => value
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

/// Fetches a device's self-description. Returns null on any failure.
///
/// Injected as [DeviceDescriptionFetcher] so the scanner can be tested
/// without a network.
typedef DeviceDescriptionFetcher = Future<DeviceDescription?> Function(Uri);

/// Ceiling on a description body. These documents are a couple of kilobytes;
/// anything larger is a host on the LAN that answered a broadcast with
/// something we should not be reading into memory.
const _maxDescriptionBytes = 64 * 1024;

/// Best-effort fetch of the UPnP / ECP description at [location].
Future<DeviceDescription?> fetchDeviceDescription(
  Uri location, {
  http.Client? client,
  Duration timeout = const Duration(seconds: 3),
}) async {
  final httpClient = client ?? http.Client();
  try {
    final response = await httpClient.get(location).timeout(timeout);
    if (response.statusCode != 200) return null;
    if (response.bodyBytes.length > _maxDescriptionBytes) {
      log.w('DeviceDescription: oversized document from $location, ignoring');
      return null;
    }
    final description = parseDeviceDescription(response.body);
    return description.isEmpty ? null : description;
  } catch (e) {
    // A device that will not describe itself is still usable; the scanner
    // falls back to the name it inferred from the SERVER header.
    log.d('DeviceDescription: could not read $location - $e');
    return null;
  } finally {
    if (client == null) httpClient.close();
  }
}
