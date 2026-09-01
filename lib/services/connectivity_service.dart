import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True when at least one of [results] can reach a device on the local
/// network.
///
/// Every controller in this app talks to a private address on the same LAN.
/// Cellular and VPN transports cannot reach one, so treating "not none" as
/// "reconnect now" sent the app into a full retry chain - five attempts, each
/// with a 3-second timeout, plus backoff - every time the user walked out of
/// the house and dropped to mobile data.
bool canReachLocalNetwork(List<ConnectivityResult> results) =>
    results.contains(ConnectivityResult.wifi) ||
    results.contains(ConnectivityResult.ethernet);

/// Wraps connectivity_plus and WidgetsBindingObserver to emit network
/// lifecycle events to subscribers.
class ConnectivityService with WidgetsBindingObserver {
  final Connectivity _connectivity;
  final _controller = StreamController<List<ConnectivityResult>>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _sub;

  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;

  ConnectivityService({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity() {
    WidgetsBinding.instance.addObserver(this);
    _sub = _connectivity.onConnectivityChanged.listen(_controller.add);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Ask what the connectivity actually is rather than asserting wifi.
    // Emitting a hardcoded [wifi] on every resume put a value on this stream
    // that was frequently untrue, and it was the reason the reconnect chain
    // fired after every foreground regardless of the real transport.
    unawaited(_emitCurrentState());
  }

  Future<void> _emitCurrentState() async {
    try {
      final results = await _connectivity.checkConnectivity();
      if (!_controller.isClosed) _controller.add(results);
    } catch (_) {
      // A failed probe is not worth surfacing: the stream stays quiet and the
      // next real connectivity event will correct us.
    }
  }

  void dispose() {
    _sub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _controller.close();
  }
}

/// Riverpod provider for ConnectivityService.
final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  final svc = ConnectivityService();
  ref.onDispose(svc.dispose);
  return svc;
});
