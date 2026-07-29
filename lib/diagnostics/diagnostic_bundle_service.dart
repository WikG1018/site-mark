import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sitemark/diagnostics/diagnostic_event_store.dart';

class DiagnosticBundleService {
  const DiagnosticBundleService({
    required this.store,
    this.supportDirectory,
    this.packageInfo,
  });

  final DiagnosticEventStore store;
  final Future<Directory> Function()? supportDirectory;
  final Future<PackageInfo> Function()? packageInfo;

  Future<String> generate() async {
    final root = await (supportDirectory ?? getApplicationSupportDirectory)();
    final outputDirectory = Directory(
      '${root.path}${Platform.pathSeparator}diagnostics',
    );
    await outputDirectory.create(recursive: true);
    final info = await (packageInfo ?? PackageInfo.fromPlatform)();
    final events = await store.readRecent();
    final generatedAt = DateTime.now().toUtc().toIso8601String();
    final environment = jsonEncode({
      'app_version': info.version,
      'build_number': info.buildNumber,
      'operating_system': Platform.operatingSystem,
      'operating_system_version': Platform.operatingSystemVersion,
      'locale': Platform.localeName,
    });
    final eventText = events.map((event) => event.encode()).join('\n');
    final summary =
        'SiteMark 诊断包\n'
        '生成时间：$generatedAt\n'
        '事件数量：${events.length}\n'
        '隐私：不包含照片、项目名称、工程内容、人员、位置、文件路径或原始异常。\n';
    final manifest = jsonEncode({
      'schema_version': 1,
      'generated_at': generatedAt,
      'retention_days': 7,
      'max_event_bytes': 2 * 1024 * 1024,
    });
    final archive = Archive()
      ..addFile(ArchiveFile.string('summary.txt', summary))
      ..addFile(ArchiveFile.string('environment.json', environment))
      ..addFile(ArchiveFile.string('events.jsonl', eventText))
      ..addFile(ArchiveFile.string('manifest.json', manifest));
    final path =
        '${outputDirectory.path}${Platform.pathSeparator}sitemark-diagnostics.zip';
    final bytes = ZipEncoder().encode(archive);
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }
}
