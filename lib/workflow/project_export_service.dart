import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/src/rust/api/image_core.dart';

class ProjectExportService {
  const ProjectExportService({
    required this.database,
    required this.images,
    required this.capturePaths,
    required this.exportPaths,
    required this.selectionExportPaths,
  });

  final AppDatabase database;
  final ImagePipeline images;
  final CaptureOutputPaths capturePaths;
  final ProjectExportPaths exportPaths;
  final SelectionExportPaths selectionExportPaths;

  Future<ExportProjectResult> exportProject({
    required String projectId,
    required bool includeOriginals,
  }) async {
    final project = await database.projectById(projectId);
    if (project == null) throw StateError('Project does not exist');
    final captures = (await database.capturesForProject(
      projectId,
    )).where((capture) => capture.status == CaptureStatus.ready).toList();
    if (captures.isEmpty) {
      throw StateError('Project has no completed captures to export');
    }
    final photos = <ExportPhotoRecord>[];
    for (final capture in captures) {
      photos.add(
        ExportPhotoRecord(
          photoNumber: capture.photoNumber!,
          watermarkedPath: await capturePaths.renderedPhotoPath(capture.id),
          originalPath: includeOriginals ? capture.originalPath : null,
          originalSha256: capture.originalSha256!,
          capturedAt: _formatLocalTimestamp(capture.capturedAt!),
          workLocation: capture.workLocation,
          workContent: capture.workContent,
          photographer: capture.photographer,
          address: capture.address,
          coordinates: _coordinates(capture),
          notes: capture.notes,
        ),
      );
    }
    final outputPath = await exportPaths.projectZipPath(projectId);
    return images.export(
      ExportProjectRequest(
        projectId: project.id,
        projectName: project.name,
        outputZipPath: outputPath,
        includeOriginals: includeOriginals,
        photos: photos,
      ),
    );
  }

  /// Exports a cross-project ZIP containing every selected capture grouped by
  /// project. Rejects any non-`ready` capture, groups by project ID, preserves
  /// each group's capture-time order, omits originals whose
  /// `originalDeletedAt` is non-null, and fails an `includeOriginals: true`
  /// request when any selected original is unavailable.
  Future<ExportProjectResult> exportSelection({
    required List<String> captureIds,
    required bool includeOriginals,
  }) async {
    if (captureIds.isEmpty) {
      throw StateError('No captures selected for export');
    }
    final captures = await database.capturesByIds(captureIds);
    if (captures.isEmpty) {
      throw StateError('No captures found for the given IDs');
    }
    for (final capture in captures) {
      if (capture.status != CaptureStatus.ready) {
        throw StateError(
          'Capture ${capture.id} is not ready for export (status=${capture.status.name})',
        );
      }
    }
    final byProject = <String, List<CaptureRecord>>{};
    for (final capture in captures) {
      byProject.putIfAbsent(capture.projectId, () => []).add(capture);
    }
    final projects = <ExportSelectionProject>[];
    for (final entry in byProject.entries) {
      final projectId = entry.key;
      final project = await database.projectById(projectId);
      if (project == null) {
        throw StateError('Project $projectId does not exist');
      }
      final photos = <ExportPhotoRecord>[];
      for (final capture in entry.value) {
        String? originalPath;
        if (includeOriginals) {
          if (capture.originalDeletedAt != null) {
            throw StateError(
              'Capture ${capture.id} original is unavailable (cleared)',
            );
          }
          originalPath = capture.originalPath;
        }
        photos.add(
          ExportPhotoRecord(
            photoNumber: capture.photoNumber!,
            watermarkedPath: await capturePaths.renderedPhotoPath(capture.id),
            originalPath: originalPath,
            originalSha256: capture.originalSha256!,
            capturedAt: _formatLocalTimestamp(capture.capturedAt!),
            workLocation: capture.workLocation,
            workContent: capture.workContent,
            photographer: capture.photographer,
            address: capture.address,
            coordinates: _coordinates(capture),
            notes: capture.notes,
          ),
        );
      }
      projects.add(
        ExportSelectionProject(
          projectId: projectId,
          projectName: project.name,
          photos: photos,
        ),
      );
    }
    final outputPath = await selectionExportPaths.selectionZipPath();
    return images.exportSelection(
      ExportSelectionRequest(
        outputZipPath: outputPath,
        includeOriginals: includeOriginals,
        projects: projects,
      ),
    );
  }

  static String? _coordinates(CaptureRecord capture) {
    if (capture.latitude == null || capture.longitude == null) return null;
    return '${capture.latitude!.toStringAsFixed(6)}, '
        '${capture.longitude!.toStringAsFixed(6)}'
        '${capture.accuracyMeters == null ? '' : ' · ±${capture.accuracyMeters!.round()}m'}';
  }

  static String _formatLocalTimestamp(DateTime value) {
    final offset = value.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final absoluteMinutes = offset.inMinutes.abs();
    String two(int part) => part.toString().padLeft(2, '0');
    return '${value.year.toString().padLeft(4, '0')}-'
        '${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}:${two(value.second)} '
        '$sign${two(absoluteMinutes ~/ 60)}:${two(absoluteMinutes % 60)}';
  }
}
