import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/domain/release_check.dart';

void main() {
  final digest = 'sha256:${'a' * 64}';
  String body({List<Object?>? assets}) => jsonEncode({
    'tag_name': 'v1.0.32',
    'draft': false,
    'prerelease': false,
    'assets':
        assets ??
        [
          for (final variant in ['arm64', 'universal'])
            {
              'name': 'sitemark-v1.0.32-$variant.apk',
              'size': 42000000,
              'state': 'uploaded',
              'digest': digest,
              // This untrusted field must never decide the download destination.
              'browser_download_url': 'https://untrusted.example/file.apk',
            },
        ],
  });

  ReleaseCheckOutcome outcome(String data) => outcomeFromRead(
    localVersion: '1.0.31',
    read: readFlutterLatest(data),
    source: ReleaseSource.official,
  );

  test('keeps only uploaded assets with exact release names', () {
    final result = outcome(
      body(
        assets: [
          {
            'name': 'sitemark-v1.0.32-arm64.apk',
            'size': 123,
            'state': 'uploaded',
            'digest': digest,
          },
          {
            'name': 'sitemark-v1.0.32-universal.apk',
            'size': 0,
            'state': 'uploaded',
          },
          {
            'name': 'sitemark-v1.0.31-universal.apk',
            'size': 123,
            'state': 'uploaded',
          },
          {
            'name': 'sitemark-v1.0.32-debug.apk',
            'size': 123,
            'state': 'uploaded',
          },
          {
            'name': 'sitemark-v1.0.32-universal.apk',
            'size': 123,
            'state': 'new',
          },
        ],
      ),
    );
    expect(result.downloads.map((asset) => asset.variant), [
      ReleaseApkVariant.arm64,
    ]);
  });

  test('download preserves the installed variant and constructs its own URL', () {
    final result = outcome(body());
    final arm64 = result.downloadForBuild('2046');
    final universal = result.downloadForBuild('46');
    expect(
      arm64?.officialUri.toString(),
      'https://github.com/WikG1018/site-mark/releases/download/v1.0.32/sitemark-v1.0.32-arm64.apk',
    );
    expect(universal?.variant, ReleaseApkVariant.universal);
    expect(arm64?.sizeBytes, 42000000);
    expect(result.downloadForBuild('4046'), isNull);
    expect(result.downloadForBuild('unknown'), isNull);
  });

  test(
    'a missing matching APK never falls back to a lower version-code variant',
    () {
      final result = outcome(
        body(
          assets: [
            {
              'name': 'sitemark-v1.0.32-universal.apk',
              'size': 123,
              'state': 'uploaded',
              'digest': digest,
            },
          ],
        ),
      );
      expect(result.downloadForBuild('2046'), isNull);
      expect(result.downloadForBuild('46'), isNotNull);
    },
  );

  test(
    'old releases without asset metadata still allow viewing release notes',
    () {
      final result = outcome(body(assets: []));
      expect(result.hasUpdate, isTrue);
      expect(result.downloads, isEmpty);
    },
  );

  test(
    'malformed assets do not turn a valid version response into an exception',
    () {
      final result = outcome(
        body(
          assets: [
            null,
            5,
            'apk',
            {'name': 3, 'size': 'x'},
          ],
        ),
      );
      expect(result.hasUpdate, isTrue);
      expect(result.downloads, isEmpty);
    },
  );
}
