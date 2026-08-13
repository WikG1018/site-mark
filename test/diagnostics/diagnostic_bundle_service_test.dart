import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sitemark/diagnostics/diagnostic_bundle_service.dart';
import 'package:sitemark/diagnostics/diagnostic_event.dart';
import 'package:sitemark/diagnostics/diagnostic_event_store.dart';
import 'package:sitemark/l10n/app_strings.dart';

void main() {
  test('summary.txt is bilingual and omits private content', () async {
    final root = await Directory.systemTemp.createTemp(
      'sitemark-diag-bundle-test-',
    );
    addTearDown(() => root.delete(recursive: true));
    final now = DateTime.utc(2026, 8, 13, 12);
    final store = DiagnosticEventStore(directory: root, clock: () => now);
    await store.append(
      DiagnosticEvent(
        timestamp: now,
        category: DiagnosticCategory.backup,
        outcome: DiagnosticOutcome.success,
        count: 2,
      ),
    );
    final service = DiagnosticBundleService(
      store: store,
      supportDirectory: () async => root,
      packageInfo: () async => PackageInfo(
        appName: 'SiteMark',
        packageName: 'io.github.wikg1018.sitemark',
        version: '1.0.6',
        buildNumber: '21',
      ),
    );

    final path = await service.generate();
    final archive = ZipDecoder().decodeBytes(await File(path).readAsBytes());
    final summaryFile = archive.findFile('summary.txt');
    expect(summaryFile, isNotNull);
    final summary = utf8.decode(summaryFile!.content as List<int>);
    final generatedAtMatch = RegExp(
      r'Generated at: (.+)\n',
    ).firstMatch(summary);
    expect(generatedAtMatch, isNotNull);
    final generatedAt = generatedAtMatch!.group(1)!;
    expect(
      summary,
      contains(
        AppStrings(
          const Locale('en'),
        ).diagnosticBundleSummary(generatedAt: generatedAt, eventCount: 1),
      ),
    );
    expect(
      summary,
      contains(
        AppStrings(
          const Locale('zh'),
        ).diagnosticBundleSummary(generatedAt: generatedAt, eventCount: 1),
      ),
    );
    expect(summary, isNot(contains('照片路径')));
    expect(summary, isNot(contains('/storage/')));
    expect(summary, isNot(contains('/data/')));
    expect(summary, isNot(contains('FileSystemException')));
    expect(summary, isNot(contains('东区厂房')));
    expect(summary, isNot(contains('张工')));
  });
}
