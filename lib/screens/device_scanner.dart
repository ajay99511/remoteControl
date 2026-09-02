import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_colors.dart';

import '../models/device.dart';
import 'manual_connect_dialog.dart';
import '../providers/connection_provider.dart';
import '../providers/scanner_provider.dart';
import '../widgets/ambient_background.dart';

class DeviceScannerScreen extends ConsumerStatefulWidget {
  const DeviceScannerScreen({super.key});

  @override
  ConsumerState<DeviceScannerScreen> createState() =>
      _DeviceScannerScreenState();
}

class _DeviceScannerScreenState extends ConsumerState<DeviceScannerScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(scannerProvider.notifier).startScan();
    });
  }

  Future<void> _handleManualConnect() async {
    final device = await showDialog<Device>(
      context: context,
      builder: (_) => const ManualConnectDialog(),
    );
    if (device == null || !mounted) return;
    await ref.read(connectionProvider.notifier).connect(device);
  }

  @override
  Widget build(BuildContext context) {
    final scanner = ref.watch(scannerProvider);
    final connection = ref.watch(connectionProvider);

    ref.listen(connectionProvider, (prev, next) {
      if (next.status == ConnectionStatus.error && next.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection failed: ${next.errorMessage}'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const AmbientBackground(),
          // Main Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 16.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 32),
                  const Text(
                        'Discover',
                        style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: -1,
                        ),
                        textAlign: TextAlign.center,
                      )
                      .animate()
                      .fadeIn(duration: 500.ms)
                      .moveY(begin: -20, end: 0),
                  const SizedBox(height: 8),
                  Text(
                    scanner.isScanning
                        ? 'Looking for nearby smart devices...'
                        : scanner.devices.isEmpty
                        ? 'No devices found'
                        : '${scanner.devices.length} nearby device(s) found',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ).animate().fadeIn(delay: 200.ms),
                  if (scanner.error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      scanner.error!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ).animate().fadeIn(),
                  ],
                  const SizedBox(height: 48),
                  Expanded(
                    child: scanner.isScanning && scanner.devices.isEmpty
                        ? _buildScanningAnimation()
                        : _buildDeviceList(
                            scanner.devices,
                            scanner.isScanning,
                            scanner.restored,
                          ),
                  ),
                  if (connection.status == ConnectionStatus.connecting)
                    Container(
                          margin: const EdgeInsets.only(top: 24),
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 24,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.indigoAccent,
                                ),
                              ),
                              SizedBox(width: 16),
                              Text(
                                'Connecting to device...',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        )
                        .animate()
                        .fadeIn(duration: 300.ms)
                        .slideY(begin: 0.2, end: 0),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanningAnimation() {
    // Isolated: this pulses forever while a scan runs, and without a
    // boundary it repaints everything sharing its layer.
    return RepaintBoundary(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.indigoAccent.withValues(alpha: 0.3),
                          width: 2,
                        ),
                      ),
                    )
                    .animate(onPlay: (controller) => controller.repeat())
                    .scale(
                      duration: 2.seconds,
                      begin: const Offset(1, 1),
                      end: const Offset(2.5, 2.5),
                    )
                    .fadeOut(duration: 2.seconds),
                Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.purpleAccent.withValues(alpha: 0.3),
                          width: 2,
                        ),
                      ),
                    )
                    .animate(
                      onPlay: (controller) => controller.repeat(),
                      delay: 600.ms,
                    )
                    .scale(
                      duration: 2.seconds,
                      begin: const Offset(1, 1),
                      end: const Offset(2.5, 2.5),
                    )
                    .fadeOut(duration: 2.seconds),
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        Colors.indigoAccent.withValues(alpha: 0.2),
                        Colors.purpleAccent.withValues(alpha: 0.2),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.indigoAccent.withValues(alpha: 0.2),
                        blurRadius: 30,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                  child: const Icon(
                    LucideIcons.radar,
                    color: Colors.white,
                    size: 48,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),
            const Text(
                  'Scanning Network...',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                    letterSpacing: 2.0,
                  ),
                )
                .animate(
                  onPlay: (controller) => controller.repeat(reverse: true),
                )
                .fadeIn(duration: 1.seconds)
                .fadeOut(duration: 1.seconds),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceList(
    List<Device> devices,
    bool isScanning,
    Set<String> restored,
  ) {
    return Column(
      children: [
        Expanded(
          child: devices.isEmpty
              ? const _NothingFound()
              : ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  itemCount: devices.length,
                  itemBuilder: (context, index) {
                    final device = devices[index];
                    // RepaintBoundary isolates each row so an animating
                    // neighbour does not dirty the whole list layer, and the
                    // stagger is capped: an unbounded index * 100ms delay
                    // meant the 20th device faded in two seconds late, and
                    // the animation restarted on every scroll recycle.
                    return RepaintBoundary(
                      child:
                          _buildDeviceItem(
                                device,
                                isRemembered: restored.contains(
                                  device.credentialKey,
                                ),
                              )
                              .animate()
                              .fadeIn(
                                duration: 400.ms,
                                delay: (math.min(index, 6) * 60).ms,
                              )
                              .slideX(begin: 0.1, end: 0),
                    );
                  },
                ),
        ),
        if (isScanning && devices.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.indigoAccent,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Still scanning...',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                icon: LucideIcons.refreshCw,
                label: 'Rescan',
                onTap: () async {
                  // stopScan is async: not awaiting it let startScan append
                  // new Discovery handles while the previous teardown was
                  // still in flight, orphaning them past the next stopScan.
                  final notifier = ref.read(scannerProvider.notifier);
                  await notifier.stopScan();
                  if (!context.mounted) return;
                  await notifier.startScan();
                },
                isPrimary: true,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildActionButton(
                icon: LucideIcons.plus,
                label: 'Manual IP',
                onTap: _handleManualConnect,
                isPrimary: false,
              ),
            ),
          ],
        ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.2, end: 0),
      ],
    );
  }

  /// Explains why a row cannot be tapped, instead of swallowing the tap.
  void _explainUnsupported(Device device) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${device.name} is a ${device.type.label} device, which is not '
          'supported yet.',
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildDeviceItem(Device device, {required bool isRemembered}) {
    // Discovery lists whatever answers, including hosts with no transport
    // here. Offering them as ordinary rows meant a user picked their
    // Chromecast, waited, and was told it failed - when the controller throws
    // on the first line of connect() and never had a chance.
    final controllable = device.type.isControllable;
    return Opacity(
      // Reads as inert before it is touched, not only after.
      opacity: controllable ? 1 : 0.55,
      child: _deviceCard(device, isRemembered, controllable),
    );
  }

  Widget _deviceCard(Device device, bool isRemembered, bool controllable) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Semantics(
        label:
            '${device.name}, ${device.type.name} device, ${device.model}'
            '${isRemembered ? ', saved, not seen on this network yet' : ''}'
            '${controllable ? '' : ', not supported'}',
        hint: controllable
            ? 'Connect to this device'
            : 'This device type is not supported yet',
        enabled: controllable,
        button: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            highlightColor: Colors.white.withValues(alpha: 0.05),
            splashColor: Colors.indigoAccent.withValues(alpha: 0.2),
            onTap: controllable
                ? () => ref.read(connectionProvider.notifier).connect(device)
                : () => _explainUnsupported(device),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: _deviceColor(device.type).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _deviceColor(device.type).withValues(alpha: 0.5),
                      ),
                    ),
                    child: Icon(
                      _deviceIcon(device.type),
                      color: _deviceColor(device.type),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          device.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                device.model,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.6),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            // A remembered device is shown before the network
                            // has confirmed it, so the row has to be honest
                            // about which of the two it is.
                            if (!controllable) ...[
                              const SizedBox(width: 8),
                              const _RowBadge('Not supported'),
                            ] else if (isRemembered) ...[
                              const SizedBox(width: 8),
                              const _RowBadge('Saved'),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    LucideIcons.chevronRight,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _deviceIcon(DeviceType type) {
    switch (type) {
      case DeviceType.roku:
        return LucideIcons.tv2;
      case DeviceType.samsung:
        return LucideIcons.monitor;
      case DeviceType.lg:
        return LucideIcons.monitorDot;
      case DeviceType.vizio:
        return LucideIcons.monitorPlay;
      case DeviceType.googleTv:
        return LucideIcons.cast;
      case DeviceType.fireTv:
        return LucideIcons.flame;
      case DeviceType.ir:
        return LucideIcons.activity;
      case DeviceType.unknown:
        return LucideIcons.monitorSmartphone;
    }
  }

  Color _deviceColor(DeviceType type) {
    switch (type) {
      case DeviceType.roku:
        return const Color(0xFF9D64FF);
      case DeviceType.samsung:
        return const Color(0xFF1428A0);
      case DeviceType.lg:
        return const Color(0xFFA50034);
      case DeviceType.vizio:
        return const Color(0xFFFBB03B);
      case DeviceType.googleTv:
        return const Color(0xFF4285F4);
      case DeviceType.fireTv:
        return const Color(0xFFFF9900);
      case DeviceType.ir:
        return Colors.green;
      default:
        return Colors.indigoAccent;
    }
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isPrimary,
  }) {
    return Semantics(
      label: label,
      button: true,
      child: Material(
        color: isPrimary
            ? Colors.indigoAccent
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: isPrimary
                  ? null
                  : Border.all(color: Colors.white.withValues(alpha: 0.1)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isPrimary ? Colors.white : Colors.white70,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: isPrimary ? Colors.white : Colors.white70,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A short status word on a device row: "Saved" for an entry restored from
/// storage this scan has not heard from, "Not supported" for a device type
/// with no transport.
class _RowBadge extends StatelessWidget {
  const _RowBadge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.55),
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    ),
  );
}

/// What to say when a sweep turns up nothing.
///
/// The previous advice was "Ensure you share the same Wi-Fi network", which is
/// the one thing a user has almost always already done, and is not checkable
/// from inside the app. The causes that actually bite are invisible from the
/// phone: a guest SSID or a separate 2.4GHz band that presents as the same
/// network, client isolation between Wi-Fi clients, or a TV configured to
/// refuse external control. Each of those has a specific place to look.
/// Only reachable once a scan has finished: while one is running with nothing
/// found yet, [_buildDeviceList] is not called at all and the radar shows
/// instead. Advice offered before the sweep has had its chance would read as a
/// failure that has not happened yet.
class _NothingFound extends StatelessWidget {
  const _NothingFound();

  static const _checks = [
    'The TV may be on a guest network or a separate 2.4GHz band. Those look '
        'like the same Wi-Fi and are not.',
    'Some routers isolate Wi-Fi clients from each other. Look for "AP '
        'isolation" or "client isolation".',
    'On a Roku, Settings > System > Advanced system settings > Control by '
        'mobile apps must not be Disabled.',
    'Read the address off the TV (Roku: Settings > Network > About) and use '
        'Manual IP below.',
  ];

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
              child: Icon(
                LucideIcons.wifiOff,
                size: 40,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No devices found',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            for (final check in _checks)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6, right: 10),
                      child: Icon(
                        LucideIcons.dot,
                        size: 8,
                        color: Colors.white.withValues(alpha: 0.4),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        check,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
