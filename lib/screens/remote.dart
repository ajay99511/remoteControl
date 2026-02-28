import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../models/device.dart';
import '../models/remote_key.dart';
import '../providers/connection_provider.dart';
import '../widgets/remote_buttons.dart';

class RemoteScreen extends ConsumerStatefulWidget {
  final Device device;
  final VoidCallback onDisconnect;

  const RemoteScreen({
    super.key,
    required this.device,
    required this.onDisconnect,
  });

  @override
  ConsumerState<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends ConsumerState<RemoteScreen>
    with SingleTickerProviderStateMixin {
  bool isPowerOn = true;
  int activeTab = 0; // 0: Nav, 1: Touch, 2: Numpad
  bool showKeyboard = false;
  final TextEditingController _keyboardController = TextEditingController();
  final FocusNode _keyboardFocus = FocusNode();

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      setState(() {
        activeTab = _tabController.index;
      });
      HapticFeedback.selectionClick();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _keyboardController.dispose();
    _keyboardFocus.dispose();
    super.dispose();
  }

  void _sendKey(RemoteKey key) {
    ref.read(connectionProvider.notifier).sendKey(key);
    HapticFeedback.lightImpact();
  }

  void _togglePower() {
    _sendKey(RemoteKey.power);
    setState(() => isPowerOn = !isPowerOn);
    HapticFeedback.mediumImpact();
  }

  void _toggleKeyboard() {
    setState(() {
      showKeyboard = !showKeyboard;
    });
    if (showKeyboard) {
      _keyboardFocus.requestFocus();
    } else {
      _keyboardFocus.unfocus();
    }
  }

  void _sendText(String text) {
    if (text.isEmpty) return;
    ref.read(connectionProvider.notifier).sendText(text);
    HapticFeedback.lightImpact();
    _keyboardController.clear();
    setState(() {
      showKeyboard = false;
    });
    _keyboardFocus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(connectionProvider);
    final isConnected = connection.status == ConnectionStatus.connected;

    return Scaffold(
      backgroundColor: const Color(0xFF09090B),
      body: Stack(
        children: [
          // Background Glow Orbs for depth
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.indigoAccent.withValues(alpha: 0.1),
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            left: -50,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.deepPurpleAccent.withValues(alpha: 0.1),
              ),
            ),
          ),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
            child: Container(color: Colors.transparent),
          ),
          // Content
          SafeArea(
            child: Column(
              children: [
                _buildHeader(isConnected),
                Expanded(
                  child: Stack(
                    children: [
                      TabBarView(
                        controller: _tabController,
                        physics: const BouncingScrollPhysics(),
                        children: [
                          _buildNavigationMode(),
                          _buildTouchpadMode(),
                          _buildNumpadMode(),
                        ],
                      ),
                      if (showKeyboard) _buildKeyboardOverlay(),
                    ],
                  ),
                ),
                _buildBottomBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isConnected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: IconButton(
              icon: const Icon(LucideIcons.arrowLeft, color: Colors.white70),
              onPressed: widget.onDisconnect,
            ),
          ),
          Column(
            children: [
              Text(
                widget.device.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isConnected
                              ? const Color(0xFF69F0AE)
                              : Colors.redAccent,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color:
                                  (isConnected
                                          ? const Color(0xFF69F0AE)
                                          : Colors.redAccent)
                                      .withValues(alpha: 0.5),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      )
                      .animate(
                        onPlay: (controller) => isConnected
                            ? controller.repeat(reverse: true)
                            : null,
                      )
                      .fade(begin: 0.5, end: 1.0, duration: 1.seconds),
                  const SizedBox(width: 8),
                  Text(
                    isConnected ? 'CONNECTED' : 'DISCONNECTED',
                    style: TextStyle(
                      color: isConnected
                          ? const Color(0xFF69F0AE)
                          : Colors.redAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              boxShadow: isPowerOn
                  ? []
                  : [
                      BoxShadow(
                        color: Colors.redAccent.withValues(alpha: 0.2),
                        blurRadius: 10,
                      ),
                    ],
            ),
            child: IconButton(
              icon: Icon(
                LucideIcons.power,
                color: isPowerOn ? Colors.redAccent : Colors.white70,
              ),
              onPressed: _togglePower,
            ),
          ),
        ],
      ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.2, end: 0),
    );
  }

  Widget _buildNavigationMode() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        children: [
          // Premium D-Pad
          Center(
                child: SizedBox(
                  width: 280,
                  height: 280,
                  child: Stack(
                    children: [
                      // Outer Glow
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.indigoAccent.withValues(
                                alpha: 0.15,
                              ),
                              blurRadius: 40,
                              spreadRadius: 10,
                            ),
                          ],
                        ),
                      ),
                      // Background
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.03),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                            width: 2,
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.white.withValues(alpha: 0.05),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                      // Inner Plate
                      Positioned.fill(
                        child: Container(
                          margin: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0C0C0E),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.6),
                                blurRadius: 10,
                                spreadRadius: 2,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Direction Buttons
                      Align(
                        alignment: Alignment.topCenter,
                        child: _buildDPadSegment(
                          RemoteKey.up,
                          LucideIcons.chevronUp,
                          const EdgeInsets.only(top: 16),
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: _buildDPadSegment(
                          RemoteKey.down,
                          LucideIcons.chevronDown,
                          const EdgeInsets.only(bottom: 16),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _buildDPadSegment(
                          RemoteKey.left,
                          LucideIcons.chevronLeft,
                          const EdgeInsets.only(left: 16),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: _buildDPadSegment(
                          RemoteKey.right,
                          LucideIcons.chevronRight,
                          const EdgeInsets.only(right: 16),
                        ),
                      ),
                      // OK Button
                      Center(
                        child: Material(
                          color: Colors.transparent,
                          shape: const CircleBorder(),
                          child: InkWell(
                            onTap: () => _sendKey(RemoteKey.select),
                            customBorder: const CircleBorder(),
                            splashColor: Colors.indigoAccent.withValues(
                              alpha: 0.3,
                            ),
                            highlightColor: Colors.indigoAccent.withValues(
                              alpha: 0.1,
                            ),
                            child: Container(
                              width: 88,
                              height: 88,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF27272A),
                                    Color(0xFF18181B),
                                  ],
                                ),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.5),
                                    blurRadius: 10,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Text(
                                  'OK',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .animate()
              .fadeIn(duration: 500.ms)
              .scale(begin: const Offset(0.9, 0.9), end: const Offset(1, 1)),

          const SizedBox(height: 48),

          // System Keys
          Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  RemoteButton(
                    icon: LucideIcons.arrowLeft,
                    label: 'BACK',
                    onTap: () => _sendKey(RemoteKey.back),
                  ),
                  RemoteButton(
                    icon: LucideIcons.home,
                    label: 'HOME',
                    onTap: () => _sendKey(RemoteKey.home),
                    activeColor: Colors.purpleAccent,
                    active: true,
                  ),
                  RemoteButton(
                    icon: LucideIcons.playCircle,
                    label: 'PLAY',
                    onTap: () => _sendKey(RemoteKey.playPause),
                  ),
                ],
              )
              .animate()
              .fadeIn(delay: 100.ms, duration: 400.ms)
              .slideY(begin: 0.1, end: 0),

          const SizedBox(height: 32),

          // Volume & Channel
          Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  RockerButton(
                    label: 'VOL',
                    iconUp: LucideIcons.plus,
                    iconDown: LucideIcons.minus,
                    onUp: () => _sendKey(RemoteKey.volumeUp),
                    onDown: () => _sendKey(RemoteKey.volumeDown),
                  ),
                  Column(
                    children: [
                      RemoteButton(
                        icon: LucideIcons.rewind,
                        onTap: () => _sendKey(RemoteKey.rewind),
                      ),
                      const SizedBox(height: 16),
                      RemoteButton(
                        icon: LucideIcons.fastForward,
                        onTap: () => _sendKey(RemoteKey.fastForward),
                      ),
                    ],
                  ),
                  RockerButton(
                    label: 'MUTE',
                    iconUp: LucideIcons.volume2,
                    iconDown: LucideIcons.volumeX,
                    onUp: () => _sendKey(RemoteKey.volumeUp),
                    onDown: () => _sendKey(RemoteKey.mute),
                  ),
                ],
              )
              .animate()
              .fadeIn(delay: 200.ms, duration: 400.ms)
              .slideY(begin: 0.1, end: 0),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildDPadSegment(RemoteKey key, IconData icon, EdgeInsets padding) {
    return Padding(
      padding: padding,
      child: IconButton(
        iconSize: 28,
        icon: Icon(icon, color: Colors.white70),
        splashColor: Colors.indigoAccent.withValues(alpha: 0.3),
        highlightColor: Colors.indigoAccent.withValues(alpha: 0.1),
        onPressed: () => _sendKey(key),
      ),
    );
  }

  Widget _buildTouchpadMode() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
      child: Column(
        children: [
          Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(32),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.indigoAccent.withValues(alpha: 0.05),
                            blurRadius: 30,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          Center(
                                child: Icon(
                                  LucideIcons.mousePointer2,
                                  size: 80,
                                  color: Colors.white.withValues(alpha: 0.1),
                                ),
                              )
                              .animate(
                                onPlay: (controller) =>
                                    controller.repeat(reverse: true),
                              )
                              .fade(begin: 0.5, end: 1.0, duration: 2.seconds),
                          Positioned(
                            bottom: 32,
                            left: 0,
                            right: 0,
                            child: Text(
                              'SWIPE TO NAVIGATE • TAP TO CLICK',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2.0,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onPanEnd: (details) {
                              final velocity = details.velocity.pixelsPerSecond;
                              if (velocity.dx.abs() > velocity.dy.abs()) {
                                if (velocity.dx > 0) {
                                  _sendKey(RemoteKey.right);
                                } else {
                                  _sendKey(RemoteKey.left);
                                }
                              } else {
                                if (velocity.dy > 0) {
                                  _sendKey(RemoteKey.down);
                                } else {
                                  _sendKey(RemoteKey.up);
                                }
                              }
                            },
                            onTap: () => _sendKey(RemoteKey.select),
                            child: Container(color: Colors.transparent),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
              .animate()
              .fadeIn(duration: 400.ms)
              .scale(begin: const Offset(0.9, 0.9), end: const Offset(1, 1)),
          const SizedBox(height: 32),
          Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  RemoteButton(
                    icon: LucideIcons.arrowLeft,
                    label: 'BACK',
                    onTap: () => _sendKey(RemoteKey.back),
                  ),
                  RemoteButton(
                    icon: LucideIcons.home,
                    label: 'HOME',
                    onTap: () => _sendKey(RemoteKey.home),
                    activeColor: Colors.purpleAccent,
                    active: true,
                  ),
                  RemoteButton(
                    icon: LucideIcons.playCircle,
                    label: 'PLAY',
                    onTap: () => _sendKey(RemoteKey.playPause),
                  ),
                ],
              )
              .animate()
              .fadeIn(delay: 100.ms, duration: 400.ms)
              .slideY(begin: 0.1, end: 0),
        ],
      ),
    );
  }

  Widget _buildNumpadMode() {
    final nums = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', ''];
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        children: [
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.4,
            ),
            itemCount: nums.length,
            itemBuilder: (context, index) {
              final num = nums[index];
              if (num.isEmpty) return const SizedBox();
              return Material(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      onTap: () {
                        ref.read(connectionProvider.notifier).sendText(num);
                        HapticFeedback.lightImpact();
                      },
                      borderRadius: BorderRadius.circular(20),
                      splashColor: Colors.indigoAccent.withValues(alpha: 0.2),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.05),
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          num,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  )
                  .animate()
                  .fadeIn(delay: (index * 20).ms, duration: 300.ms)
                  .slideY(begin: 0.1, end: 0);
            },
          ),
          const SizedBox(height: 32),
          GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 2.2,
                children: [
                  AppButton(
                    name: 'Netflix',
                    color: const Color(0xFFE50914),
                    onTap: () {},
                  ),
                  AppButton(
                    name: 'YouTube',
                    color: const Color(0xFFFF0000),
                    onTap: () {},
                  ),
                  AppButton(
                    name: 'Prime Video',
                    color: const Color(0xFF00A8E1),
                    onTap: () {},
                  ),
                  AppButton(
                    name: 'Disney+',
                    color: const Color(0xFF113CCF),
                    onTap: () {},
                  ),
                ],
              )
              .animate()
              .fadeIn(delay: 200.ms, duration: 400.ms)
              .slideY(begin: 0.1, end: 0),
        ],
      ),
    );
  }

  Widget _buildKeyboardOverlay() {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 16,
      child:
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF18181B).withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _keyboardController,
                            focusNode: _keyboardFocus,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Type to search...',
                              hintStyle: TextStyle(
                                color: Colors.white.withValues(alpha: 0.4),
                              ),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.05),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                  color: Colors.indigoAccent,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 16,
                              ),
                            ),
                            onSubmitted: _sendText,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          decoration: const BoxDecoration(
                            color: Colors.indigoAccent,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            onPressed: () =>
                                _sendText(_keyboardController.text),
                            icon: const Icon(
                              LucideIcons.send,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _toggleKeyboard,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white.withValues(alpha: 0.6),
                      ),
                      child: const Text(
                        'Dismiss Keyboard',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ).animate().moveY(
            begin: 100,
            end: 0,
            duration: 300.ms,
            curve: Curves.easeOutQuart,
          ),
    );
  }

  Widget _buildBottomBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildTabButton(0, LucideIcons.move, 'Nav'),
            _buildTabButton(1, LucideIcons.mousePointer2, 'Touch'),
            _buildTabButton(2, LucideIcons.hash, '123'),
            _buildTabButton(
              3,
              LucideIcons.keyboard,
              'Type',
              onTap: _toggleKeyboard,
              isActiveOverride: showKeyboard,
            ),
          ],
        ),
      ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.5, end: 0),
    );
  }

  Widget _buildTabButton(
    int index,
    IconData icon,
    String label, {
    VoidCallback? onTap,
    bool? isActiveOverride,
  }) {
    final isActive = isActiveOverride ?? (activeTab == index);
    return Expanded(
      child: GestureDetector(
        onTap: onTap ?? () => _tabController.animateTo(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isActive
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.05),
                      blurRadius: 10,
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 22,
                color: isActive ? Colors.white : Colors.white54,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive ? Colors.white : Colors.white54,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
