import 'package:sitemark/domain/original_photo_state.dart';

class PhotoFileInfo {
  const PhotoFileInfo({
    required this.path,
    required this.fileSizeBytes,
    required this.width,
    required this.height,
    required this.mimeType,
  });
  final String path;
  final int fileSizeBytes;
  final int width;
  final int height;
  final String mimeType;
}

class CaptureFileInfo {
  const CaptureFileInfo({
    required this.originalState,
    this.original,
    this.watermarked,
  });
  final OriginalPhotoState originalState;
  final PhotoFileInfo? original;
  final PhotoFileInfo? watermarked;
}
