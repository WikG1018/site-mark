import 'dart:async';

import 'package:sitemark/background/capture_background_scheduler.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/diagnostics/diagnostic_event.dart';
import 'package:sitemark/diagnostics/diagnostic_recorder.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark_system_api/sitemark_system_api.dart';

/// Resolves a capture's location source with a fixed priority:
///
/// 1. Valid EXIF GPS read from the original photo.
/// 2. The record-scoped one-shot fallback [LocationResult] started when the
///    user tapped the capture button (only if permission was already granted).
/// 3. `unavailable` — the watermark still generates without coordinates.
///
/// After the location is resolved (or marked unavailable) the coordinator
/// enqueues the capture for background rendering via the
/// [CaptureBackgroundScheduler]. The foreground capture path calls [begin] to
/// fire-and-forget the entire resolution so the UI never waits on EXIF,
/// location, hashing, or rendering.
final class CaptureLocationCoordinator {
  const CaptureLocationCoordinator({
    required this.database,
    required this.platform,
    required this.scheduler,
    this.diagnostics,
    this.retryDelays = const [
      Duration(milliseconds: 500),
      Duration(seconds: 2),
    ],
  });

  final AppDatabase database;
  final PlatformServices platform;
  final CaptureBackgroundScheduler scheduler;

  /// Optional diagnostics sink. When attached, gives up after retries are
  /// recorded so a stuck `pending` location resolution is observable instead
  /// of silently waiting for startup recovery.
  final DiagnosticRecorder? diagnostics;
  final List<Duration> retryDelays;

  /// Fire-and-forgets [resolve] with `enqueue: true`. The caller (the capture
  /// button path) never awaits location, EXIF, or enqueue completion.
  void begin(String captureId, {Future<LocationResult>? fallback}) {
    unawaited(
      _resolveAndEnqueueWithRetry(
        captureId,
        fallback: fallback,
      ).catchError((Object _) {}),
    );
  }

  Future<void> _resolveAndEnqueueWithRetry(
    String captureId, {
    Future<LocationResult>? fallback,
  }) async {
    for (var attempt = 0; ; attempt++) {
      try {
        await resolve(captureId, fallback: fallback, enqueue: true);
        return;
      } catch (_) {
        if (attempt >= retryDelays.length) {
          // Startup recovery re-resolves pending rows later; recording keeps
          // the give-up visible in diagnostic bundles.
          diagnostics?.record(
            DiagnosticEvent(
              timestamp: DateTime.now(),
              category: DiagnosticCategory.processing,
              outcome: DiagnosticOutcome.failed,
              code: DiagnosticCode.unexpected,
              count: 1,
              retryCount: attempt,
            ),
          );
          rethrow;
        }
        await Future<void>.delayed(retryDelays[attempt]);
      }
    }
  }

  /// Resolves the location source for [captureId] and, when [enqueue] is true,
  /// appends the capture to the background render queue.
  ///
  /// Records whose `locationResolution` is already `resolved` or `unavailable`
  /// are skipped: the EXIF/fallback sources are only consulted once.
  Future<void> resolve(
    String captureId, {
    Future<LocationResult>? fallback,
    required bool enqueue,
  }) async {
    final record = await database.captureById(captureId);
    if (record == null) return;
    if (record.locationResolution == 'pending') {
      try {
        final metadata = await platform.inspectImage(record.originalPath);
        if (_validGps(metadata.latitude, metadata.longitude)) {
          await database.resolveCaptureLocation(
            captureId: captureId,
            resolution: 'resolved',
            outcome: 'exif',
            latitude: metadata.latitude,
            longitude: metadata.longitude,
          );
        } else {
          await _persistFallback(
            captureId,
            fallback == null ? null : await fallback,
          );
        }
      } catch (_) {
        await _persistFallback(
          captureId,
          fallback == null ? null : await fallback,
        );
      }
    }
    if (enqueue) await scheduler.enqueue(captureId);
  }

  /// Re-resolves every capture still in the `pending` location state. Used by
  /// startup recovery after camera recovery but before queue reconciliation so
  /// that pending-location rows are finalized (and thus visible to
  /// `capturesAwaitingProcessing`) before the scheduler reconciles.
  Future<void> reconcilePendingLocations() async {
    for (final row in await database.capturesAwaitingLocationResolution()) {
      await resolve(row.id, fallback: null, enqueue: false);
    }
  }

  bool _validGps(double? latitude, double? longitude) {
    return latitude != null &&
        longitude != null &&
        latitude >= -90.0 &&
        latitude <= 90.0 &&
        longitude >= -180.0 &&
        longitude <= 180.0;
  }

  Future<void> _persistFallback(
    String captureId,
    LocationResult? result,
  ) async {
    if (result != null &&
        (result.outcome == LocationOutcome.precise ||
            result.outcome == LocationOutcome.approximate) &&
        _validGps(result.latitude, result.longitude)) {
      await database.resolveCaptureLocation(
        captureId: captureId,
        resolution: 'resolved',
        outcome: result.outcome.name,
        latitude: result.latitude,
        longitude: result.longitude,
        accuracyMeters: result.accuracyMeters,
        address: result.address,
      );
    } else {
      final outcomeName = result?.outcome.name ?? 'unavailable';
      await database.resolveCaptureLocation(
        captureId: captureId,
        resolution: 'unavailable',
        outcome: outcomeName,
      );
    }
  }
}
