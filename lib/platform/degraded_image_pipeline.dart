import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:image/image.dart' as img;
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/src/rust/api/image_core.dart' as rust;

const _projectBundleKind = 'sitemark-project-bundle';
const _maxBundleProjects = 100;
final _unsafeArchiveChars = RegExp(r'[/\\:*?"<>|]');
final _csvSpecialChars = RegExp(r'[,"\r\n]');

class DegradedImagePipeline implements ImagePipeline {
  const DegradedImagePipeline();

  @override
  bool get isDegraded => true;

  @override
  Future<rust.ExportProjectResult> export(
    rust.ExportProjectRequest request,
  ) async {
    if (request.projectName.trim().isEmpty) {
      throw _invalidData('validate export request: project name is required');
    }
    if (!_isValidLifecycleStatus(request.projectLifecycleStatus)) {
      throw _invalidData(
        'validate export request: unsupported project lifecycle status ${request.projectLifecycleStatus}',
      );
    }

    final archive = Archive();
    for (final photo in request.photos) {
      final safeNumber = _safePhotoNumberComponent(photo.photoNumber);
      _addFileToZip(
        archive,
        photo.watermarkedPath,
        'photos/$safeNumber.jpg',
      );
      if (request.includeOriginals) {
        final original = photo.originalPath;
        if (original == null || original.isEmpty) {
          throw _invalidData(
            'validate export request: missing original for ${photo.photoNumber}',
          );
        }
        final extension = _originalExtension(original);
        _addFileToZip(
          archive,
          original,
          'originals/$safeNumber.$extension',
        );
      }
    }

    _addBytes(archive, 'records.csv', _recordsCsv(request.projectName, request.photos));
    _addBytes(
      archive,
      'manifest.json',
      utf8.encode(_prettyJson(_projectManifest(request))),
    );
    return _writeZip(request.outputZipPath, archive, request.photos.length);
  }

  @override
  Future<rust.ExportProjectResult> exportSelection(
    rust.ExportSelectionRequest request,
  ) async {
    if (request.projects.isEmpty) {
      throw _invalidData('validate export request: project list is empty');
    }
    final totalPhotos = request.projects.fold<int>(
      0,
      (sum, project) => sum + project.photos.length,
    );
    if (totalPhotos == 0) {
      throw _invalidData('validate export request: no photos to export');
    }

    for (final project in request.projects) {
      _safeArchiveComponent(project.projectId);
      if (project.projectName.trim().isEmpty) {
        throw _invalidData('validate export request: project name is required');
      }
      for (final photo in project.photos) {
        _safePhotoNumberComponent(photo.photoNumber);
      }
    }

    final archive = Archive();
    final csvRows = <_CsvPhotoRow>[];
    for (final project in request.projects) {
      final safeProjectId = _safeArchiveComponent(project.projectId);
      for (final photo in project.photos) {
        final safeNumber = _safePhotoNumberComponent(photo.photoNumber);
        _addFileToZip(
          archive,
          photo.watermarkedPath,
          'projects/$safeProjectId/photos/$safeNumber.jpg',
        );
        if (request.includeOriginals) {
          final original = photo.originalPath;
          if (original == null || original.isEmpty) {
            throw _invalidData(
              'validate export request: missing original for ${photo.photoNumber}',
            );
          }
          final extension = _originalExtension(original);
          _addFileToZip(
            archive,
            original,
            'projects/$safeProjectId/originals/$safeNumber.$extension',
          );
        }
        csvRows.add(_CsvPhotoRow(project.projectName, photo));
      }
    }

    _addBytes(archive, 'records.csv', _recordsCsvFromRows(csvRows));
    _addBytes(
      archive,
      'manifest.json',
      utf8.encode(
        _prettyJson({
          'schema_version': 1,
          'app': 'SiteMark',
          'includes_originals': request.includeOriginals,
          'projects': [
            for (final project in request.projects)
              {
                'project_id': project.projectId,
                'project_name': project.projectName,
                'photos': [
                  for (final photo in project.photos) _photoJson(photo),
                ],
              },
          ],
        }),
      ),
    );
    return _writeZip(request.outputZipPath, archive, totalPhotos);
  }

  @override
  Future<rust.ProjectArchivePreview> readProjectArchive(String zipPath) {
    throw _invalidData(
      'degraded zip readProjectArchive is not implemented',
    );
  }

  @override
  Future<rust.ExtractedArchivePhoto> extractArchivePhoto(
    rust.ExtractArchivePhotoRequest request,
  ) {
    throw _invalidData(
      'degraded zip extractArchivePhoto is not implemented',
    );
  }

  @override
  Future<String> sha256(String path) async {
    final bytes = await File(path).readAsBytes();
    return crypto.sha256.convert(bytes).toString();
  }

  @override
  Future<rust.RenderPhotoResult> render(rust.RenderPhotoRequest request) async {
    final source = File(request.sourcePath);
    if (!source.existsSync()) {
      throw const ImagePipelineException(
        ImagePipelineFailureKind.notFound,
        'not_found:open original',
      );
    }

    final decoded = img.decodeImage(await source.readAsBytes());
    if (decoded == null) {
      throw _invalidData('decode jpeg');
    }

    img.drawString(
      decoded,
      'SiteMark',
      font: img.arial24,
      x: 16,
      y: 16,
      color: img.ColorRgb8(255, 255, 255),
    );

    final encoded = img.encodeJpg(decoded);
    final output = File(request.outputPath);
    await output.parent.create(recursive: true);
    await output.writeAsBytes(Uint8List.fromList(encoded), flush: true);

    return rust.RenderPhotoResult(
      outputPath: request.outputPath,
      outputSha256: crypto.sha256.convert(encoded).toString(),
      width: decoded.width,
      height: decoded.height,
    );
  }
}

class DegradedProjectBundlePipeline implements ProjectBundlePipeline {
  const DegradedProjectBundlePipeline();

  @override
  Future<rust.ExportProjectResult> exportBundle(
    rust.ExportProjectBundleRequest request,
  ) async {
    if (request.projects.isEmpty) {
      throw _invalidData('validate project bundle: project list is empty');
    }
    if (request.projects.length > _maxBundleProjects) {
      throw _invalidData(
        'validate project bundle: too many projects',
      );
    }

    final archive = Archive();
    final entries = <Map<String, dynamic>>[];
    for (final project in request.projects) {
      final safeId = _safeArchiveComponent(project.projectId);
      if (project.projectName.trim().isEmpty) {
        throw _invalidData('validate project bundle: project name is required');
      }
      final bytes = _readExistingFile(project.archivePath, 'open project ZIP');
      final digest = crypto.sha256.convert(bytes).toString();
      final archivePath = 'projects/$safeId.zip';
      _addBytes(archive, archivePath, bytes);
      entries.add({
        'project_id': project.projectId,
        'project_name': project.projectName,
        'archive_path': archivePath,
        'archive_sha256': digest,
      });
    }

    _addBytes(
      archive,
      'bundle.json',
      utf8.encode(
        _prettyJson({
          'kind': _projectBundleKind,
          'schema_version': 1,
          'created_at': DateTime.now().toUtc().millisecondsSinceEpoch.toString(),
          'projects': entries,
        }),
      ),
    );
    return _writeZip(
      request.outputZipPath,
      archive,
      request.projects.length,
    );
  }

  @override
  Future<void> extractBundleEntry(
    rust.ExtractProjectBundleEntryRequest request,
  ) {
    throw _invalidData(
      'degraded zip extractBundleEntry is not implemented',
    );
  }

  @override
  Future<rust.ProjectBundlePreview> readBundle(String zipPath) {
    throw _invalidData('degraded zip readBundle is not implemented');
  }
}

class _CsvPhotoRow {
  const _CsvPhotoRow(this.projectName, this.photo);

  final String projectName;
  final rust.ExportPhotoRecord photo;
}

Map<String, dynamic> _projectManifest(rust.ExportProjectRequest request) {
  return {
    'schema_version': 5,
    'app': 'SiteMark',
    'project_id': request.projectId,
    'project_name': request.projectName,
    'project_description': request.projectDescription,
    'project_created_at': request.projectCreatedAt,
    'snapshot_at': request.snapshotAt,
    'omitted_processing_count': request.omittedProcessingCount,
    'omitted_failed_count': request.omittedFailedCount,
    'includes_originals': request.includeOriginals,
    'project_lifecycle_status': request.projectLifecycleStatus,
    'project_is_pinned': request.projectIsPinned,
    'watermark': {
      'position': request.watermark.position,
      'opacity': request.watermark.opacity,
      'accent_color_argb': request.watermark.accentColorArgb,
      'font_scale': request.watermark.fontScale,
    },
    'photos': [for (final photo in request.photos) _photoJson(photo)],
    'templates': [
      for (final template in request.templates)
        {
          'name': template.name,
          'work_location': template.workLocation,
          'work_content': template.workContent,
          'photographer': template.photographer,
          'created_at': template.createdAt,
          'updated_at': template.updatedAt,
        },
    ],
  };
}

Map<String, dynamic> _photoJson(rust.ExportPhotoRecord photo) {
  return {
    'photo_number': photo.photoNumber,
    'watermarked_path': photo.watermarkedPath,
    'original_path': photo.originalPath,
    'original_sha256': photo.originalSha256,
    'captured_at': photo.capturedAt,
    'work_location': photo.workLocation,
    'work_content': photo.workContent,
    'photographer': photo.photographer,
    'address': photo.address,
    'coordinates': photo.coordinates,
    'notes': photo.notes,
    'latitude': photo.latitude,
    'longitude': photo.longitude,
    'accuracy_meters': photo.accuracyMeters,
    'watermark_locale_code': photo.watermarkLocaleCode,
  };
}

List<int> _recordsCsv(String projectName, List<rust.ExportPhotoRecord> photos) {
  return _recordsCsvFromRows([
    for (final photo in photos) _CsvPhotoRow(projectName, photo),
  ]);
}

List<int> _recordsCsvFromRows(List<_CsvPhotoRow> rows) {
  final buffer = StringBuffer()
    ..writeln(
      'project_name,photo_number,captured_at,work_location,work_content,photographer,address,coordinates,notes,original_sha256',
    );
  for (final row in rows) {
    final photo = row.photo;
    buffer.writeln(
      [
        _csvField(row.projectName),
        _csvField(photo.photoNumber),
        _csvField(photo.capturedAt),
        _csvField(photo.workLocation),
        _csvField(photo.workContent),
        _csvField(photo.photographer),
        _csvField(photo.address ?? ''),
        _csvField(photo.coordinates ?? ''),
        _csvField(photo.notes ?? ''),
        _csvField(photo.originalSha256),
      ].join(','),
    );
  }
  return [0xef, 0xbb, 0xbf, ...utf8.encode(buffer.toString())];
}

String _csvField(String value) {
  if (!_csvSpecialChars.hasMatch(value)) {
    return value;
  }
  return '"${value.replaceAll('"', '""')}"';
}

String _prettyJson(Map<String, dynamic> value) {
  return const JsonEncoder.withIndent('  ').convert(value);
}

Future<rust.ExportProjectResult> _writeZip(
  String outputZipPath,
  Archive archive,
  int photoCount,
) async {
  final encoded = ZipEncoder().encode(archive);
  final output = File(outputZipPath);
  try {
    await output.parent.create(recursive: true);
    await output.writeAsBytes(encoded, flush: true);
  } on FileSystemException catch (error) {
    throw ImagePipelineException(
      ImagePipelineFailureKind.transientIo,
      'io:write ZIP: $error',
    );
  }
  return rust.ExportProjectResult(
    outputZipPath: outputZipPath,
    archiveSha256: crypto.sha256.convert(encoded).toString(),
    photoCount: photoCount,
  );
}

void _addFileToZip(Archive archive, String sourcePath, String zipPath) {
  _addBytes(archive, zipPath, _readExistingFile(sourcePath, 'open ZIP source'));
}

void _addBytes(Archive archive, String zipPath, List<int> bytes) {
  archive.addFile(ArchiveFile.bytes(zipPath, bytes));
}

Uint8List _readExistingFile(String path, String context) {
  final file = File(path);
  if (!file.existsSync()) {
    throw ImagePipelineException(
      ImagePipelineFailureKind.notFound,
      'not_found:$context',
    );
  }
  try {
    return file.readAsBytesSync();
  } on FileSystemException catch (error) {
    throw ImagePipelineException(
      ImagePipelineFailureKind.transientIo,
      'io:$context: $error',
    );
  }
}

String _originalExtension(String path) {
  final name = path.split(RegExp(r'[/\\]')).last;
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) {
    return 'jpg';
  }
  return name.substring(dot + 1).toLowerCase();
}

bool _isValidLifecycleStatus(String status) {
  return status == 'active' || status == 'completed' || status == 'archived';
}

String _safePhotoNumberComponent(String value) {
  return _safeArchiveComponent(value, label: 'photo number');
}

String _safeArchiveComponent(String value, {String label = 'archive component'}) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw _invalidData('validate export request: $label is empty');
  }
  if (trimmed.contains('\uFEFF') ||
      trimmed.runes.any((code) => code < 32) ||
      trimmed.contains(RegExp(r'\s')) ||
      _unsafeArchiveChars.hasMatch(trimmed)) {
    throw _invalidData('validate export request: invalid $label $value');
  }
  return trimmed;
}

Never _invalidData(String detail) {
  throw ImagePipelineException(
    ImagePipelineFailureKind.invalidData,
    'invalid_data:$detail',
  );
}
