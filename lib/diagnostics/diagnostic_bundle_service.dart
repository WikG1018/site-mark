import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sitemark/diagnostics/diagnostic_event_store.dart';
import 'package:sitemark/l10n/app_strings.dart';

class DiagnosticBundleService {
  const DiagnosticBundleService({
    required this.store,
    this.supportDirectory,
    this.packageInfo,
  });

  final DiagnosticEventStore store;
  final Future<Directory> Function()? supportDirectory;
  final Future<PackageInfo> Function()? packageInfo;

  /// [droppedEventCount] records diagnostic events that failed to persist
  /// (see `DiagnosticRecorder.droppedCount`); callers pass it so a broken
  /// store is visible in shared bundles instead of silently missing events.
  Future<String> generate({int? droppedEventCount}) async {
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
    final english = AppStrings(const Locale('en')).diagnosticBundleSummary(
      generatedAt: generatedAt,
      eventCount: events.length,
    );
    final chinese = AppStrings(const Locale('zh')).diagnosticBundleSummary(
      generatedAt: generatedAt,
      eventCount: events.length,
    );
    final summary = '$english\n$chinese';
    final manifest = jsonEncode({
      'schema_version': 1,
      'generated_at': generatedAt,
      'retention_days': 7,
      'max_event_bytes': 2 * 1024 * 1024,
      'dropped_event_count': droppedEventCount ?? 0,
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
