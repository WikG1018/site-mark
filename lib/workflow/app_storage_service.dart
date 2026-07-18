import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/app_storage_usage.dart';

abstract interface class StorageUsageService {
  Future<AppStorageUsage> load();

  Future<ClearExportsResult> clearExports();
}

typedef DocumentsDirectoryLoader = Future<Directory> Function();

class AppStorageUsageService implements StorageUsageService {
  AppStorageUsageService({
    required this.database,
    this.documentsDirectory = getApplicationDocumentsDirectory,
  });

  final AppDatabase database;
  final DocumentsDirectoryLoader documentsDirectory;

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

    var originalBytes = 0;
    for (final file in originals.values) {
      originalBytes += await _fileLength(file);
    }

    var renderedBytes = 0;
    var exportBytes = 0;
    var databaseAndOtherBytes = 0;
    final renderedKey = _pathKey(renderedDirectory.path);
    final exportKey = _pathKey(exportDirectory.path);
    if (await documents.exists()) {
      await for (final entity in documents.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final key = _pathKey(entity.path);
        final length = await _fileLength(entity);
        if (_inside(key, renderedKey)) {
          renderedBytes += length;
        } else if (_inside(key, exportKey)) {
          exportBytes += length;
        } else if (!originals.containsKey(key)) {
          databaseAndOtherBytes += length;
        }
      }
    }

    return AppStorageUsage(
      originalBytes: originalBytes,
      renderedBytes: renderedBytes,
      exportBytes: exportBytes,
      databaseAndOtherBytes: databaseAndOtherBytes,
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
      freedBytes += await _fileLength(entity);
      await entity.delete();
      deletedFiles++;
    }
    return ClearExportsResult(
      deletedFiles: deletedFiles,
      freedBytes: freedBytes,
    );
  }

  Future<int> _fileLength(File file) async {
    try {
      return await file.length();
    } on FileSystemException {
      return 0;
    }
  }

  bool _inside(String path, String directory) {
    return path == directory || path.startsWith('$directory/');
  }

  String _pathKey(String path) {
    final normalized = File(path).absolute.path.replaceAll('\\', '/');
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }
}
