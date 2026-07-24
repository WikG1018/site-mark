import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/platform/capture_form_draft_store.dart';

/// Tests for [FileCaptureFormDraftStore], the production implementation
/// that persists MEMORY_KILL draft snapshots to the filesystem. These
/// tests mock `path_provider` so the store writes to a temp directory.
void main() {
  late Directory tempDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('draft_store_test_');
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return tempDir.path;
        }
        return null;
      },
    );
  });

  tearDown(() async {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('FileCaptureFormDraftStore', () {
    test('save then load returns the persisted snapshot', () async {
      final store = FileCaptureFormDraftStore();
      const snapshot = CaptureFormDraftSnapshot(
        projectId: 'proj-123',
        workLocation: 'Site A',
        workContent: 'Foundation work',
        photographer: 'Alice',
        notes: 'Weather: sunny',
      );

      await store.save(snapshot);
      final loaded = await store.load('proj-123');

      expect(loaded, isNotNull);
      expect(loaded!.projectId, 'proj-123');
      expect(loaded.workLocation, 'Site A');
      expect(loaded.workContent, 'Foundation work');
      expect(loaded.photographer, 'Alice');
      expect(loaded.notes, 'Weather: sunny');
    });

    test('clear removes the persisted snapshot', () async {
      final store = FileCaptureFormDraftStore();
      const snapshot = CaptureFormDraftSnapshot(
        projectId: 'proj-456',
        workLocation: 'Site B',
        workContent: 'Roofing',
        photographer: 'Bob',
        notes: '',
      );

      await store.save(snapshot);
      expect(await store.load('proj-456'), isNotNull);

      await store.clear('proj-456');
      expect(await store.load('proj-456'), isNull);
    });

    test('load returns null when no snapshot exists', () async {
      final store = FileCaptureFormDraftStore();
      expect(await store.load('nonexistent-id'), isNull);
    });

    test('path separators in projectId are sanitized to prevent directory traversal', () async {
      final store = FileCaptureFormDraftStore();
      const snapshot = CaptureFormDraftSnapshot(
        projectId: 'a/b',
        workLocation: 'Loc1',
        workContent: 'Content1',
        photographer: 'P1',
        notes: 'N1',
      );

      await store.save(snapshot);

      // Loading with the original key works.
      final loaded = await store.load('a/b');
      expect(loaded, isNotNull);
      expect(loaded!.workLocation, 'Loc1');

      // The file is written directly under the docs directory with
      // separators replaced — no subdirectory is created.
      final files = tempDir.listSync().whereType<File>().map((f) => f.path).toList();
      expect(files.length, 1);
      expect(files.first, contains('kill_form_draft_a_b.json'));
    });

    test('corrupt file content returns null instead of throwing', () async {
      final store = FileCaptureFormDraftStore();
      const snapshot = CaptureFormDraftSnapshot(
        projectId: 'corrupt-test',
        workLocation: 'Loc',
        workContent: 'Content',
        photographer: 'P',
        notes: 'N',
      );

      await store.save(snapshot);

      // Overwrite the file with invalid JSON to simulate a partial write
      // (e.g. process killed mid-write during MEMORY_KILL).
      final file = File('${tempDir.path}/kill_form_draft_corrupt-test.json');
      await file.writeAsString('{ this is not valid json');

      // load must not throw; it returns null so the form falls back to
      // the carry-forward draft.
      final loaded = await store.load('corrupt-test');
      expect(loaded, isNull);
    });
  });
}
