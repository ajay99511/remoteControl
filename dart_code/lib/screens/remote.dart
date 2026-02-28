import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../models/device.dart';
import '../widgets/remote_buttons.dart';

class RemoteScreen extends StatefulWidget {
  final Device device;
  final VoidCallback onDisconnect;

  const RemoteScreen({
    super.key,
    required this.device,
    required this.onDisconnect,
  });

  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen>
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

  void _togglePower() {
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
    // Simulate sending text
    print("Sending text: $text");
    HapticFeedback.lightImpact();
    _keyboardController.clear();
    setState(() {
      showKeyboard = false;
    });
    _keyboardFocus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF09090B),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
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
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF09090B),
        border: Border(bottom: BorderSide(color: Color(0xFF27272A))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(LucideIcons.arrowLeft, color: Color(0xFF71717A)),
            onPressed: widget.onDisconnect,
          ),
          Column(
            children: [
              Row(
                children: [
                  Text(
                    widget.device.name,
                    style: const TextStyle(
                      color: Color(0xFFE4E4E7),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF27272A),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF3F3F46)),
                    ),
                    child: const Text(
                      'DEMO',
                      style: TextStyle(
                        color: Color(0xFF71717A),
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF69F0AE),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'CONNECTED',
                    style: TextStyle(
                      color: Color(0xFF69F0AE),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ],
          ),
          IconButton(
            icon: Icon(
              LucideIcons.power,
              color: isPowerOn ? Colors.redAccent : const Color(0xFF52525B),
            ),
            onPressed: _togglePower,
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationMode() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // D-Pad
          SizedBox(
            width: 256,
            height: 256,
            child: Stack(
              children: [
                // Background
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF18181B).withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                ),
                // Inner Circle
                Positioned.fill(
                  child: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Color(0xFF121212),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black,
                          blurRadius: 4,
                          spreadRadius: 0,
                          offset: Offset(0, 2),
                        ), // Inset shadow simulation
                      ],
                    ),
                  ),
                ),
                // Buttons
                Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: IconButton(
                      icon: const Icon(
                        LucideIcons.chevronUp,
                        color: Color(0xFFA1A1AA),
                      ),
                      onPressed: () => HapticFeedback.lightImpact(),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: IconButton(
                      icon: const Icon(
                        LucideIcons.chevronDown,
                        color: Color(0xFFA1A1AA),
                      ),
                      onPressed: () => HapticFeedback.lightImpact(),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: IconButton(
                      icon: const Icon(
                        LucideIcons.chevronLeft,
                        color: Color(0xFFA1A1AA),
                      ),
                      onPressed: () => HapticFeedback.lightImpact(),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: IconButton(
                      icon: const Icon(
                        LucideIcons.chevronRight,
                        color: Color(0xFFA1A1AA),
                      ),
                      onPressed: () => HapticFeedback.lightImpact(),
                    ),
                  ),
                ),
                // OK Button
                Center(
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF27272A), Color(0xFF09090B)],
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      shape: const CircleBorder(),
                      child: InkWell(
                        onTap: () => HapticFeedback.mediumImpact(),
                        customBorder: const CircleBorder(),
                        child: const Center(
                          child: Text(
                            'OK',
                            style: TextStyle(
                              color: Color(0xFFA1A1AA),
                              fontWeight: FontWeight.bold,
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

          const SizedBox(height: 32),

          // System Keys
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              RemoteButton(
                icon: LucideIcons.arrowLeft,
                label: 'BACK',
                onTap: () {},
              ),
              RemoteButton(icon: LucideIcons.home, label: 'HOME', onTap: () {}),
              RemoteButton(icon: LucideIcons.menu, label: 'MENU', onTap: () {}),
            ],
          ),

          const SizedBox(height: 32),

          // Volume & Channel
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              RockerButton(
                label: 'VOL',
                iconUp: LucideIcons.plus,
                iconDown: LucideIcons.minus,
                onUp: () {},
                onDown: () {},
              ),
              Column(
                children: [
                  RemoteButton(
                    icon: LucideIcons.mic,
                    onTap: () {},
                    activeColor: Colors.indigo,
                    color: Colors.indigoAccent,
                    active: false, // Could toggle
                  ),
                  const SizedBox(height: 16),
                  RemoteButton(
                    icon: LucideIcons.volumeX,
                    onTap: () {},
                    color: Colors.redAccent,
                  ),
                ],
              ),
              RockerButton(
                label: 'CH',
                iconUp: LucideIcons.chevronUp,
                iconDown: LucideIcons.chevronDown,
                onUp: () {},
                onDown: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTouchpadMode() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF18181B).withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Stack(
                children: [
                  const Center(
                    child: Icon(
                      LucideIcons.mousePointer2,
                      size: 96,
                      color: Color(0xFF27272A),
                    ),
                  ),
                  Positioned(
                    bottom: 24,
                    left: 0,
                    right: 0,
                    child: Text(
                      'SWIPE TO NAVIGATE • TAP TO CLICK',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: const Color(0xFF52525B),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onPanUpdate: (details) {
                      // Handle pan
                    },
                    onTap: () {
                      HapticFeedback.lightImpact();
                    },
                    child: Container(color: Colors.transparent),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              RemoteButton(
                icon: LucideIcons.arrowLeft,
                label: 'BACK',
                onTap: () {},
              ),
              RemoteButton(icon: LucideIcons.home, label: 'HOME', onTap: () {}),
              RemoteButton(icon: LucideIcons.menu, label: 'MENU', onTap: () {}),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNumpadMode() {
    final nums = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', ''];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.5,
            ),
            itemCount: nums.length,
            itemBuilder: (context, index) {
              final num = nums[index];
              if (num.isEmpty) return const SizedBox();
              return Material(
                color: const Color(0xFF18181B),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  onTap: () => HapticFeedback.lightImpact(),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFF27272A)),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      num,
                      style: const TextStyle(
                        color: Color(0xFFE4E4E7),
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 32),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 2.5,
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
                name: 'Prime',
                color: const Color(0xFF00A8E1),
                onTap: () {},
              ),
              AppButton(
                name: 'Disney+',
                color: const Color(0xFF113CCF),
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKeyboardOverlay() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Color(0xFF18181B),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 20)],
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
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Type to search...',
                      hintStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: Colors.black.withValues(alpha: 0.5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: _sendText,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _sendText(_keyboardController.text),
                  icon: const Icon(
                    LucideIcons.send,
                    color: Colors.indigoAccent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _toggleKeyboard,
              child: const Text(
                'Close Keyboard',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ),
      ).animate().moveY(begin: 100, end: 0, duration: 200.ms),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
      decoration: const BoxDecoration(
        color: Color(0xFF09090B),
        border: Border(top: BorderSide(color: Color(0xFF27272A))),
      ),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFF18181B).withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
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
      ),
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
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF27272A) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: isActive ? Colors.white : const Color(0xFF71717A),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: isActive ? Colors.white : const Color(0xFF71717A),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
