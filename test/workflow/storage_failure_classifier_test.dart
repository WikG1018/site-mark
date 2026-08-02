import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/workflow/project_bundle_service.dart';

void main() {
  final codeCases =
      <({StorageFailurePlatform platform, int code, bool expected})>[
        (platform: StorageFailurePlatform.windows, code: 39, expected: true),
        (platform: StorageFailurePlatform.windows, code: 112, expected: true),
        (platform: StorageFailurePlatform.windows, code: 28, expected: false),
        (platform: StorageFailurePlatform.posix, code: 28, expected: true),
        (platform: StorageFailurePlatform.posix, code: 39, expected: false),
        (platform: StorageFailurePlatform.posix, code: 112, expected: false),
        (platform: StorageFailurePlatform.unknown, code: 28, expected: false),
        (platform: StorageFailurePlatform.unknown, code: 39, expected: false),
        (platform: StorageFailurePlatform.unknown, code: 112, expected: false),
      ];

  for (final codeCase in codeCases) {
    for (final wrapped in [false, true]) {
      test('${codeCase.platform.name} code ${codeCase.code} '
          '${wrapped ? 'wrapped' : 'direct'} => ${codeCase.expected}', () {
        final fileError = FileSystemException(
          'opaque write failure',
          '/private/output.zip',
          OSError('opaque operating-system failure', codeCase.code),
        );
        final error = wrapped
            ? ProjectBackupExportException(
                projectId: 'private-project-id',
                projectName: 'Private project name',
                cause: fileError,
              )
            : fileError;

        expect(
          isInsufficientStorageFailureForPlatform(
            error,
            platform: codeCase.platform,
          ),
          codeCase.expected,
        );
      });
    }
  }

  test('operating-system names map conservatively', () {
    expect(
      storageFailurePlatformForOperatingSystem('windows'),
      StorageFailurePlatform.windows,
    );
    for (final operatingSystem in ['android', 'linux', 'macos', 'ios']) {
      expect(
        storageFailurePlatformForOperatingSystem(operatingSystem),
        StorageFailurePlatform.posix,
      );
    }
    expect(
      storageFailurePlatformForOperatingSystem('fuchsia'),
      StorageFailurePlatform.unknown,
    );
    expect(
      storageFailurePlatformForOperatingSystem('future-os'),
      StorageFailurePlatform.unknown,
    );
  });

  for (final platform in StorageFailurePlatform.values) {
    test(
      '${platform.name} preserves direct and wrapped ENOSPC text fallback',
      () {
        final direct = StateError('ENOSPC while writing backup');
        final wrapped = ProjectBackupExportException(
          projectId: 'private-project-id',
          projectName: 'Private project name',
          cause: direct,
        );

        expect(
          isInsufficientStorageFailureForPlatform(direct, platform: platform),
          isTrue,
        );
        expect(
          isInsufficientStorageFailureForPlatform(wrapped, platform: platform),
          isTrue,
        );
      },
    );
  }
}
