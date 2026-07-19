import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/app_storage_usage.dart';
import 'package:sitemark/workflow/app_storage_service.dart';

void main() {
  late Directory temporaryRoot;
  late Directory documents;
  late AppDatabase database;

  setUp(() async {
    temporaryRoot = await Directory.systemTemp.createTemp('sitemark-storage-');
    documents = await Directory(
      '${temporaryRoot.path}${Platform.pathSeparator}documents',
    ).create();
    database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.createProject(id: 'project', name: '工程记录');
  });

  tearDown(() async {
    await database.close();
    await temporaryRoot.delete(recursive: true);
  });

  Future<File> writeFile(String path, int length) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(List<int>.filled(length, 1));
    return file;
  }

  test('loads deduplicated app-private storage categories', () async {
    final original = await writeFile(
      '${temporaryRoot.path}${Platform.pathSeparator}original.jpg',
      11,
    );
    for (final id in ['capture-a', 'capture-b']) {
      await database.createPendingCapture(
        id: id,
        projectId: 'project',
        originalPath: original.path,
        workLocation: 'A 区',
        workContent: '检查',
        photographer: '张工',
        watermarkLocaleCode: 'zh',
      );
    }
    await writeFile(
      '${documents.path}${Platform.pathSeparator}rendered'
      '${Platform.pathSeparator}capture-a.jpg',
      13,
    );
    await writeFile(
      '${documents.path}${Platform.pathSeparator}exports'
      '${Platform.pathSeparator}project.zip',
      17,
    );
    await writeFile(
      '${documents.path}${Platform.pathSeparator}sitemark.sqlite',
      19,
    );
    await writeFile('${documents.path}${Platform.pathSeparator}other.bin', 23);

    final usage = await AppStorageUsageService(
      database: database,
      documentsDirectory: () async => documents,
    ).load();

    expect(usage.originalBytes, 11);
    expect(usage.renderedBytes, 13);
    expect(usage.exportBytes, 17);
    expect(usage.databaseAndOtherBytes, 42);
    expect(usage.totalBytes, 83);
  });

  test(
    'clearExports deletes only ZIP files under the private export folder',
    () async {
      final first = await writeFile(
        '${documents.path}${Platform.pathSeparator}exports'
        '${Platform.pathSeparator}first.zip',
        17,
      );
      final second = await writeFile(
        '${documents.path}${Platform.pathSeparator}exports'
        '${Platform.pathSeparator}nested${Platform.pathSeparator}second.ZIP',
        7,
      );
      final keep = await writeFile(
        '${documents.path}${Platform.pathSeparator}exports'
        '${Platform.pathSeparator}keep.txt',
        5,
      );
      final rendered = await writeFile(
        '${documents.path}${Platform.pathSeparator}rendered'
        '${Platform.pathSeparator}capture.jpg',
        13,
      );

      final result = await AppStorageUsageService(
        database: database,
        documentsDirectory: () async => documents,
      ).clearExports();

      expect(result.deletedFiles, 2);
      expect(result.freedBytes, 24);
      expect(await first.exists(), isFalse);
      expect(await second.exists(), isFalse);
      expect(await keep.exists(), isTrue);
      expect(await rendered.exists(), isTrue);
    },
  );

  test('formats storage bytes for settings display', () {
    expect(formatStorageBytes(0), '0 B');
    expect(formatStorageBytes(1024), '1 KB');
    expect(formatStorageBytes(1536), '1.5 KB');
    expect(formatStorageBytes(10 * 1024 * 1024), '10 MB');
  });
}
