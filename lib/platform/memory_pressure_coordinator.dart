import 'dart:async';

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
///
/// The controller exposes three orthogonal operations that callers combine
/// depending on the source of the pressure event:
///
/// - [pauseBackgroundWork] / [resumeBackgroundWork] — gate the conditional
///   polling streams. Only pair with backgrounding (lifecycle `paused`/
///   `hidden`) or a real OEM TRIM/KILL broadcast; never with a foreground
///   `didHaveMemoryPressure` (which fires on transient `onTrimMemory` while
///   the user is still looking at the app).
/// - [releaseResources] — clear the image cache and notify release handlers.
///   Safe to call from any pressure source.
/// - [dispatch] — entry point for native OEM broadcasts (TRIM/KILL). TRIM
///   pauses + releases; KILL runs the kill hooks. Used by the coordinator
///   for the MethodChannel path.
class MemoryPressureController {
  final List<BackgroundWorkControl> _backgroundControls = [];
  final List<VoidCallback> _releaseHandlers = [];
  final List<KillBackupHook> _killHooks = [];

  MemoryPressureLevel? _lastLevel;

  /// The most recent pressure level dispatched via [dispatch], or `null` if
  /// none has been dispatched. Does not update on bare [releaseResources] /
  /// [pauseBackgroundWork] calls.
  MemoryPressureLevel? get lastLevel => _lastLevel;

  /// Attaches a [BackgroundWorkControl] so its work is paused/resumed by
  /// [pauseBackgroundWork] / [resumeBackgroundWork]. Returns an unsubscribe
  /// function.
  VoidCallback attachBackground(BackgroundWorkControl control) {
    _backgroundControls.add(control);
    return () => _backgroundControls.remove(control);
  }

  /// Attaches a release handler invoked on every [releaseResources] call
  /// (and therefore on every TRIM/system dispatch). Use this for resources
  /// that should be released but cannot implement [BackgroundWorkControl]
  /// (e.g. a fullscreen image route). Returns an unsubscribe function.
  VoidCallback attachRelease(VoidCallback handler) {
    _releaseHandlers.add(handler);
    return () => _releaseHandlers.remove(handler);
  }

  /// Attaches a [KillBackupHook] invoked on every KILL dispatch. Returns an
  /// unsubscribe function.
  VoidCallback attachKillHook(KillBackupHook hook) {
    _killHooks.add(hook);
    return () => _killHooks.remove(hook);
  }

  /// Pauses all attached [BackgroundWorkControl]s. Safe to call repeatedly.
  /// Does NOT release image caches or notify release handlers — pair with
  /// [releaseResources] when both are needed (e.g. backgrounding).
  void pauseBackgroundWork() {
    for (final control in List<BackgroundWorkControl>.of(_backgroundControls)) {
      try {
        control.pauseBackgroundWork();
      } catch (_) {
        // Best-effort; a failing control must not block others.
      }
    }
  }

  /// Clears the Flutter image cache and notifies all release handlers.
  /// Safe to call from any pressure source (foreground `onTrimMemory`,
  /// background TRIM, etc.) and safe to call repeatedly.
  void releaseResources() {
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
  }

  /// Called by the coordinator for native OEM broadcasts (TRIM/KILL). For
  /// TRIM this pauses background work and releases resources; for KILL this
  /// runs the kill hooks. The coordinator awaits this before ACKing the
  /// OEM Binder.
  ///
  /// Note: the framework's `didHaveMemoryPressure` and the lifecycle
  /// `paused`/`hidden` states do NOT go through this method — they call
  /// [releaseResources] / [pauseBackgroundWork] directly so the foreground
  /// pressure path does not stall the polling streams (see ITGSA C1 fix).
  Future<void> dispatch(MemoryPressureLevel level) async {
    _lastLevel = level;
    switch (level) {
      case MemoryPressureLevel.system:
      case MemoryPressureLevel.trim:
        // OEM TRIM: the app is being asked to release memory while
        // backgrounded. Pause polling and release caches.
        pauseBackgroundWork();
        releaseResources();
      case MemoryPressureLevel.kill:
        // Persist state before the process is killed. Drift writes through
        // on every mutation so captured records are already durable; the
        // hooks here cover in-memory buffers (e.g. an in-progress capture
        // form draft).
        for (final hook in List<KillBackupHook>.of(_killHooks)) {
          try {
            await hook.persistForKill();
          } catch (_) {
            // Best-effort; the system is killing us anyway.
          }
        }
    }
  }

  /// Resumes all attached [BackgroundWorkControl]s. Safe to call repeatedly
  /// and when nothing was paused.
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
      // No explicit dispose needed: the controller holds only lists of
      // detach callbacks owned by their registrants, which detach on their
      // own dispose. Keeping a no-op onDispose makes future migration to a
      // disposable controller trivial.
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
