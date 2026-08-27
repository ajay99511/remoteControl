import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The two soft colour washes behind each screen.
///
/// Previously two circles under a full-viewport BackdropFilter, which forces
/// a saveLayer and re-blurs the whole screen on any frame where anything
/// beneath it changes - on a screen whose job is to sit idle waiting for
/// button presses. A pair of radial gradients reproduces the look at zero
/// per-frame cost.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({
    super.key,
    this.primary = AppColors.accent,
    this.secondary = Colors.purpleAccent,
    this.primaryAlignment = const Alignment(-0.9, -1.0),
    this.secondaryAlignment = const Alignment(1.0, 1.0),
    this.intensity = 0.18,
  });

  final Color primary;
  final Color secondary;
  final Alignment primaryAlignment;
  final Alignment secondaryAlignment;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: primaryAlignment,
              radius: 1.1,
              colors: [
                primary.withValues(alpha: intensity),
                AppColors.background.withValues(alpha: 0),
              ],
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: secondaryAlignment,
                radius: 0.9,
                colors: [
                  secondary.withValues(alpha: intensity * 0.8),
                  AppColors.background.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
