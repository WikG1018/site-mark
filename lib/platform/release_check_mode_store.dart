import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sitemark/domain/release_check.dart';

const releaseCheckModeFileName = 'release_check_mode.txt';

abstract interface class ReleaseCheckModeStore {
  Future<ReleaseCheckMode> read();
  Future<void> write(ReleaseCheckMode mode);
}

/// Remembers auto / official / mirror in the app-private support directory.
/// A missing or unreadable file is Automatic. This is not a database column.
class FileReleaseCheckModeStore implements ReleaseCheckModeStore {
  FileReleaseCheckModeStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  Future<File> _file() async {
    final dir = await _directory();
    return File(
      '${dir.path}${Platform.pathSeparator}$releaseCheckModeFileName',
    );
  }

  @override
  Future<ReleaseCheckMode> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return ReleaseCheckMode.auto;
      return parseReleaseCheckMode(await file.readAsString());
    } catch (_) {
      return ReleaseCheckMode.auto;
    }
  }

  @override
  Future<void> write(ReleaseCheckMode mode) async {
    final file = await _file();
    await file.writeAsString(serializeReleaseCheckMode(mode), flush: true);
  }
}

class MemoryReleaseCheckModeStore implements ReleaseCheckModeStore {
  MemoryReleaseCheckModeStore([this.mode = ReleaseCheckMode.auto]);

  ReleaseCheckMode mode;

  @override
  Future<ReleaseCheckMode> read() async => mode;

  @override
  Future<void> write(ReleaseCheckMode mode) async {
    this.mode = mode;
  }
}
