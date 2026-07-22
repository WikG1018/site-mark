import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sitemark/platform/memory_pressure_service.dart';

/// Pluggable hook used by the [MemoryPressureCoordinator] to pause/resume
/// background work owned by other layers (e.g. the conditional-polling
/// streams in `app_database.dart`) without taking a direct dependency on
/// drift or any UI widget.
///
/// Implementations register themselves via [MemoryPressureController.attach]
/// when they start listening, and detach when their owner is disposed. The
/// coordinator calls all attached controllers on each TRIM/system event.
abstract class BackgroundWorkControl {
  /// Pause all non-essential background work (polling, future loaders).
  /// Must be safe to call repeatedly.
  void pauseBackgroundWork();

  /// Resume previously paused background work. Must be safe to call
  /// repeatedly and when nothing was paused.
  void resumeBackgroundWork();
}

/// Pluggable hook for persisting in-memory state before a MEMORY_KILL. The
/// coordinator invokes this on `kill` so the app has a chance to flush
/// drafts before the process is torn down.
abstract class KillBackupHook {
  Future<void> persistForKill();
}

/// A simple publish-subscribe bus used by UI surfaces (e.g. the fullscreen
/// image viewer) that need to react to memory-pressure events independently
/// of the central coordinator.
///
/// Subscribers receive a [MemoryPressureLevel] and are expected to release
/// their heavy resources (e.g. pop a fullscreen image route) synchronously
/// or within a microtask. The coordinator awaits all subscribers before
/// ACKing the OEM Binder.
class MemoryPressureController extends ChangeNotifier {
  final List<BackgroundWorkControl> _backgroundControls = [];
  final List<VoidCallback> _releaseHandlers = [];
  final List<KillBackupHook> _killHooks = [];

  MemoryPressureLevel? _lastLevel;

  /// The most recent pressure level, or `null` if none has been dispatched.
  MemoryPressureLevel? get lastLevel => _lastLevel;

  /// Attaches a [BackgroundWorkControl] so its work is paused on TRIM/system
  /// and resumed when pressure is relieved. Returns an unsubscribe function.
  VoidCallback attachBackground(BackgroundWorkControl control) {
    _backgroundControls.add(control);
    return () => _backgroundControls.remove(control);
  }

  /// Attaches a release handler invoked on every TRIM/system event. Use this
  /// for resources that should be released but cannot implement
  /// [BackgroundWorkControl] (e.g. a fullscreen image route). Returns an
  /// unsubscribe function.
  VoidCallback attachRelease(VoidCallback handler) {
    _releaseHandlers.add(handler);
    return () => _releaseHandlers.remove(handler);
  }

  /// Attaches a [KillBackupHook] invoked on every KILL event. Returns an
  /// unsubscribe function.
  VoidCallback attachKillHook(KillBackupHook hook) {
    _killHooks.add(hook);
    return () => _killHooks.remove(hook);
  }

  /// Called by the coordinator. Notifies all subscribers, then notifies
  /// listeners (for [ChangeNotifier] consumers).
  Future<void> dispatch(MemoryPressureLevel level) async {
    _lastLevel = level;
    switch (level) {
      case MemoryPressureLevel.system:
      case MemoryPressureLevel.trim:
        // Pause background work first so the polling streams stop touching
        // the database while we release caches.
        for (final control in List<BackgroundWorkControl>.of(_backgroundControls)) {
          try {
            control.pauseBackgroundWork();
          } catch (_) {
            // Best-effort; a failing control must not block others.
          }
        }
        // Release image cache and other heavy resources.
        try {
          PaintingBinding.instance.imageCache.clear();
        } catch (_) {
          // imageCache is always present in production; in tests it may not
          // be initialized. Swallow so test harnesses don't crash.
        }
        for (final handler in List<VoidCallback>.of(_releaseHandlers)) {
          try {
            handler();
          } catch (_) {
            // Best-effort.
          }
        }
        // Notify ChangeNotifier subscribers (e.g. the fullscreen viewer).
        notifyListeners();
      case MemoryPressureLevel.kill:
        // Persist state before the process is killed. Drafts in drift are
        // already durable (drift writes through on every mutation), so the
        // hooks here are typically a no-op; they exist for future in-memory
        // buffers (e.g. an in-progress capture form).
        for (final hook in List<KillBackupHook>.of(_killHooks)) {
          try {
            await hook.persistForKill();
          } catch (_) {
            // Best-effort; the system is killing us anyway.
          }
        }
        notifyListeners();
    }
  }

  /// Called by the coordinator after the Dart side resumes from background.
  /// Resumes all paused background work.
  void resumeBackgroundWork() {
    for (final control in List<BackgroundWorkControl>.of(_backgroundControls)) {
      try {
        control.resumeBackgroundWork();
      } catch (_) {
        // Best-effort.
      }
    }
  }
}

/// Riverpod provider for the central [MemoryPressureController]. Singleton
/// across the app lifetime.
final memoryPressureControllerProvider =
    Provider<MemoryPressureController>((ref) {
      final controller = MemoryPressureController();
      ref.onDispose(controller.dispose);
      return controller;
    });

/// Coordinates memory-pressure events between the [MemoryPressureService]
/// (native broadcasts + framework `didHaveMemoryPressure`) and the
/// [MemoryPressureController] (UI subscribers).
///
/// The coordinator is created in `_SiteMarkAppState.initState` and disposed
/// in `dispose`. It registers a handler with the service and forwards every
/// event to the controller. After the controller finishes (handlers awaited),
/// the coordinator ACKs the OEM Binder via `service.acknowledge`.
class MemoryPressureCoordinator {
  MemoryPressureCoordinator({
    required this.service,
    required this.controller,
  });

  final MemoryPressureService service;
  final MemoryPressureController controller;
  VoidCallback? _unregisterHandler;

  /// Wires the coordinator to the service. Call once after the service is
  /// initialized.
  void start() {
    _unregisterHandler = service.addHandler(_handle);
  }

  /// Detaches from the service. Call on dispose.
  void dispose() {
    _unregisterHandler?.call();
    _unregisterHandler = null;
  }

  Future<void> _handle(MemoryPressureLevel level) async {
    await controller.dispatch(level);
    // ACK the OEM Binder. `acknowledge` is a no-op when no Binder is pending
    // (e.g. for `system` level, or when running on a non-ITGSA ROM).
    await service.acknowledge(level, success: true);
  }
}
