import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:devicecontroller/main.dart';

void main() {
  testWidgets('App smoke test - Scanner screen', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(
        child: MyApp(),
      ),
    );

    // Verify Discover title
    expect(find.text('Discover'), findsOneWidget);

    // Verify buttons
    expect(find.text('Rescan'), findsOneWidget);
    expect(find.text('Manual IP'), findsOneWidget);

    // Tap Manual IP
    await tester.tap(find.text('Manual IP'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500)); // Wait for dialog animation

    // Verify dialog
    expect(find.text('Connect via IP'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);

    // Close dialog
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Wait for discovery timer (10s) and other async tasks
    await tester.pump(const Duration(seconds: 11));

    // Final pump to clear any remaining frame tasks
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
