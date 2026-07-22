import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/app_storage_usage.dart';

abstract interface class StorageUsageService {
  Future<AppStorageUsage> load();

  Future<ClearExportsResult> clearExports();
}

typedef DocumentsDirectoryLoader = Future<Directory> Function();
typedef FileLengthLoader = Future<int> Function(File file);

const _maximumConcurrentFileLengths = 8;

Future<int> _safeFileLength(File file) async {
  try {
    return await file.length();
  } on FileSystemException {
    return 0;
  }
}

enum _StorageCategory { original, rendered, export, other }

class _CategorizedFile {
  const _CategorizedFile(this.file, this.category);

  final File file;
  final _StorageCategory category;
}

class _StorageTotals {
  const _StorageTotals({
    this.originalBytes = 0,
    this.renderedBytes = 0,
    this.exportBytes = 0,
    this.databaseAndOtherBytes = 0,
  });

  final int originalBytes;
  final int renderedBytes;
  final int exportBytes;
  final int databaseAndOtherBytes;

  _StorageTotals add(_StorageTotals other) {
    return _StorageTotals(
      originalBytes: originalBytes + other.originalBytes,
      renderedBytes: renderedBytes + other.renderedBytes,
      exportBytes: exportBytes + other.exportBytes,
      databaseAndOtherBytes:
          databaseAndOtherBytes + other.databaseAndOtherBytes,
    );
  }
}

class AppStorageUsageService implements StorageUsageService {
  AppStorageUsageService({
    required this.database,
    this.documentsDirectory = getApplicationDocumentsDirectory,
    FileLengthLoader? fileLength,
  }) : fileLength = fileLength ?? _safeFileLength;

  final AppDatabase database;
  final DocumentsDirectoryLoader documentsDirectory;
  final FileLengthLoader fileLength;

  @override
  Future<AppStorageUsage> load() async {
    final documents = await documentsDirectory();
    final renderedDirectory = Directory(
      '${documents.path}${Platform.pathSeparator}rendered',
    );
    final exportDirectory = Directory(
      '${documents.path}${Platform.pathSeparator}exports',
    );

    final originals = <String, File>{};
    for (final capture in await database.getAllCaptures()) {
      final file = File(capture.originalPath);
      originals.putIfAbsent(_pathKey(file.path), () => file);
    }

    final files = <_CategorizedFile>[
      for (final file in originals.values)
        _CategorizedFile(file, _StorageCategory.original),
    ];
    final renderedKey = _pathKey(renderedDirectory.path);
    final exportKey = _pathKey(exportDirectory.path);
    if (await documents.exists()) {
      await for (final entity in documents.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final key = _pathKey(entity.path);
        if (originals.containsKey(key)) {
          continue;
        }
        if (_inside(key, renderedKey)) {
          files.add(_CategorizedFile(entity, _StorageCategory.rendered));
        } else if (_inside(key, exportKey)) {
          files.add(_CategorizedFile(entity, _StorageCategory.export));
        } else {
          files.add(_CategorizedFile(entity, _StorageCategory.other));
        }
      }
    }

    final totals = await _loadFileLengths(files);

    return AppStorageUsage(
      originalBytes: totals.originalBytes,
      renderedBytes: totals.renderedBytes,
      exportBytes: totals.exportBytes,
      databaseAndOtherBytes: totals.databaseAndOtherBytes,
    );
  }

  @override
  Future<ClearExportsResult> clearExports() async {
    final documents = await documentsDirectory();
    final directory = Directory(
      '${documents.path}${Platform.pathSeparator}exports',
    );
    if (!await directory.exists()) {
      return const ClearExportsResult(deletedFiles: 0, freedBytes: 0);
    }

    var deletedFiles = 0;
    var freedBytes = 0;
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.zip')) {
        continue;
      }
      freedBytes += await fileLength(entity);
      await entity.delete();
      deletedFiles++;
    }
    return ClearExportsResult(
      deletedFiles: deletedFiles,
      freedBytes: freedBytes,
    );
  }

  Future<_StorageTotals> _loadFileLengths(List<_CategorizedFile> files) async {
    if (files.isEmpty) return const _StorageTotals();

    var nextIndex = 0;
    final workerCount = files.length < _maximumConcurrentFileLengths
        ? files.length
        : _maximumConcurrentFileLengths;
    final workerTotals = await Future.wait(
      List.generate(workerCount, (_) async {
        var originals = 0;
        var rendered = 0;
        var exports = 0;
        var other = 0;
        while (nextIndex < files.length) {
          final file = files[nextIndex++];
          final length = await fileLength(file.file);
          switch (file.category) {
            case _StorageCategory.original:
              originals += length;
            case _StorageCategory.rendered:
              rendered += length;
            case _StorageCategory.export:
              exports += length;
            case _StorageCategory.other:
              other += length;
          }
        }
        return _StorageTotals(
          originalBytes: originals,
          renderedBytes: rendered,
          exportBytes: exports,
          databaseAndOtherBytes: other,
        );
      }),
    );

    return workerTotals.fold<_StorageTotals>(
      const _StorageTotals(),
      (total, worker) => total.add(worker),
    );
  }

  bool _inside(String path, String directory) {
    return path == directory || path.startsWith('$directory/');
  }

  String _pathKey(String path) {
    final normalized = File(path).absolute.path.replaceAll('\\', '/');
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }
}
