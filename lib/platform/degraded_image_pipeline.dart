import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:image/image.dart' as img;
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/src/rust/api/image_core.dart' as rust;

class DegradedImagePipeline implements ImagePipeline {
  const DegradedImagePipeline();

  @override
  bool get isDegraded => true;

  @override
  Future<rust.ExportProjectResult> export(rust.ExportProjectRequest request) {
    throw _invalidData('degraded zip export is not implemented');
  }

  @override
  Future<rust.ExportProjectResult> exportSelection(
    rust.ExportSelectionRequest request,
  ) {
    throw _invalidData('degraded zip exportSelection is not implemented');
  }

  @override
  Future<rust.ProjectArchivePreview> readProjectArchive(String zipPath) {
    throw _invalidData('degraded zip readProjectArchive is not implemented');
  }

  @override
  Future<rust.ExtractedArchivePhoto> extractArchivePhoto(
    rust.ExtractArchivePhotoRequest request,
  ) {
    throw _invalidData('degraded zip extractArchivePhoto is not implemented');
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

Never _invalidData(String detail) {
  throw ImagePipelineException(
    ImagePipelineFailureKind.invalidData,
    'invalid_data:$detail',
  );
}
