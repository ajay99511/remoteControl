import 'package:flutter/material.dart';

/// The app's colour tokens.
///
/// These literals were previously repeated across four files - `0xFF09090B`
/// in four places, `0xFF18181B` in four, `Colors.indigoAccent` in more than
/// thirty - while MaterialApp.theme defined a ColorScheme almost none of them
/// read. A brand change was a find-and-replace with no compiler help, and a
/// light theme was impossible.
abstract final class AppColors {
  /// Page background.
  static const background = Color(0xFF09090B);

  /// Cards, dialogs, sheets.
  static const surface = Color(0xFF18181B);

  /// Raised controls on top of [surface].
  static const surfaceRaised = Color(0xFF27272A);

  /// Secondary text and inactive icons (zinc-500).
  static const textMuted = Color(0xFF71717A);

  /// Accent used for focus, selection and primary actions.
  static const accent = Colors.indigoAccent;

  /// Connected-state indicator.
  static const connected = Color(0xFF69F0AE);

  /// Error and disconnected-state indicator.
  static const disconnected = Colors.redAccent;
}
