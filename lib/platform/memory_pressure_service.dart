import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Fair-memory pressure levels defined by the ITGSA (金标联盟) "fair running
/// memory" mechanism. Translated from the native `itgsa.intent.action.*`
/// broadcasts so the Dart side does not have to know intent strings.
///
/// The same enum is used to carry Flutter's own
/// [WidgetsBindingObserver.didHaveMemoryPressure] signal so a single
/// pipeline handles both system and OEM memory-trim sources.
enum MemoryPressureLevel {
  /// Generic memory-pressure callback from the Flutter framework. Releases
  /// caches that are cheap to rebuild (image cache, unused isolate buffers).
  system,

  /// ITGSA `itgsa.intent.action.MEMORY_TRIM`: the OEM asks backgrounded apps
  /// to release everything that is not strictly required to preserve the
  /// visible state. Must be honored within a short window and the result
  /// reported back to the system via [MemoryPressureService.acknowledge].
  trim,

  /// ITGSA `itgsa.intent.action.MEMORY_KILL`: the OEM is about to kill the
  /// process. The app must persist any unsaved draft state so the next cold
  /// start can restore it. The result must be reported back via
  /// [MemoryPressureService.acknowledge].
  kill,
}

typedef MemoryPressureHandler = Future<void> Function(MemoryPressureLevel level);

/// Abstraction over the native side that:
///
/// 1. Listens for ITGSA `MEMORY_TRIM` / `MEMORY_KILL` broadcasts (registered
///    in `AndroidManifest.xml` and forwarded through a `MethodChannel`).
/// 2. Forwards them to Dart handlers registered via [addHandler].
/// 3. Calls back into native code with `acknowledge(level, success)` so the
///    OEM Binder callback receives the result (required by the spec).
abstract class MemoryPressureService {
  /// Starts forwarding native broadcasts to registered handlers. Idempotent.
  /// Returns after the native channel is wired but before any broadcast
  /// arrives.
  Future<void> initialize();

  /// Registers a handler invoked for every pressure event. Handlers are
  /// awaited in registration order; a failing handler does not prevent later
  /// handlers from running. Returns an unregister function.
  VoidCallback addHandler(MemoryPressureHandler handler);

  /// Reports the Dart-side result back to the OEM Binder so the system knows
  /// the pressure event was handled. Safe to call when no native callback is
  /// pending (no-op).
  Future<void> acknowledge(MemoryPressureLevel level, {required bool success});
}

/// Riverpod provider. Production wires [PlatformMemoryPressureService]
/// via `MyApp(memoryPressureService: ...)`; the default [NoopMemoryPressureService]
/// keeps tests (and any non-ITGSA platform) running without extra overrides.
final memoryPressureServiceProvider =
    Provider<MemoryPressureService>((ref) {
      return NoopMemoryPressureService();
    });

/// Production implementation backed by a [MethodChannel] named
/// `sitemark/memory_pressure`.
///
/// The channel is two-way:
/// - Native → Dart: the `onMemoryPressure` method call carries `{level}` and
///   triggers registered handlers.
/// - Dart → Native: `acknowledge(level, success)` completes the OEM Binder
///   callback set up by `MemoryPressureReceiver`.
class PlatformMemoryPressureService implements MemoryPressureService {
  PlatformMemoryPressureService()
    : _channel = const MethodChannel('sitemark/memory_pressure');

  @visibleForTesting
  PlatformMemoryPressureService.channel(this._channel);

  final MethodChannel _channel;
  final List<MemoryPressureHandler> _handlers = [];
  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onMemoryPressure') {
        final raw = call.arguments is Map
            ? (call.arguments as Map<Object?, Object?>)['level']
            : null;
        final level = _parseLevel(raw);
        if (level == null) return null;
        await _dispatch(level);
      }
      return null;
    });
  }

  @override
  VoidCallback addHandler(MemoryPressureHandler handler) {
    _handlers.add(handler);
    return () => _handlers.remove(handler);
  }

  @override
  Future<void> acknowledge(
    MemoryPressureLevel level, {
    required bool success,
  }) async {
    if (!_initialized) return;
    // The native side ignores acks for levels it did not originate (e.g. the
    // Flutter framework's didHaveMemoryPressure). Calling it unconditionally
    // keeps the Dart code simple and is a no-op when no Binder callback is
    // pending.
    try {
      await _channel.invokeMethod<void>('acknowledge', {
        'level': _levelName(level),
        'success': success,
      });
    } on PlatformException {
      // Native side may not be listening (e.g. running on a non-ITGSA ROM or
      // in a widget test where the channel has no handler). Swallow so the
      // caller never sees a failure for ack-only traffic.
    }
  }

  Future<void> _dispatch(MemoryPressureLevel level) async {
    // Snapshot to avoid concurrent modification while iterating.
    final handlers = List<MemoryPressureHandler>.of(_handlers);
    for (final handler in handlers) {
      try {
        await handler(level);
      } catch (_, stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: 'Memory-pressure handler failed: $level',
            stack: stack,
            library: 'sitemark.platform',
          ),
        );
      }
    }
  }

  static MemoryPressureLevel? _parseLevel(Object? raw) {
    if (raw is String) {
      return switch (raw) {
        'system' => MemoryPressureLevel.system,
        'trim' => MemoryPressureLevel.trim,
        'kill' => MemoryPressureLevel.kill,
        _ => null,
      };
    }
    return null;
  }

  static String _levelName(MemoryPressureLevel level) => switch (level) {
    MemoryPressureLevel.system => 'system',
    MemoryPressureLevel.trim => 'trim',
    MemoryPressureLevel.kill => 'kill',
  };
}

/// A no-op implementation used when the production service is not available
/// (e.g. pure-Dart unit tests that don't exercise memory pressure).
class NoopMemoryPressureService implements MemoryPressureService {
  @override
  Future<void> initialize() async {}

  @override
  VoidCallback addHandler(MemoryPressureHandler handler) {
    return () {};
  }

  @override
  Future<void> acknowledge(
    MemoryPressureLevel level, {
    required bool success,
  }) async {}
}
