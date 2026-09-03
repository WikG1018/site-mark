import 'package:flutter/material.dart';
import 'package:sitemark/motion.dart';

/// Pure hide/show policy for overlay chrome (top bar, dock, FAB).
///
/// Downward scroll (positive [delta]) hides; upward scroll shows. Chrome
/// stays visible near the top of the list and whenever a caller forces it.
class ScrollChromePolicy {
  static const double hideThreshold = 8;
  static const double showThreshold = 8;
  static const double topRevealExtent = 24;

  bool visible = true;
  double _accumulated = 0;

  /// Returns whether [visible] changed.
  bool apply({
    required double delta,
    required double offset,
    bool forceVisible = false,
  }) {
    if (!delta.isFinite || !offset.isFinite) {
      return false;
    }
    if (forceVisible || offset <= topRevealExtent) {
      _accumulated = 0;
      return _setVisible(true);
    }
    if (delta == 0) {
      return false;
    }
    if (_accumulated != 0 && delta.sign != _accumulated.sign) {
      _accumulated = 0;
    }
    _accumulated += delta;
    if (_accumulated >= hideThreshold) {
      _accumulated = 0;
      return _setVisible(false);
    }
    if (_accumulated <= -showThreshold) {
      _accumulated = 0;
      return _setVisible(true);
    }
    return false;
  }

  bool reset() {
    _accumulated = 0;
    return _setVisible(true);
  }

  bool _setVisible(bool value) {
    if (visible == value) {
      return false;
    }
    visible = value;
    return true;
  }
}

/// Shared controller for root and nested list chrome.
class ScrollChromeController extends ChangeNotifier {
  ScrollChromeController({ScrollChromePolicy? policy})
    : _policy = policy ?? ScrollChromePolicy();

  final ScrollChromePolicy _policy;
  final Set<Object> _forceReasons = <Object>{};
  bool _alive = true;

  bool get visible => _forceReasons.isNotEmpty || _policy.visible;

  void setForce(Object reason, bool active) {
    final changed = active
        ? _forceReasons.add(reason)
        : _forceReasons.remove(reason);
    if (!changed) {
      return;
    }
    if (active) {
      _policy.reset();
    }
    _emit();
  }

  void handleScroll({required double delta, required double offset}) {
    if (_policy.apply(
      delta: delta,
      offset: offset,
      forceVisible: _forceReasons.isNotEmpty,
    )) {
      _emit();
    }
  }

  bool handleNotification(ScrollNotification notification) {
    if (notification is! ScrollUpdateNotification) {
      return false;
    }
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }
    final delta = notification.scrollDelta;
    if (delta == null || delta == 0 || !delta.isFinite) {
      return false;
    }
    if (notification.metrics.outOfRange) {
      return false;
    }
    handleScroll(delta: delta, offset: notification.metrics.pixels);
    return false;
  }

  void reset() {
    final changed = _policy.reset();
    if (changed) {
      _emit();
    }
  }

  void _emit() {
    if (!_alive) {
      return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _alive = false;
    super.dispose();
  }
}

class ScrollChromeScope extends InheritedNotifier<ScrollChromeController> {
  const ScrollChromeScope({
    super.key,
    required ScrollChromeController controller,
    required super.child,
  }) : super(notifier: controller);

  static ScrollChromeController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<ScrollChromeScope>()
        ?.notifier;
  }

  static bool visibleOf(BuildContext context) {
    return maybeOf(context)?.visible ?? true;
  }
}

/// Owns the policy, listens to descendant scroll, and resets on [resetKey].
class ScrollChromeHost extends StatefulWidget {
  const ScrollChromeHost({
    super.key,
    required this.resetKey,
    required this.child,
  });

  final Object resetKey;
  final Widget child;

  @override
  State<ScrollChromeHost> createState() => _ScrollChromeHostState();
}

class _ScrollChromeHostState extends State<ScrollChromeHost> {
  final ScrollChromeController controller = ScrollChromeController();

  @override
  void didUpdateWidget(covariant ScrollChromeHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetKey != widget.resetKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          controller.reset();
        }
      });
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScrollChromeScope(
      controller: controller,
      child: NotificationListener<ScrollNotification>(
        onNotification: controller.handleNotification,
        child: widget.child,
      ),
    );
  }
}

Duration scrollChromeAnimationOf(BuildContext context) {
  return AppMotion.durationOf(context, AppMotion.short4);
}

const double scrollChromeFilterBarHeight = 52;

double scrollChromeTopInsetOf(BuildContext context, {double extra = 0}) {
  return MediaQuery.paddingOf(context).top + kToolbarHeight + extra;
}

/// Holds overlay chrome visible while [active] is true (search, selection,
/// or an open filter sheet).
class ScrollChromeForce extends StatefulWidget {
  const ScrollChromeForce({
    super.key,
    required this.reason,
    required this.active,
    required this.child,
  });

  final Object reason;
  final bool active;
  final Widget child;

  @override
  State<ScrollChromeForce> createState() => _ScrollChromeForceState();
}

class _ScrollChromeForceState extends State<ScrollChromeForce> {
  ScrollChromeController? _controller;
  Object? _appliedReason;
  bool? _appliedActive;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = ScrollChromeScope.maybeOf(context);
    if (!identical(next, _controller)) {
      _release(_controller, _appliedReason);
      _controller = next;
      _appliedReason = null;
      _appliedActive = null;
    }
    _scheduleApply();
  }

  @override
  void didUpdateWidget(covariant ScrollChromeForce oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reason != widget.reason ||
        oldWidget.active != widget.active) {
      _scheduleApply();
    }
  }

  @override
  void dispose() {
    _release(_controller, _appliedReason);
    super.dispose();
  }

  void _scheduleApply() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _apply();
    });
  }

  void _apply() {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    if (_appliedReason != null && _appliedReason != widget.reason) {
      controller.setForce(_appliedReason!, false);
    }
    if (_appliedReason == widget.reason && _appliedActive == widget.active) {
      return;
    }
    controller.setForce(widget.reason, widget.active);
    _appliedReason = widget.reason;
    _appliedActive = widget.active;
  }

  void _release(ScrollChromeController? controller, Object? reason) {
    if (controller == null || reason == null) {
      return;
    }
    controller.setForce(reason, false);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
