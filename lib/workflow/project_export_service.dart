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
  });

  final AppDatabase database;
  final ImagePipeline images;
  final CaptureOutputPaths capturePaths;
  final ProjectExportPaths exportPaths;

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
