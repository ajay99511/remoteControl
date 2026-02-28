import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'models/device.dart';
import 'screens/device_scanner.dart';
import 'screens/remote.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Device? connectedDevice;
  bool isLoading = true;
  final _storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _loadSavedDevice();
  }

  Future<void> _loadSavedDevice() async {
    try {
      final String? deviceJson = await _storage.read(key: 'connected_device');
      if (deviceJson != null) {
        setState(() {
          connectedDevice = Device.fromJson(jsonDecode(deviceJson));
        });
      }
    } catch (e) {
      debugPrint('Error loading saved device: $e');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _handleConnect(Device device) async {
    setState(() {
      connectedDevice = device;
    });
    try {
      await _storage.write(
        key: 'connected_device',
        value: jsonEncode(device.toJson()),
      );
    } catch (e) {
      debugPrint('Error saving device: $e');
    }
  }

  Future<void> _handleDisconnect() async {
    setState(() {
      connectedDevice = null;
    });
    try {
      await _storage.delete(key: 'connected_device');
    } catch (e) {
      debugPrint('Error deleting saved device: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Set system overlay style for dark theme
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFF09090B),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    return MaterialApp(
      title: 'Universal Remote',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF09090B),
        colorScheme: const ColorScheme.dark(
          primary: Colors.indigoAccent,
          surface: Color(0xFF18181B),
        ),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      ),
      home: isLoading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: connectedDevice == null
                  ? DeviceScannerScreen(onConnect: _handleConnect)
                  : RemoteScreen(
                      key: ValueKey(connectedDevice!.id),
                      device: connectedDevice!,
                      onDisconnect: _handleDisconnect,
                    ),
            ),
    );
  }
}
