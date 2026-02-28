import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../models/device.dart';

class DeviceScannerScreen extends StatefulWidget {
  final Function(Device) onConnect;

  const DeviceScannerScreen({super.key, required this.onConnect});

  @override
  State<DeviceScannerScreen> createState() => _DeviceScannerScreenState();
}

class _DeviceScannerScreenState extends State<DeviceScannerScreen> {
  bool isScanning = true;
  List<Device> devices = [];

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  void _startScan() {
    setState(() {
      isScanning = true;
      devices = [];
    });

    // Simulate scanning
    Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          isScanning = false;
          devices = [
            Device(
              id: '1',
              name: 'Living Room TV',
              type: 'wifi',
              model: 'Samsung QLED 4K',
              signal: 90,
            ),
            Device(
              id: '2',
              name: 'Bedroom TV',
              type: 'wifi',
              model: 'LG WebOS',
              signal: 75,
            ),
            Device(
              id: '3',
              name: 'Office Cast',
              type: 'bluetooth',
              model: 'Chromecast Ultra',
              signal: 60,
            ),
          ];
        });
      }
    });
  }

  void _handleManualConnect() {
    showDialog(
      context: context,
      builder: (context) {
        final TextEditingController ipController = TextEditingController();
        return AlertDialog(
          backgroundColor: const Color(0xFF18181B),
          title: const Text(
            'Connect via IP',
            style: TextStyle(color: Colors.white),
          ),
          content: TextField(
            controller: ipController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'e.g., 192.168.1.105',
              hintStyle: TextStyle(color: Colors.grey),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.grey),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.indigo),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                if (ipController.text.isNotEmpty) {
                  Navigator.pop(context);
                  widget.onConnect(
                    Device(
                      id: 'manual-${DateTime.now().millisecondsSinceEpoch}',
                      name: 'Manual Device',
                      type: 'wifi',
                      model: ipController.text,
                      signal: 100,
                    ),
                  );
                }
              },
              child: const Text(
                'Connect',
                style: TextStyle(color: Colors.indigoAccent),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Simulation Mode Badge
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF18181B).withValues(alpha: 0.8),
                  border: Border.all(color: const Color(0xFF27272A)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'SIMULATION MODE',
                  style: TextStyle(
                    color: Color(0xFF71717A),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Select Device',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w300,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Scanning for nearby displays...',
                    style: TextStyle(color: Color(0xFF71717A)),
                  ),
                  const SizedBox(height: 48),
                  Expanded(
                    child: isScanning
                        ? _buildScanningAnimation()
                        : _buildDeviceList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanningAnimation() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.indigo.withValues(alpha: 0.5),
                      ),
                    ),
                  )
                  .animate(onPlay: (controller) => controller.repeat())
                  .scale(
                    duration: 2.seconds,
                    begin: const Offset(1, 1),
                    end: const Offset(2, 2),
                  )
                  .fadeOut(duration: 2.seconds),
              Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.indigo.withValues(alpha: 0.3),
                      ),
                    ),
                  )
                  .animate(
                    onPlay: (controller) => controller.repeat(),
                    delay: 500.ms,
                  )
                  .scale(
                    duration: 2.seconds,
                    begin: const Offset(1, 1),
                    end: const Offset(1.5, 1.5),
                  )
                  .fadeOut(duration: 2.seconds),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: const Color(0xFF18181B),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF27272A)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.indigo.withValues(alpha: 0.1),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Icon(
                  LucideIcons.search,
                  color: Colors.indigoAccent,
                  size: 32,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          const Text(
                'DISCOVERING...',
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: Color(0xFF71717A),
                  letterSpacing: 1.5,
                ),
              )
              .animate(onPlay: (controller) => controller.repeat(reverse: true))
              .fadeIn()
              .fadeOut(delay: 1.seconds),
        ],
      ),
    );
  }

  Widget _buildDeviceList() {
    return Column(
      children: [
        ...devices.map((device) => _buildDeviceItem(device)),
        const SizedBox(height: 24),
        const Divider(color: Color(0xFF27272A)),
        const SizedBox(height: 16),
        _buildActionButton(
          icon: LucideIcons.refreshCw,
          label: 'Scan Again',
          onTap: _startScan,
        ),
        const SizedBox(height: 12),
        _buildActionButton(
          icon: LucideIcons.smartphone,
          label: 'Connect via IP',
          onTap: _handleManualConnect,
        ),
      ],
    ).animate().fadeIn(duration: 500.ms).moveY(begin: 20, end: 0);
  }

  Widget _buildDeviceItem(Device device) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: const Color(0xFF18181B).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Color(0xFF27272A)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          onTap: () => widget.onConnect(device),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF27272A)),
                  ),
                  child: Icon(
                    device.type == 'wifi' ? LucideIcons.wifi : LucideIcons.cast,
                    color: device.type == 'wifi'
                        ? Colors.indigoAccent
                        : const Color(0xFF69F0AE),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.name,
                        style: const TextStyle(
                          color: Color(0xFFE4E4E7),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        device.model,
                        style: const TextStyle(
                          color: Color(0xFF71717A),
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(4, (index) {
                    final height = [30, 50, 70, 100][index];
                    final isActive = device.signal > (index * 25);
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      width: 4,
                      height: 12.0 * (height / 100),
                      decoration: BoxDecoration(
                        color: isActive
                            ? const Color(0xFF69F0AE)
                            : const Color(0xFF3F3F46),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFF18181B).withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: const Color(0xFFA1A1AA)),
              const SizedBox(width: 8),
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  color: Color(0xFFA1A1AA),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
