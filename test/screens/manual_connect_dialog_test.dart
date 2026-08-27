import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devicecontroller/models/device.dart';
import 'package:devicecontroller/screens/manual_connect_dialog.dart';

void main() {
  /// Opens the dialog on a real route so Navigator.pop results can be read.
  Future<Device?> showAndCapture(
    WidgetTester tester,
    Future<void> Function(WidgetTester tester) interact,
  ) async {
    Device? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showDialog<Device>(
                context: context,
                builder: (_) => const ManualConnectDialog(),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await interact(tester);
    return result;
  }

  Finder ipField() => find.byType(TextField).at(0);
  Finder portField() => find.byType(TextField).at(1);
  String portText(WidgetTester tester) =>
      tester.widget<TextField>(portField()).controller!.text;

  group('ManualConnectDialog.validateHost', () {
    test('accepts a dotted IPv4 address', () {
      expect(validateManualHost('192.168.1.105'), isNull);
    });

    test('accepts a compressed IPv6 address', () {
      // The previous regex required all eight groups, so this was rejected.
      expect(validateManualHost('fe80::1'), isNull);
    });

    test('rejects a dotless number the old regex accepted', () {
      expect(validateManualHost('1234'), isNotNull);
    });

    test('rejects an incomplete address', () {
      expect(validateManualHost('1.2.3'), isNotNull);
    });

    test('rejects an out-of-range octet', () {
      expect(validateManualHost('999.1.1.1'), isNotNull);
    });

    test(
      'reports empty input without shouting at a user who has not typed',
      () {
        expect(validateManualHost(''), isNotNull);
      },
    );
  });

  group('ManualConnectDialog', () {
    testWidgets(
      'keeps the caret in the port field while the IP field is edited',
      (tester) async {
        await showAndCapture(tester, (tester) async {
          await tester.enterText(portField(), '9999');
          await tester.pump();

          // Typing here used to hand the port field a brand-new controller on
          // every keystroke, whose selection defaulted to invalid - so the caret
          // jumped out of the field mid-entry.
          await tester.enterText(ipField(), '192.168.1.50');
          await tester.pump();

          final selection = tester
              .widget<TextField>(portField())
              .controller!
              .selection;
          expect(portText(tester), '9999');
          expect(
            selection.isValid,
            isTrue,
            reason: 'a rebuild must not discard the caret position',
          );
        });
      },
    );

    testWidgets('a cleared port field stays cleared', (tester) async {
      await showAndCapture(tester, (tester) async {
        await tester.enterText(portField(), '');
        await tester.pump();

        // The old pattern reseeded the field from state on the next rebuild,
        // and int.tryParse('') kept the previous value - so clearing the port
        // silently reverted it to 8060 behind the user's back.
        await tester.enterText(ipField(), '192.168.1.50');
        await tester.pump();

        expect(portText(tester), '');
      });
    });

    testWidgets('refuses to submit a port outside the valid range', (
      tester,
    ) async {
      final device = await showAndCapture(tester, (tester) async {
        await tester.enterText(ipField(), '192.168.1.50');
        await tester.pump();
        await tester.enterText(portField(), '');
        await tester.pump();
        await tester.tap(find.widgetWithText(ElevatedButton, 'Connect'));
        await tester.pumpAndSettle();
      });

      expect(device, isNull, reason: 'an empty port must not become a device');
      expect(find.textContaining('Port must be'), findsOneWidget);
    });

    testWidgets('applies the default port when the device type changes', (
      tester,
    ) async {
      await showAndCapture(tester, (tester) async {
        expect(portText(tester), '${kDefaultPorts[DeviceType.roku]}');

        await tester.tap(find.byType(DropdownButton<DeviceType>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('LG').last);
        await tester.pumpAndSettle();

        expect(portText(tester), '${kDefaultPorts[DeviceType.lg]}');
      });
    });

    testWidgets('keeps Connect disabled until the address parses', (
      tester,
    ) async {
      await showAndCapture(tester, (tester) async {
        ElevatedButton connectButton() => tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Connect'),
        );

        expect(connectButton().onPressed, isNull);

        await tester.enterText(ipField(), 'not-an-ip');
        await tester.pump();
        expect(connectButton().onPressed, isNull);

        await tester.enterText(ipField(), '192.168.1.50');
        await tester.pump();
        expect(connectButton().onPressed, isNotNull);
      });
    });

    testWidgets('returns the device the user described', (tester) async {
      final device = await showAndCapture(tester, (tester) async {
        await tester.enterText(ipField(), '10.0.0.7');
        await tester.pump();
        await tester.enterText(portField(), '8060');
        await tester.pump();
        await tester.tap(find.widgetWithText(ElevatedButton, 'Connect'));
        await tester.pumpAndSettle();
      });

      expect(device, isNotNull);
      expect(device!.ip, '10.0.0.7');
      expect(device.port, 8060);
      expect(device.type, DeviceType.roku);
    });

    testWidgets('returns nothing when cancelled', (tester) async {
      final device = await showAndCapture(tester, (tester) async {
        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await tester.pumpAndSettle();
      });

      expect(device, isNull);
    });
  });
}
