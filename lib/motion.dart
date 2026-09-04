import 'package:flutter/widgets.dart';

abstract final class AppMotion {
  static const Duration rootSwitch = Duration(milliseconds: 240);
  static const Duration pageTransition = Duration(milliseconds: 260);
  static const Duration short4 = Duration(milliseconds: 180);
  static const Duration scrollChrome = Duration(milliseconds: 280);
  static const Duration medium2 = pageTransition;
  static const Duration medium4 = Duration(milliseconds: 320);
  static const Duration long2 = Duration(milliseconds: 500);

  static const Cubic emphasized = Cubic(0.2, 0.0, 0.0, 1.0);
  static const Cubic emphasizedDecelerate = Cubic(0.05, 0.7, 0.1, 1.0);
  static const Cubic emphasizedAccelerate = Cubic(0.3, 0.0, 0.8, 0.15);
  static const Cubic standard = Cubic(0.2, 0.0, 0.0, 1.0);
  static const Cubic standardDecelerate = Cubic(0.0, 0.0, 0.0, 1.0);
  static const Cubic standardAccelerate = Cubic(0.3, 0.0, 1.0, 1.0);

  /// Returns [duration] unless the user has enabled system reduce-motion,
  /// in which case animations collapse to zero for accessibility.
  static Duration durationOf(BuildContext context, Duration duration) {
    return MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
  }
}
