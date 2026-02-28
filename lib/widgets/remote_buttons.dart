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
            splashColor: (activeColor ?? Colors.indigoAccent).withValues(
              alpha: 0.2,
            ),
            highlightColor: Colors.white.withValues(alpha: 0.05),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: active
                    ? (activeColor ?? const Color(0xFF27272A))
                    : Colors.white.withValues(alpha: 0.03),
                shape: BoxShape.circle,
                border: Border.all(
                  color: active
                      ? (activeColor?.withValues(alpha: 0.6) ??
                            Colors.white.withValues(alpha: 0.2))
                      : Colors.white.withValues(alpha: 0.05),
                  width: 1,
                ),
                boxShadow: [
                  if (active)
                    BoxShadow(
                      color: (activeColor ?? Colors.white).withValues(
                        alpha: 0.3,
                      ),
                      blurRadius: 10,
                      spreadRadius: 1,
                    )
                  else
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                ],
              ),
              child: Center(
                child: Icon(
                  icon,
                  color: active ? Colors.white : (color ?? Colors.white70),
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
              color: Color(0xFF71717A), // zinc-500
              fontSize: 10,
              fontWeight: FontWeight.w600,
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
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.02),
            blurRadius: 10,
            spreadRadius: -5,
            offset: const Offset(0, -5),
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
              splashColor: Colors.indigoAccent.withValues(alpha: 0.2),
              child: Center(
                child: Icon(iconUp, color: Colors.white70, size: 24),
              ),
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF71717A),
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
              splashColor: Colors.indigoAccent.withValues(alpha: 0.2),
              child: Center(
                child: Icon(iconDown, color: Colors.white70, size: 24),
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
      color: Colors.white.withValues(alpha: 0.03),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () {
          HapticFeedback.mediumImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(16),
        splashColor: color.withValues(alpha: 0.2),
        highlightColor: color.withValues(alpha: 0.05),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            borderRadius: BorderRadius.circular(16),
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
            name,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 15,
              letterSpacing: 0.5,
              shadows: [
                Shadow(color: color.withValues(alpha: 0.5), blurRadius: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
