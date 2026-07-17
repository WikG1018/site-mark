import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_file_info.dart';
import 'package:sitemark/domain/original_photo_state.dart';
import 'package:sitemark/platform/platform_services.dart';

class CaptureMediaService {
  CaptureMediaService({
    required this.database,
    required this.platform,
    required this.outputPaths,
    required this.files,
  });

  final AppDatabase database;
  final PlatformServices platform;
  final CaptureOutputPaths outputPaths;
  final PrivateFileStore files;

  Future<OriginalPhotoState> originalState(CaptureRecord record) async {
    if (record.originalDeletedAt != null) {
      return OriginalPhotoState.cleared;
    }
    return await files.exists(record.originalPath)
        ? OriginalPhotoState.retained
        : OriginalPhotoState.missing;
  }

  Future<CaptureFileInfo> inspect(CaptureRecord record) async {
    final state = await originalState(record);
    final watermarkedPath = await outputPaths.renderedPhotoPath(record.id);
    return CaptureFileInfo(
      originalState: state,
      original: await _inspectPath(record.originalPath),
      watermarked: await _inspectPath(watermarkedPath),
    );
  }

  Future<PhotoFileInfo?> _inspectPath(String path) async {
    if (!await files.exists(path)) return null;
    final metadata = await platform.inspectImage(path);
    return PhotoFileInfo(
      path: path,
      fileSizeBytes: metadata.fileSizeBytes,
      width: metadata.width,
      height: metadata.height,
      mimeType: metadata.mimeType,
    );
  }
}
