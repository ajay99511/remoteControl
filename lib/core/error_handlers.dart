import 'package:flutter/foundation.dart';

import 'app_logger.dart';

/// Routes every uncaught error to [log] so nothing is discarded silently.
///
/// Without these handlers an exception thrown inside a stream `onData`
/// callback escapes to the enclosing Zone and vanishes in release builds.
/// That is exactly how the unreachable-pong defect (audit C-1) stayed
/// invisible in the field despite firing on every connection.
///
/// This is the seam where a crash reporter would be attached. None is wired
/// up yet - adding that dependency is a separate, deliberate decision.
void installErrorHandlers() {
  FlutterError.onError = (details) {
    // Keep the framework's own console presentation in debug, then record it.
    FlutterError.presentError(details);
    log.e('flutter_error', details.exception, details.stack);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    log.e('uncaught_async_error', error, stack);
    // Reported rather than rethrown: an uncaught async error should not take
    // the isolate down when the UI is still usable.
    return true;
  };
}
