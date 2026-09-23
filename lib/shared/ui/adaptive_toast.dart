import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sitemark/motion.dart';
import 'package:sitemark/shared/ui/glass_surface.dart';

/// Label + callback of a toast's trailing action (e.g. 撤销).
class AppToastAction {
  const AppToastAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;
}

/// Shows a transient confirmation as a floating glass capsule — the same
/// chrome vocabulary as the navigation dock and batch action bar.
///
/// Material [SnackBar] is deliberately not used: its full-width bar and
/// platform-default action styling read as a different design system from the
/// app's floating glass surfaces.
///
/// [replace] clears any visible toast first instead of queueing behind it.
void showAppToast(
  BuildContext context,
  String message, {
  AppToastAction? action,
  bool replace = false,
  Duration duration = const Duration(seconds: 4),
}) {
  if (replace) {
    _removeCurrent();
  } else if (_currentEntry != null) {
    // Keep the newest toast only, matching the previous hide+show Material
    // sequence callers relied on.
    _animatedDismiss?.call();
  }
  final overlay = Overlay.of(context, rootOverlay: true);
  OverlayEntry? entry;
  entry = OverlayEntry(
    builder: (entryContext) => _ToastCapsule(
      message: message,
      action: action,
      duration: duration,
      // Only the toast that is still current may tear down the slot — a
      // replacement shown while this one fades out must survive.
      onDismiss: () {
        if (identical(_currentEntry, entry)) _removeCurrent();
      },
    ),
  );
  _currentEntry = entry;
  overlay.insert(entry);
}

/// Immediately hides the visible toast.
void hideAppToast() {
  final animated = _animatedDismiss;
  if (animated != null) {
    animated();
    return;
  }
  _removeCurrent();
}

OverlayEntry? _currentEntry;

/// Set by the visible capsule so timer/hide paths fade out instead of
/// yanking the capsule off screen.
void Function()? _animatedDismiss;

void _removeCurrent() {
  final entry = _currentEntry;
  _currentEntry = null;
  _animatedDismiss = null;
  entry?.remove();
}

class _ToastCapsule extends StatefulWidget {
  const _ToastCapsule({
    required this.message,
    required this.duration,
    required this.onDismiss,
    this.action,
  });

  final String message;
  final AppToastAction? action;
  final Duration duration;
  final VoidCallback onDismiss;

  @override
  State<_ToastCapsule> createState() => _ToastCapsuleState();
}

class _ToastCapsuleState extends State<_ToastCapsule>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// Drives the capsule's rise/settle motion: a spring on entrance for the
  /// "life" pop, an accelerate-out curve on dismiss.
  late final CurvedAnimation _motion;
  Timer? _autoDismiss;
  bool _entranceStarted = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, value: 1);
    _motion = CurvedAnimation(
      parent: _controller,
      curve: AppMotion.springSlideRise,
      reverseCurve: AppMotion.emphasizedAccelerate,
    );
    _animatedDismiss = _dismissAnimated;
    // Own the auto-dismiss timer so overlay/route teardown can cancel it in
    // [dispose] — a module-level timer would outlive a never-built entry.
    _autoDismiss = Timer(widget.duration, _dismissAnimated);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entranceStarted) return;
    _entranceStarted = true;
    if (!MediaQuery.disableAnimationsOf(context)) {
      _controller
        ..duration = AppMotion.short4
        ..forward(from: 0);
    }
  }

  void _dismissAnimated() {
    _autoDismiss?.cancel();
    _autoDismiss = null;
    if (!mounted) {
      widget.onDismiss();
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      widget.onDismiss();
      return;
    }
    _controller
      ..duration = AppMotion.short4
      ..reverse().whenComplete(widget.onDismiss);
  }

  @override
  void dispose() {
    _autoDismiss?.cancel();
    _autoDismiss = null;
    if (identical(_animatedDismiss, _dismissAnimated)) {
      _animatedDismiss = null;
    }
    _motion.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, viewPadding.bottom + 16),
          child: FadeTransition(
            opacity: _controller,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, .28),
                end: Offset.zero,
              ).animate(_motion),
              child: ScaleTransition(
                scale: Tween<double>(begin: .9, end: 1).animate(_motion),
                child: GlassSurface(
                  borderRadius: BorderRadius.circular(24),
                  opacity: GlassChrome.opacity,
                  blurSigma: GlassChrome.blurSigma,
                  // Match the root dock: one always-on glass layer is affordable
                  // and keeps the toast in the same material family.
                  blurOnAndroid: true,
                  child: Material(
                    type: MaterialType.transparency,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Text(
                                widget.message,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                          ),
                          if (widget.action != null)
                            TextButton(
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                widget.action!.onPressed();
                                _dismissAnimated();
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: scheme.primary,
                              ),
                              child: Text(widget.action!.label),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
