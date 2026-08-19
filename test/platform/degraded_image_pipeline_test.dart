import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sitemark/app.dart';
import 'package:sitemark/platform/degraded_image_pipeline.dart';
import 'package:sitemark/platform/ohos_capability.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/src/rust/api/image_core.dart' as rust;

const _watermark = rust.ExportWatermarkSettings(
  position: 'bottomLeft',
  opacity: 1,
  accentColorArgb: 0,
  fontScale: 1,
);

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

  test('export writes a schema 5 zip with manifest and records.csv', () async {
    final root = await Directory.systemTemp.createTemp('sitemark-degraded-zip-');
    addTearDown(() => root.delete(recursive: true));
    final outputZipPath = '${root.path}${Platform.pathSeparator}out.zip';

    const pipeline = DegradedImagePipeline();
    final result = await pipeline.export(
      rust.ExportProjectRequest(
        projectId: 'p',
        projectName: 'n',
        projectCreatedAt: '2026-01-01T00:00:00Z',
        snapshotAt: '2026-01-01T00:00:00Z',
        omittedProcessingCount: 0,
        omittedFailedCount: 0,
        outputZipPath: outputZipPath,
        includeOriginals: false,
        projectLifecycleStatus: 'active',
        projectIsPinned: false,
        watermark: _watermark,
        photos: const [],
        templates: const [],
      ),
    );

    final zipFile = File(outputZipPath);
    expect(zipFile.existsSync(), isTrue);
    expect(await zipFile.length(), greaterThan(0));
    expect(result.outputZipPath, outputZipPath);
    expect(result.photoCount, 0);
    expect(
      result.archiveSha256,
      crypto.sha256.convert(await zipFile.readAsBytes()).toString(),
    );

    final archive = ZipDecoder().decodeBytes(await zipFile.readAsBytes());
    final manifestFile = archive.findFile('manifest.json');
    expect(manifestFile, isNotNull);
    final manifest =
        jsonDecode(utf8.decode(manifestFile!.content as List<int>))
            as Map<String, dynamic>;
    expect(manifest['schema_version'], 5);
    expect(manifest['app'], 'SiteMark');
    expect(manifest['project_id'], 'p');
    expect(manifest['project_name'], 'n');
    expect(manifest['includes_originals'], isFalse);
    expect(manifest['project_lifecycle_status'], 'active');
    expect(manifest['photos'], isEmpty);

    final csvFile = archive.findFile('records.csv');
    expect(csvFile, isNotNull);
    final csvBytes = csvFile!.content as List<int>;
    expect(csvBytes.take(3), [0xef, 0xbb, 0xbf]);
    expect(
      utf8.decode(csvBytes.skip(3).toList()),
      startsWith(
        'project_name,photo_number,captured_at,work_location,work_content,photographer,address,coordinates,notes,original_sha256',
      ),
    );
  });

  test('export rejects an invalid lifecycle status', () async {
    final root = await Directory.systemTemp.createTemp(
      'sitemark-degraded-zip-bad-',
    );
    addTearDown(() => root.delete(recursive: true));

    try {
      await const DegradedImagePipeline().export(
        rust.ExportProjectRequest(
          projectId: 'p',
          projectName: 'n',
          projectCreatedAt: '2026-01-01T00:00:00Z',
          snapshotAt: '2026-01-01T00:00:00Z',
          omittedProcessingCount: 0,
          omittedFailedCount: 0,
          outputZipPath: '${root.path}${Platform.pathSeparator}out.zip',
          includeOriginals: false,
          projectLifecycleStatus: 'draft',
          projectIsPinned: false,
          watermark: _watermark,
          photos: const [],
          templates: const [],
        ),
      );
      fail('expected invalid_data:');
    } catch (error) {
      expect(error.toString(), startsWith('invalid_data:'));
      expect(
        ImagePipelineException.tryParseRustError(error)?.kind,
        ImagePipelineFailureKind.invalidData,
      );
    }
  });

  test('export embeds a watermarked photo under photos/', () async {
    final root = await Directory.systemTemp.createTemp(
      'sitemark-degraded-zip-photo-',
    );
    addTearDown(() => root.delete(recursive: true));

    final source = img.Image(width: 16, height: 12);
    img.fill(source, color: img.ColorRgb8(10, 20, 30));
    final photoPath = '${root.path}${Platform.pathSeparator}001.jpg';
    await File(photoPath).writeAsBytes(img.encodeJpg(source));
    final outputZipPath = '${root.path}${Platform.pathSeparator}out.zip';

    final result = await const DegradedImagePipeline().export(
      rust.ExportProjectRequest(
        projectId: 'p1',
        projectName: 'Demo',
        projectCreatedAt: '2026-01-01T00:00:00Z',
        snapshotAt: '2026-01-02T00:00:00Z',
        omittedProcessingCount: 0,
        omittedFailedCount: 0,
        outputZipPath: outputZipPath,
        includeOriginals: false,
        projectLifecycleStatus: 'active',
        projectIsPinned: false,
        watermark: _watermark,
        photos: [
          rust.ExportPhotoRecord(
            photoNumber: '001',
            watermarkedPath: photoPath,
            originalSha256: 'abc',
            capturedAt: '2026-01-01T00:00:00Z',
            workLocation: 'loc',
            workContent: 'work',
            photographer: 'cam',
          ),
        ],
        templates: const [],
      ),
    );

    expect(result.photoCount, 1);
    final archive = ZipDecoder().decodeBytes(
      await File(outputZipPath).readAsBytes(),
    );
    expect(archive.findFile('photos/001.jpg'), isNotNull);
  });

  test('exportSelection rejects an empty project list', () async {
    try {
      await const DegradedImagePipeline().exportSelection(
        const rust.ExportSelectionRequest(
          outputZipPath: '/tmp/sel.zip',
          includeOriginals: false,
          projects: [],
        ),
      );
      fail('expected invalid_data:');
    } catch (error) {
      expect(error.toString(), startsWith('invalid_data:'));
    }
  });

  test('exportBundle wraps project zips with bundle.json', () async {
    final root = await Directory.systemTemp.createTemp(
      'sitemark-degraded-bundle-',
    );
    addTearDown(() => root.delete(recursive: true));
    final innerZip = File('${root.path}${Platform.pathSeparator}inner.zip');
    await innerZip.writeAsBytes([
      0x50,
      0x4b,
      0x05,
      0x06,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
    ]);
    final outputZipPath = '${root.path}${Platform.pathSeparator}bundle.zip';

    final result = await const DegradedProjectBundlePipeline().exportBundle(
      rust.ExportProjectBundleRequest(
        outputZipPath: outputZipPath,
        projects: [
          rust.ProjectBundleSource(
            projectId: 'p1',
            projectName: 'Demo',
            archivePath: innerZip.path,
          ),
        ],
      ),
    );

    expect(result.photoCount, 1);
    final archive = ZipDecoder().decodeBytes(
      await File(outputZipPath).readAsBytes(),
    );
    final bundle =
        jsonDecode(
              utf8.decode(archive.findFile('bundle.json')!.content as List<int>),
            )
            as Map<String, dynamic>;
    expect(bundle['kind'], 'sitemark-project-bundle');
    expect(bundle['schema_version'], 1);
    expect(archive.findFile('projects/p1.zip'), isNotNull);
  });

  test('readProjectArchive reads a schema 5 zip written by export', () async {
    final root = await Directory.systemTemp.createTemp(
      'sitemark-degraded-restore-',
    );
    addTearDown(() => root.delete(recursive: true));
    final outputZipPath = '${root.path}${Platform.pathSeparator}out.zip';
    const pipeline = DegradedImagePipeline();
    await pipeline.export(
      rust.ExportProjectRequest(
        projectId: 'p',
        projectName: 'n',
        projectCreatedAt: '2026-01-01T00:00:00Z',
        snapshotAt: '2026-01-01T00:00:00Z',
        omittedProcessingCount: 0,
        omittedFailedCount: 0,
        outputZipPath: outputZipPath,
        includeOriginals: false,
        projectLifecycleStatus: 'active',
        projectIsPinned: false,
        watermark: _watermark,
        photos: const [],
        templates: const [],
      ),
    );

    final preview = await pipeline.readProjectArchive(outputZipPath);
    expect(preview.schemaVersion, 5);
    expect(preview.projectName, 'n');
    expect(preview.photos, isEmpty);
    expect(preview.projectLifecycleStatus, 'active');
    expect(preview.projectIsPinned, isFalse);
    expect(preview.includesOriginals, isFalse);
    expect(preview.isPartial, isFalse);
  });

  test('readProjectArchive rejects a multi-project selection zip', () async {
    final root = await Directory.systemTemp.createTemp(
      'sitemark-degraded-restore-sel-',
    );
    addTearDown(() => root.delete(recursive: true));
    final source = img.Image(width: 8, height: 8);
    img.fill(source, color: img.ColorRgb8(1, 2, 3));
    final photoPath = '${root.path}${Platform.pathSeparator}001.jpg';
    await File(photoPath).writeAsBytes(img.encodeJpg(source));
    final outputZipPath = '${root.path}${Platform.pathSeparator}sel.zip';
    await const DegradedImagePipeline().exportSelection(
      rust.ExportSelectionRequest(
        outputZipPath: outputZipPath,
        includeOriginals: false,
        projects: [
          rust.ExportSelectionProject(
            projectId: 'p1',
            projectName: 'A',
            photos: [
              rust.ExportPhotoRecord(
                photoNumber: '001',
                watermarkedPath: photoPath,
                originalSha256: 'abc',
                capturedAt: '2026-01-01T00:00:00Z',
                workLocation: 'loc',
                workContent: 'work',
                photographer: 'cam',
              ),
            ],
          ),
        ],
      ),
    );

    try {
      await const DegradedImagePipeline().readProjectArchive(outputZipPath);
      fail('expected invalid_data:');
    } catch (error) {
      expect(error.toString(), startsWith('invalid_data:'));
      expect(
        error.toString(),
        contains('Only single-project archives are restorable'),
      );
    }
  });

  test('extractArchivePhoto writes the rendered jpeg', () async {
    final root = await Directory.systemTemp.createTemp(
      'sitemark-degraded-extract-',
    );
    addTearDown(() => root.delete(recursive: true));
    final source = img.Image(width: 16, height: 12);
    img.fill(source, color: img.ColorRgb8(10, 20, 30));
    final jpegBytes = img.encodeJpg(source);
    final photoPath = '${root.path}${Platform.pathSeparator}001.jpg';
    await File(photoPath).writeAsBytes(jpegBytes);
    final outputZipPath = '${root.path}${Platform.pathSeparator}out.zip';
    const pipeline = DegradedImagePipeline();
    await pipeline.export(
      rust.ExportProjectRequest(
        projectId: 'p1',
        projectName: 'Demo',
        projectCreatedAt: '2026-01-01T00:00:00Z',
        snapshotAt: '2026-01-02T00:00:00Z',
        omittedProcessingCount: 0,
        omittedFailedCount: 0,
        outputZipPath: outputZipPath,
        includeOriginals: false,
        projectLifecycleStatus: 'active',
        projectIsPinned: false,
        watermark: _watermark,
        photos: [
          rust.ExportPhotoRecord(
            photoNumber: '001',
            watermarkedPath: photoPath,
            originalSha256: 'abc',
            capturedAt: '2026-01-01T00:00:00Z',
            workLocation: 'loc',
            workContent: 'work',
            photographer: 'cam',
          ),
        ],
        templates: const [],
      ),
    );

    final dest = '${root.path}${Platform.pathSeparator}restored.jpg';
    final extracted = await pipeline.extractArchivePhoto(
      rust.ExtractArchivePhotoRequest(
        zipPath: outputZipPath,
        photoNumber: '001',
        renderedDestination: dest,
      ),
    );
    expect(extracted.renderedPath, dest);
    expect(extracted.originalPath, isNull);
    expect(await File(dest).readAsBytes(), jpegBytes);
  });

  test('readBundle and extractBundleEntry restore an inner project zip', () async {
    final root = await Directory.systemTemp.createTemp(
      'sitemark-degraded-restore-bundle-',
    );
    addTearDown(() => root.delete(recursive: true));
    const pipeline = DegradedImagePipeline();
    final innerZipPath = '${root.path}${Platform.pathSeparator}inner.zip';
    await pipeline.export(
      rust.ExportProjectRequest(
        projectId: 'p1',
        projectName: 'Demo',
        projectCreatedAt: '2026-01-01T00:00:00Z',
        snapshotAt: '2026-01-01T00:00:00Z',
        omittedProcessingCount: 0,
        omittedFailedCount: 0,
        outputZipPath: innerZipPath,
        includeOriginals: false,
        projectLifecycleStatus: 'active',
        projectIsPinned: false,
        watermark: _watermark,
        photos: const [],
        templates: const [],
      ),
    );
    final bundleZipPath = '${root.path}${Platform.pathSeparator}bundle.zip';
    const bundle = DegradedProjectBundlePipeline();
    await bundle.exportBundle(
      rust.ExportProjectBundleRequest(
        outputZipPath: bundleZipPath,
        projects: [
          rust.ProjectBundleSource(
            projectId: 'p1',
            projectName: 'Demo',
            archivePath: innerZipPath,
          ),
        ],
      ),
    );

    final preview = await bundle.readBundle(bundleZipPath);
    expect(preview.schemaVersion, 1);
    expect(preview.projects, hasLength(1));
    expect(preview.projects.single.projectId, 'p1');
    expect(preview.projects.single.archivePath, 'projects/p1.zip');

    final extractedPath = '${root.path}${Platform.pathSeparator}extracted.zip';
    await bundle.extractBundleEntry(
      rust.ExtractProjectBundleEntryRequest(
        zipPath: bundleZipPath,
        archivePath: 'projects/p1.zip',
        outputPath: extractedPath,
      ),
    );
    final innerPreview = await pipeline.readProjectArchive(extractedPath);
    expect(innerPreview.projectName, 'Demo');
    expect(innerPreview.schemaVersion, 5);
  });

  test('readProjectArchive rejects a missing zip with not_found:', () async {
    try {
      await const DegradedImagePipeline().readProjectArchive(
        '${Directory.systemTemp.path}${Platform.pathSeparator}missing-sitemark.zip',
      );
      fail('expected not_found:');
    } catch (error) {
      expect(error.toString(), startsWith('not_found:'));
      expect(
        ImagePipelineException.tryParseRustError(error)?.kind,
        ImagePipelineFailureKind.notFound,
      );
    }
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
