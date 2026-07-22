import 'package:flutter/animation.dart';

abstract final class AppMotion {
  static const Duration short4 = Duration(milliseconds: 200);
  static const Duration medium2 = Duration(milliseconds: 300);
  static const Duration medium4 = Duration(milliseconds: 400);
  static const Duration long2 = Duration(milliseconds: 500);

  static const Cubic emphasized = Cubic(0.2, 0.0, 0.0, 1.0);
  static const Cubic emphasizedDecelerate = Cubic(0.05, 0.7, 0.1, 1.0);
  static const Cubic emphasizedAccelerate = Cubic(0.3, 0.0, 0.8, 0.15);
  static const Curve standard = Curves.easeInOutCubic;
}
