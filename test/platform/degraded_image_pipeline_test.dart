import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sitemark/app.dart';
import 'package:sitemark/platform/degraded_image_pipeline.dart';
import 'package:sitemark/platform/ohos_capability.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/src/rust/api/image_core.dart' as rust;

void main() {
  test('degraded pipeline implements ImagePipeline and reports degraded', () {
    const pipeline = DegradedImagePipeline();
    expect(pipeline, isA<ImagePipeline>());
    expect(pipeline.isDegraded, isTrue);
  });

  test('render writes JPEG overlay and sha256 matches the file', () async {
    final root = await Directory.systemTemp.createTemp('sitemark-degraded-');
    addTearDown(() => root.delete(recursive: true));

    final source = img.Image(width: 48, height: 32);
    img.fill(source, color: img.ColorRgb8(20, 40, 60));
    final sourcePath = '${root.path}${Platform.pathSeparator}source.jpg';
    final outputPath = '${root.path}${Platform.pathSeparator}out.jpg';
    await File(sourcePath).writeAsBytes(img.encodeJpg(source));

    const pipeline = DegradedImagePipeline();
    final result = await pipeline.render(
      rust.RenderPhotoRequest(
        sourcePath: sourcePath,
        outputPath: outputPath,
        projectName: 'p',
        workLocation: 'loc',
        workContent: 'work',
        photographer: 'cam',
        photoNumber: '001',
        capturedAt: '2026-08-18T00:00:00Z',
        position: rust.WatermarkPosition.bottomLeft,
        opacity: 1,
        accentColorArgb: 0xFFFFFFFF,
        fontScale: 1,
        localeCode: 'zh',
      ),
    );

    final output = File(outputPath);
    expect(output.existsSync(), isTrue);
    expect(result.outputPath, outputPath);
    expect(await pipeline.sha256(outputPath), result.outputSha256);
    expect(img.decodeJpg(await output.readAsBytes()), isNotNull);
  });

  test('ZIP methods throw invalid_data:', () async {
    const pipeline = DegradedImagePipeline();
    const exportRequest = rust.ExportProjectRequest(
      projectId: 'p',
      projectName: 'n',
      projectCreatedAt: '2026-01-01T00:00:00Z',
      snapshotAt: '2026-01-01T00:00:00Z',
      omittedProcessingCount: 0,
      omittedFailedCount: 0,
      outputZipPath: '/tmp/out.zip',
      includeOriginals: false,
      projectLifecycleStatus: 'active',
      projectIsPinned: false,
      watermark: rust.ExportWatermarkSettings(
        position: 'bottomLeft',
        opacity: 1,
        accentColorArgb: 0,
        fontScale: 1,
      ),
      photos: [],
      templates: [],
    );
    const selectionRequest = rust.ExportSelectionRequest(
      outputZipPath: '/tmp/sel.zip',
      includeOriginals: false,
      projects: [],
    );
    const extractRequest = rust.ExtractArchivePhotoRequest(
      zipPath: '/tmp/in.zip',
      photoNumber: '001',
      renderedDestination: '/tmp/r.jpg',
    );

    Future<void> expectInvalidData(Future<void> Function() action) async {
      try {
        await action();
        fail('expected invalid_data:');
      } catch (error) {
        expect(error.toString(), startsWith('invalid_data:'));
        expect(
          ImagePipelineException.tryParseRustError(error)?.kind,
          ImagePipelineFailureKind.invalidData,
        );
      }
    }

    await expectInvalidData(() => pipeline.export(exportRequest));
    await expectInvalidData(() => pipeline.exportSelection(selectionRequest));
    await expectInvalidData(() => pipeline.readProjectArchive('/tmp/in.zip'));
    await expectInvalidData(() => pipeline.extractArchivePhoto(extractRequest));
  });

  test('pipeline helpers switch after isOhosBuild && rustInitFailed', () {
    expect(
      resolveImagePipeline(ohosBuild: true, rustFailed: false),
      isA<RustImagePipeline>(),
    );
    expect(
      resolveImagePipeline(ohosBuild: true, rustFailed: true),
      isA<DegradedImagePipeline>(),
    );
    expect(
      resolveProjectBundlePipeline(ohosBuild: true, rustFailed: true),
      isA<DegradedProjectBundlePipeline>(),
    );
    expect(
      resolveImagePipeline(ohosBuild: false, rustFailed: true),
      isA<RustImagePipeline>(),
    );
  });

  test('rustInitFailed notifier rebuilds the image pipeline listen path', () {
    rustInitFailed = false;
    addTearDown(() {
      rustInitFailed = false;
    });

    var builds = 0;
    final provider = Provider<int>((ref) {
      attachRustInitFailureWatch(ref);
      builds += 1;
      return builds;
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(provider), 1);
    rustInitFailed = true;
    expect(container.read(provider), 2);
  });
}
