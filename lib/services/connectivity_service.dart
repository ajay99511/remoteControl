import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Wraps connectivity_plus and WidgetsBindingObserver to emit network
/// lifecycle events to subscribers.
class ConnectivityService with WidgetsBindingObserver {
  final _controller = StreamController<List<ConnectivityResult>>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _sub;

  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;

  ConnectivityService() {
    WidgetsBinding.instance.addObserver(this);
    _sub = Connectivity()
        .onConnectivityChanged
        .listen(_controller.add);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Emit a wifi result to trigger reconnect check on resume.
      _controller.add([ConnectivityResult.wifi]);
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
