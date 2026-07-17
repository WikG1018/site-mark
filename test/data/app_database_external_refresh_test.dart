import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_filter.dart';
import 'package:sitemark/domain/capture_status.dart';

void main() {
  const digest =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  late Directory directory;
  late AppDatabase foreground;
  late AppDatabase background;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sitemark-refresh-');
    final file = File(
      '${directory.path}${Platform.pathSeparator}sitemark.sqlite',
    );
    foreground = AppDatabase.forTesting(
      NativeDatabase(file),
      externalRefreshInterval: const Duration(milliseconds: 10),
    );
    await foreground.createProject(id: 'project-1', name: '东区厂房改造');
    final pending = await foreground.createPendingCapture(
      id: 'capture-1',
      projectId: 'project-1',
      originalPath: '/private/capture-1.jpg',
      workLocation: 'A 区',
      workContent: '风管检查',
      photographer: '张工',
      watermarkLocaleCode: 'zh',
    );
    await foreground.markCaptured(
      captureId: pending.id,
      capturedAt: DateTime(2026, 7, 17, 9, 30),
    );
    background = AppDatabase.forTesting(NativeDatabase(file));
    await background.customSelect('SELECT 1').get();
  });

  tearDown(() async {
    await background.close();
    await foreground.close();
    await directory.delete(recursive: true);
  });

  test(
    'detail and summary watchers observe an external ready update',
    () async {
      final detail = StreamIterator(foreground.watchCaptureById('capture-1'));
      final filtered = StreamIterator(
        foreground.watchCaptureSummaries(const CaptureFilter()),
      );
      final all = StreamIterator(foreground.watchAllCaptureSummaries());

      expect(await detail.moveNext(), isTrue);
      expect(detail.current?.status, CaptureStatus.captured);
      expect(await filtered.moveNext(), isTrue);
      expect(filtered.current.single.capture.status, CaptureStatus.captured);
      expect(await all.moveNext(), isTrue);
      expect(all.current.single.capture.status, CaptureStatus.captured);

      await background.markRendering(
        captureId: 'capture-1',
        originalSha256: digest,
      );
      await background.markReady(
        captureId: 'capture-1',
        publishedUri: 'content://media/site-mark/1',
      );

      final readyDetail = await _nextMatching(
        detail,
        (record) => record?.status == CaptureStatus.ready,
      );
      final readyFiltered = await _nextMatching(
        filtered,
        (rows) => rows.single.capture.status == CaptureStatus.ready,
      );
      final readyAll = await _nextMatching(
        all,
        (rows) => rows.single.capture.status == CaptureStatus.ready,
      );

      expect(readyDetail?.publishedUri, 'content://media/site-mark/1');
      expect(readyFiltered.single.projectName, '东区厂房改造');
      expect(
        readyAll.single.capture.publishedUri,
        'content://media/site-mark/1',
      );
      await detail.cancel();
      await filtered.cancel();
      await all.cancel();
    },
  );
}

Future<T> _nextMatching<T>(
  StreamIterator<T> iterator,
  bool Function(T value) predicate,
) async {
  while (await iterator.moveNext().timeout(const Duration(seconds: 1))) {
    if (predicate(iterator.current)) return iterator.current;
  }
  throw StateError('Stream closed before the expected value');
}
