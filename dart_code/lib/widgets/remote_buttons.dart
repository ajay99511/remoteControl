import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RemoteButton extends StatelessWidget {
  final IconData? icon;
  final String? label;
  final VoidCallback onTap;
  final bool active;
  final double size;
  final Color? activeColor;
  final Color? color;

  const RemoteButton({
    super.key,
    this.icon,
    this.label,
    required this.onTap,
    this.active = false,
    this.size = 56,
    this.activeColor,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              onTap();
            },
            borderRadius: BorderRadius.circular(size / 2),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: active
                    ? (activeColor ?? const Color(0xFF27272A))
                    : const Color(0xFF18181B), // zinc-900
                shape: BoxShape.circle,
                border: Border.all(
                  color: active
                      ? (activeColor?.withValues(alpha: 0.5) ??
                            const Color(0xFF52525B))
                      : const Color(0xFF27272A),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Icon(
                  icon,
                  color: active
                      ? Colors.white
                      : (color ?? const Color(0xFFA1A1AA)), // zinc-400
                  size: size * 0.4,
                ),
              ),
            ),
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 8),
          Text(
            label!,
            style: const TextStyle(
              color: Color(0xFF52525B), // zinc-600
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ],
    );
  }
}

class RockerButton extends StatelessWidget {
  final String label;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final IconData iconUp;
  final IconData iconDown;

  const RockerButton({
    super.key,
    required this.label,
    required this.onUp,
    required this.onDown,
    required this.iconUp,
    required this.iconDown,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 140,
      decoration: BoxDecoration(
        color: const Color(0xFF18181B), // zinc-900
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Expanded(
            child: InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                onUp();
              },
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(32),
              ),
              child: Center(
                child: Icon(iconUp, color: const Color(0xFFA1A1AA), size: 24),
              ),
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF52525B), // zinc-600
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                onDown();
              },
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(32),
              ),
              child: Center(
                child: Icon(iconDown, color: const Color(0xFFA1A1AA), size: 24),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AppButton extends StatelessWidget {
  final String name;
  final Color color;
  final VoidCallback onTap;

  const AppButton({
    super.key,
    required this.name,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF18181B), // zinc-900
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () {
          HapticFeedback.mediumImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF27272A)), // zinc-800
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(
            name,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}

// Extension to add zinc colors easily
extension ZincColors on Colors {
  static Color get zinc900 => const Color(0xFF18181B);
  static Color get zinc800 => const Color(0xFF27272A);
  static Color get zinc600 => const Color(0xFF52525B);
  static Color get zinc400 => const Color(0xFFA1A1AA);
}
