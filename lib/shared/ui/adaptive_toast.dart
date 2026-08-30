import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:sitemark/motion.dart';
import 'package:sitemark/shared/ui/glass_surface.dart';

/// Label + callback of a toast's trailing action (e.g. 撤销).
class AppToastAction {
  const AppToastAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;
}

/// Shows a transient confirmation message following each platform's shape: a
/// floating glass capsule over the content on iOS — snackbars are not part of
/// the Liquid Glass vocabulary — and a Material [SnackBar] everywhere else.
///
/// [replace] clears any visible toast first instead of queueing behind it,
/// mirroring `hideCurrentSnackBar` + `showSnackBar` sequences.
void showAppToast(
  BuildContext context,
  String message, {
  AppToastAction? action,
  bool replace = false,
  Duration duration = const Duration(seconds: 4),
}) {
  if (defaultTargetPlatform != TargetPlatform.iOS) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    // Keep the pre-migration `maybeOf` semantics: without a Scaffold in
    // scope (bare test harnesses) the toast is a no-op.
    if (messenger == null) return;
    _materialMessenger = messenger;
    if (replace) {
      messenger
        ..clearSnackBars()
        ..removeCurrentSnackBar();
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        action: action == null
            ? null
            : SnackBarAction(label: action.label, onPressed: action.onPressed),
      ),
    );
    return;
  }
  _dismissTimer?.cancel();
  _removeCurrent();
  final overlay = Overlay.of(context, rootOverlay: true);
  final entry = OverlayEntry(
    builder: (entryContext) => _ToastCapsule(
      message: message,
      action: action,
      duration: duration,
      onDismiss: _removeCurrent,
    ),
  );
  _currentEntry = entry;
  overlay.insert(entry);
  _dismissTimer = Timer(duration, _removeCurrent);
}

/// Immediately hides the visible toast, whichever platform is showing it.
void hideAppToast() {
  _dismissTimer?.cancel();
  _dismissTimer = null;
  if (defaultTargetPlatform != TargetPlatform.iOS) {
    final messenger = _materialMessenger;
    // The stored messenger can be stale (e.g. a disposed test harness);
    // touching it would animate a disposed controller.
    if (messenger != null && messenger.mounted) {
      messenger.clearSnackBars();
    } else {
      _materialMessenger = null;
    }
    return;
  }
  _removeCurrent();
}

OverlayEntry? _currentEntry;
Timer? _dismissTimer;
ScaffoldMessengerState? _materialMessenger;

void _removeCurrent() {
  _dismissTimer?.cancel();
  _dismissTimer = null;
  _currentEntry?.remove();
  _currentEntry = null;
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
  bool _entranceStarted = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, value: 1);
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewPadding = MediaQuery.viewPaddingOf(context);
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, viewPadding.bottom + 16),
          child: FadeTransition(
            opacity: _controller,
            child: GlassSurface(
              borderRadius: BorderRadius.circular(24),
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
                            widget.action!.onPressed();
                            widget.onDismiss();
                          },
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
    );
  }
}
