import 'dart:io';

import 'package:flutter/material.dart';

/// A record-photo Hero with a stable image-only flight layer.
///
/// The list and detail previews have different layouts and decode sizes. The
/// flight therefore avoids reusing either preview subtree, which can contain
/// async resolution and fade animations. Both flight images share one provider
/// and keep the prior frame visible while Flutter resolves it.
class CapturePhotoHero extends StatelessWidget {
  const CapturePhotoHero({
    super.key,
    required this.tag,
    required this.path,
    required this.child,
  });

  final String tag;
  final String path;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: tag,
      // Keep the list thumbnail painted underneath the overlay. The default
      // empty placeholder creates a one-frame hole when the reverse flight is
      // handed back to the destination route.
      placeholderBuilder: (context, heroSize, child) => child,
      flightShuttleBuilder:
          (
            flightContext,
            animation,
            direction,
            fromHeroContext,
            toHeroContext,
          ) {
            final provider = ResizeImage.resizeIfNeeded(
              2048,
              null,
              FileImage(File(path)),
            );
            return KeyedSubtree(
              key: const Key('capture-photo-hero-flight'),
              child: AnimatedBuilder(
                animation: animation,
                builder: (context, child) {
                  final progress = animation.value;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Opacity(
                        opacity: 1 - progress,
                        child: Image(
                          image: provider,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
                      Opacity(
                        opacity: progress,
                        child: Image(
                          image: provider,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
      child: child,
    );
  }
}
