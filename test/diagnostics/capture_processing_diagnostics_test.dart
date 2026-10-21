import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/diagnostics/capture_processing_diagnostics.dart';
import 'package:sitemark/diagnostics/diagnostic_event.dart';
import 'package:sitemark/diagnostics/diagnostic_event_store.dart';
import 'package:sitemark/diagnostics/diagnostic_recorder.dart';
import 'package:sitemark/platform/platform_services.dart';

void main() {
  late Directory root;
  late DiagnosticEventStore store;
  late CaptureProcessingDiagnostics diagnostics;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('capture-diagnostics-');
    store = captureProcessingDiagnosticStore(root);
    diagnostics = CaptureProcessingDiagnostics(DiagnosticRecorder(store));
  });
  tearDown(() => root.delete(recursive: true));

  test('records empty original without leaking paths or error text', () async {
    final original = File('${root.path}/private-project-person.jpg');
    await original.writeAsBytes([]);
    await diagnostics.failed(
      stage: DiagnosticStage.rendering,
      error: const ImagePipelineException(
        ImagePipelineFailureKind.invalidData,
        'unable to detect image format: private-project-person /data/private',
      ),
      sourcePath: original.path,
      attempts: 1,
    );
    final events = await store.readRecent();
    final event = events.single;
    expect(event.stage, DiagnosticStage.rendering);
    expect(event.code, DiagnosticCode.unsupportedImageFormat);
    expect(event.sourceFormat, DiagnosticImageFormat.empty);
    expect(event.sourceSizeBytes, 0);
    expect(event.retryCount, 0);
    expect(event.encode(), isNot(contains('private-project-person')));
    expect(event.encode(), isNot(contains('/data/private')));
    expect(event.encode(), isNot(contains(root.path)));
    expect(DiagnosticEvent.tryDecode(event.encode())?.toJson(), event.toJson());
  });

  test('detects HEIF bytes despite a jpg file extension', () async {
    final original = File('${root.path}/original.jpg');
    await original.writeAsBytes([0, 0, 0, 24, ...ascii.encode('ftypheic')]);
    await diagnostics.failed(
      stage: DiagnosticStage.rendering,
      error: const ImagePipelineException(
        ImagePipelineFailureKind.invalidData,
        'unsupported image format',
      ),
      sourcePath: original.path,
      attempts: 3,
    );
    final event = (await store.readRecent()).single;
    expect(event.sourceFormat, DiagnosticImageFormat.heif);
    expect(event.sourceSizeBytes, 12);
    expect(event.retryCount, 2);
  });

  test(
    'recognizes JPEG, size limits, missing files and platform failures',
    () async {
      final original = File('${root.path}/original.jpg');
      await original.writeAsBytes([0xff, 0xd8, 0xff, 0xe1]);
      await diagnostics.failed(
        stage: DiagnosticStage.rendering,
        error: const ImagePipelineException(
          ImagePipelineFailureKind.invalidData,
          'image exceeds the 64 megapixel limit',
        ),
        sourcePath: original.path,
      );
      await diagnostics.failed(
        stage: DiagnosticStage.originalHash,
        error: PathNotFoundException(original.path, const OSError('gone', 2)),
        sourcePath: '${root.path}/missing.jpg',
      );
      await diagnostics.failed(
        stage: DiagnosticStage.publishing,
        error: PlatformException(code: 'private-code', message: 'private-text'),
      );
      final events = await store.readRecent();
      expect(events[0].sourceFormat, DiagnosticImageFormat.jpeg);
      expect(events[0].code, DiagnosticCode.imageTooLarge);
      expect(events[1].sourceFormat, DiagnosticImageFormat.missing);
      expect(events[1].code, DiagnosticCode.originalMissing);
      expect(events[2].code, DiagnosticCode.platformUnavailable);
      expect(events[2].encode(), isNot(contains('private-')));
    },
  );

  test('diagnostic write failure cannot escape the processing path', () async {
    final blocker = File('${root.path}/blocker');
    await blocker.writeAsString('not a directory');
    final recorder = DiagnosticRecorder(
      DiagnosticEventStore(directory: Directory('${blocker.path}/events')),
    );
    await CaptureProcessingDiagnostics(recorder).failed(
      stage: DiagnosticStage.worker,
      error: StateError('private exception'),
    );
    expect(recorder.droppedCount, 1);
  });
}
