import 'dart:async';

import 'package:flutter/widgets.dart';

/// Owns one exact modal route and can terminally dismiss it across lifecycle
/// changes, including when dismissal wins the race with the route builder.
class CaptureOwnedRouteController {
  Route<Object?>? _route;
  bool _dismissed = false;
  final Set<VoidCallback> _dismissListeners = {};

  void addDismissListener(VoidCallback listener) {
    if (_dismissed) {
      listener();
      return;
    }
    _dismissListeners.add(listener);
  }

  void removeDismissListener(VoidCallback listener) {
    _dismissListeners.remove(listener);
  }

  void attach(Route<Object?> route) {
    if (_dismissed) {
      _removeWhenSafe(route);
      return;
    }
    _route = route;
  }

  void detach() => _route = null;

  void dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    final listeners = [..._dismissListeners];
    _dismissListeners.clear();
    for (final listener in listeners) {
      listener();
    }
    final route = _route;
    _route = null;
    if (route != null) _removeWhenSafe(route);
  }

  void _removeWhenSafe(Route<Object?> route) {
    scheduleMicrotask(() {
      final navigator = route.navigator;
      if (navigator == null || !navigator.mounted || !route.isActive) return;
      navigator.removeRoute(route);
    });
  }
}
