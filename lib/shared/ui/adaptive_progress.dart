import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Activity indicator that follows each platform's shape: a
/// `CupertinoActivityIndicator` on iOS, a Material
/// `CircularProgressIndicator` everywhere else.
class AdaptiveProgressIndicator extends StatelessWidget {
  const AdaptiveProgressIndicator({super.key, this.size});

  /// Square box both variants are centered in so layouts keep their
  /// geometry across platforms; defaults to the Material spinner's size.
  final double? size;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return SizedBox(
        width: size ?? 36,
        height: size ?? 36,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    return SizedBox(
      width: size ?? 20,
      height: size ?? 20,
      child: const Center(child: CupertinoActivityIndicator()),
    );
  }
}
