import 'dart:async';

import 'package:drift/drift.dart';
import 'package:sitemark/background/capture_background_scheduler.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/workflow/capture_location_coordinator.dart';
import 'package:sitemark/workflow/capture_workflow.dart';
import 'package:sitemark_system_api/sitemark_system_api.dart';
import 'package:uuid/uuid.dart';

class GalleryImportResult {
  const GalleryImportResult(
    this.imported,
    this.failed, {
    this.cancelled = false,
  });
  final int imported;
  final int failed;
  final bool cancelled;
}

/// Copies only selected images, then reuses the ordinary durable render queue.
/// Does not call the camera or request the device's current location.
class GalleryImportService {
  GalleryImportService({
    required this.database,
    required this.api,
    required this.paths,
    required this.scheduler,
    required this.locations,
    PrivateFileStore? files,
    String Function()? idFactory,
    DateTime Function()? now,
  }) : _files = files ?? DartIoPrivateFileStore(),
       _idFactory = idFactory ?? const Uuid().v4,
       _now = now ?? DateTime.now;

  final AppDatabase database;
  final GalleryImportApi api;
  final OriginalPhotoPaths paths;
  final CaptureBackgroundScheduler scheduler;
  final CaptureLocationCoordinator locations;
  final PrivateFileStore _files;
  final String Function() _idFactory;
  final DateTime Function() _now;
  Future<void> _tail = Future.value();

  Future<T> _serial<T>(Future<T> Function() action) async {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    await previous;
    try {
      return await action();
    } finally {
      done.complete();
    }
  }

  Future<GalleryImportResult> pickAndImport(
    CaptureDraft draft, {
    void Function(int completed, int total)? onProgress,
  }) => _serial(() async {
    await _recover();
    final selected = (await api.pickImages()).toSet().toList();
    if (selected.isEmpty) {
      return const GalleryImportResult(0, 0, cancelled: true);
    }
    final ids = <String>[];
    try {
      if (selected.length > 20) throw StateError('Too many images');
      final originalPaths = <String>[];
      for (var index = 0; index < selected.length; index++) {
        final id = _idFactory();
        ids.add(id);
        originalPaths.add(await paths.originalPhotoPath(id));
      }
      await database.transaction(() async {
        for (var i = 0; i < ids.length; i++) {
          await database.createPendingCapture(
            id: ids[i],
            projectId: draft.projectId,
            originalPath: originalPaths[i],
            workLocation: draft.workLocation,
            workContent: draft.workContent,
            photographer: draft.photographer,
            notes: draft.notes,
            watermarkLocaleCode: draft.watermarkLocaleCode,
            watermarkTime: draft.watermarkTime,
            captureSource: 'gallery',
            createdAt: _now(),
          );
          await database
              .into(database.galleryImportTasks)
              .insert(
                GalleryImportTasksCompanion.insert(
                  captureId: ids[i],
                  sourceUri: selected[i],
                ),
              );
        }
      });
    } catch (_) {
      await _release(selected);
      rethrow;
    }
    var imported = 0;
    var failed = 0;
    onProgress?.call(0, ids.length);
    for (var i = 0; i < ids.length; i++) {
      final task = GalleryImportTask(captureId: ids[i], sourceUri: selected[i]);
      if (await _copy(task)) {
        imported++;
      } else {
        failed++;
      }
      onProgress?.call(i + 1, ids.length);
    }
    return GalleryImportResult(imported, failed);
  });

  Future<void> recover() => _serial(_recover);

  Future<void> _recover() async {
    for (final task
        in await database.select(database.galleryImportTasks).get()) {
      await _copy(task);
    }
  }

  Future<void> _release(List<String> uris) async {
    try {
      await api.releaseImages(uris);
    } catch (_) {
      /* No source deletion. */
    }
  }

  Future<bool> _copy(GalleryImportTask task) async {
    final record = await database.captureById(task.captureId);
    if (record == null ||
        record.captureSource != 'gallery' ||
        record.status != CaptureStatus.pendingCamera) {
      if (record == null) {
        final path = await paths.originalPhotoPath(task.captureId);
        await _files.deleteIfExists(path);
        await _files.deleteIfExists('$path.part');
      }
      await _complete(task);
      return record != null;
    }
    GalleryImageCopy copy;
    try {
      copy = await api.copyImage(task.sourceUri, task.captureId);
      if (copy.originalPath != record.originalPath) {
        throw StateError('Unexpected original path');
      }
    } catch (_) {
      // Invalid/unsupported files never become misleading failed camera shots.
      // The system gallery original remains untouched; the UI reports a count
      // and asks the user to select JPEG/PNG again.
      await _files.deleteIfExists(record.originalPath);
      await _files.deleteIfExists('${record.originalPath}.part');
      await database.transaction(() async {
        await database.deleteCapture(task.captureId);
        await (database.delete(
          database.galleryImportTasks,
        )..where((t) => t.captureId.equals(task.captureId))).go();
      });
      await _release([task.sourceUri]);
      return false;
    }
    final sourceTime = copy.capturedAtMillis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(copy.capturedAtMillis!);
    // A DB failure keeps the task and the complete atomic original. Startup
    // retries the commit without copying or changing the source bytes again.
    final committed = await database.transaction(() async {
      final current = await database.captureById(task.captureId);
      if (current == null) return false;
      await (database.update(
        database.captureRecords,
      )..where((c) => c.id.equals(task.captureId))).write(
        CaptureRecordsCompanion(
          sourceCapturedAt: Value(sourceTime),
          locationResolution: const Value('pending'),
        ),
      );
      await database.markCaptured(
        captureId: task.captureId,
        capturedAt: sourceTime ?? record.createdAt,
      );
      await (database.delete(
        database.galleryImportTasks,
      )..where((t) => t.captureId.equals(task.captureId))).go();
      return true;
    });
    if (!committed) {
      await _files.deleteIfExists(record.originalPath);
      await _complete(task);
      return false;
    }
    await _release([task.sourceUri]);
    // EXIF-only: never attach today's location to an older imported image.
    locations.begin(task.captureId, fallback: null);
    try {
      await scheduler.enqueue(task.captureId);
    } catch (_) {
      // Location resolution and startup reconciliation retry scheduling.
    }
    return true;
  }

  Future<void> _complete(GalleryImportTask task) async {
    await (database.delete(
      database.galleryImportTasks,
    )..where((t) => t.captureId.equals(task.captureId))).go();
    await _release([task.sourceUri]);
  }
}
