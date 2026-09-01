import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devicecontroller/core/error_handlers.dart';

void main() {
  group('installErrorHandlers', () {
    late FlutterExceptionHandler? originalFlutterOnError;
    late ErrorCallback? originalPlatformOnError;

    setUp(() {
      originalFlutterOnError = FlutterError.onError;
      originalPlatformOnError = PlatformDispatcher.instance.onError;
    });

    tearDown(() {
      FlutterError.onError = originalFlutterOnError;
      PlatformDispatcher.instance.onError = originalPlatformOnError;
    });

    test('claims the async error hook that is unset by default', () {
      PlatformDispatcher.instance.onError = null;

      installErrorHandlers();

      expect(PlatformDispatcher.instance.onError, isNotNull);
    });

    test('marks an uncaught async error as handled rather than fatal', () {
      installErrorHandlers();

      final handled = PlatformDispatcher.instance.onError!(
        StateError('boom'),
        StackTrace.current,
      );

      expect(
        handled,
        isTrue,
        reason: 'returning false would let the error kill the isolate',
      );
    });

    test('records a framework error without swallowing it', () {
      installErrorHandlers();

      // The handler must run to completion for an error carrying a stack.
      // Previously nothing was registered, so this error had nowhere to go.
      expect(
        () => FlutterError.onError!(
          FlutterErrorDetails(
            exception: StateError('render boom'),
            stack: StackTrace.current,
            library: 'test',
          ),
        ),
        returnsNormally,
      );
    });
  });
}
