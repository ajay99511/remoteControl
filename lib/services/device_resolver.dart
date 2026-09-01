import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_logger.dart';
import '../models/device.dart';
import '../providers/discovery_parsers.dart';
import 'ssdp.dart';

/// Finds a device the user already knows, wherever it is now.
///
/// A remembered device carries the address it held when it was last seen, and
/// a router is free to hand that address to something else overnight. Without
/// this, reconnecting meant five attempts against whatever now lives there -
/// fifteen seconds of backoff ending in "could not connect", for a television
/// that was powered on and two addresses away the whole time.
///
/// Returns [known] with its address corrected, or null if it did not answer.
/// Never throws: failing to re-find a device is an ordinary outcome, not an
/// error the caller should have to handle.
typedef DeviceAddressResolver = Future<Device?> Function(Device known);

const _probeRounds = 2;
const _probeInterval = Duration(milliseconds: 400);

Future<Device?> resolveDeviceAddress(
  Device known, {
  required DatagramSocketBinder bind,
  Duration timeout = const Duration(seconds: 3),
}) async {
  // Without a stable identity there is nothing to match an answer against,
  // and connecting to whatever replied first is how a remote ends up driving
  // the neighbour's television.
  final uid = known.uid;
  if (uid == null) return null;

  RawDatagramSocket? socket;
  StreamSubscription<RawSocketEvent>? sub;
  Timer? deadline;
  final result = Completer<Device?>();

  try {
    socket = await bind();
    socket.broadcastEnabled = true;
    final bound = socket;

    sub = bound.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = bound.receive();
      if (datagram == null) return;
      try {
        final seen = parseSsdpResponse(
          utf8.decode(datagram.data),
          datagram.address.address,
        );
        if (seen?.uid != uid || result.isCompleted) return;
        result.complete(
          // Only the address the router controls is adopted. The name, the
          // model and the port this device was paired on are ours already,
          // and a rediscovery should not quietly overwrite them.
          known.copyWith(ip: seen!.ip, port: known.port ?? seen.port),
        );
      } on FormatException catch (e) {
        log.d('DeviceResolver: undecodable datagram ignored', e);
      }
    });

    deadline = Timer(timeout, () {
      if (!result.isCompleted) result.complete(null);
    });

    unawaited(_probe(bound, result));
    final found = await result.future;
    return found;
  } catch (e, s) {
    log.d('DeviceResolver: could not look for ${known.name}', e, s);
    return null;
  } finally {
    deadline?.cancel();
    // Not awaited: nothing here depends on the cancellation completing, and
    // the socket is closed immediately after regardless. Matches how the
    // scanner releases its own SSDP subscription.
    unawaited(sub?.cancel() ?? Future<void>.value());
    socket?.close();
  }
}

/// Sends the M-SEARCH rounds, stopping as soon as the answer is in.
Future<void> _probe(RawDatagramSocket socket, Completer<Device?> result) async {
  final multicast = InternetAddress(ssdpMulticastAddress);
  for (var round = 0; round < _probeRounds; round++) {
    for (final target in ssdpSearchTargets) {
      if (result.isCompleted) return;
      try {
        socket.send(utf8.encode(ssdpMSearch(target)), multicast, ssdpPort);
      } catch (e) {
        // The socket is closed the moment an answer arrives; a send racing
        // that close is expected, not a failure to report.
        log.d('DeviceResolver: probe send failed', e);
        return;
      }
    }
    if (round < _probeRounds - 1) {
      await Future<void>.delayed(_probeInterval);
    }
  }
}

/// The production resolver.
final deviceAddressResolverProvider = Provider<DeviceAddressResolver>((ref) {
  final bind = ref.watch(ssdpSocketBinderProvider);
  return (device) => resolveDeviceAddress(device, bind: bind);
});
