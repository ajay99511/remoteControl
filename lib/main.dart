import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/error_handlers.dart';
import 'providers/connection_provider.dart';
import 'screens/device_scanner.dart';
import 'screens/remote.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  installErrorHandlers();

  // Set once at startup. This is a platform-channel call and a side effect;
  // it does not belong in build(), which reruns on every state change.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF09090B),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  /// Built once. GoogleFonts.interTextTheme copies all 15 TextStyle slots of
  /// the dark text theme, which is far too much work to redo per frame.
  static final ThemeData _theme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF09090B),
    colorScheme: const ColorScheme.dark(
      primary: Colors.indigoAccent,
      surface: Color(0xFF18181B),
    ),
    textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch only what selects the route. Watching the whole state rebuilt the
    // entire MaterialApp on every retry and every errorMessage change.
    final isConnected = ref.watch(
      connectionProvider.select((s) => s.status == ConnectionStatus.connected),
    );
    final device = ref.watch(connectionProvider.select((s) => s.device));

    return MaterialApp(
      title: 'Universal Remote',
      debugShowCheckedModeBanner: false,
      theme: _theme,
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: isConnected && device != null
            ? RemoteScreen(
                key: ValueKey(device.id),
                device: device,
                onDisconnect: () =>
                    ref.read(connectionProvider.notifier).disconnect(),
              )
            : const DeviceScannerScreen(),
      ),
    );
  }
}
