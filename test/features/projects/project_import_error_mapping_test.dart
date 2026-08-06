import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/diagnostics/diagnostic_event.dart';
import 'package:sitemark/domain/project_name.dart';
import 'package:sitemark/features/projects/project_import_flow.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/workflow/project_import_service.dart';

void main() {
  for (final locale in const [Locale('zh'), Locale('en')]) {
    group('describeImportError ($locale)', () {
      final strings = AppStrings(locale);

      test('maps invalid archive without leaking detail', () {
        final message = describeImportError(
          strings,
          const InvalidArchiveException('raw path /private/backup.zip'),
        );
        expect(message, strings.importInvalidArchive);
        expect(message, isNot(contains('raw path')));
        expect(message, isNot(contains('/private/')));
      });

      test('maps selection archives', () {
        expect(
          describeImportError(
            strings,
            const ImagePipelineException(
              ImagePipelineFailureKind.invalidData,
              'selection archive not restorable',
            ),
          ),
          strings.importSelectionUnsupported,
        );
      });

      test('maps name conflicts', () {
        expect(
          describeImportError(
            strings,
            const ProjectNameConflictException(
              ProjectNameConflictKind.displayName,
            ),
          ),
          strings.importNameConflict,
        );
      });

      test('maps insufficient storage', () {
        expect(
          describeImportError(
            strings,
            const FileSystemException(
              'write failed',
              '/private/import.zip',
              OSError('No space left on device', 28),
            ),
          ),
          strings.backupStorageInsufficient,
        );
      });

      test('maps finalization pending', () {
        final message = describeImportError(
          strings,
          ProjectImportFinalizationPendingException(
            projectId: 'project-1',
            cause: StateError('raw finalize detail'),
          ),
        );
        expect(message, strings.restoreFinalizationPending);
        expect(message, isNot(contains('raw finalize')));
        expect(message, isNot(contains('project-1')));
      });

      test('never appends raw exception text for unknown failures', () {
        final message = describeImportError(
          strings,
          StateError('secret path /data/user/0/io.github.wikg1018.sitemark'),
        );
        expect(message, strings.importFailedFriendly);
        expect(message, isNot(contains('secret')));
        expect(message, isNot(contains('/data/')));
        expect(message, isNot(contains('StateError')));
      });

      test('maps other image-pipeline failures without raw text', () {
        final message = describeImportError(
          strings,
          const ImagePipelineException(
            ImagePipelineFailureKind.transientIo,
            'io: disk path /tmp/secret.jpg',
          ),
        );
        expect(message, strings.importFailedFriendly);
        expect(message, isNot(contains('/tmp/')));
      });
    });
  }

  group('importDiagnosticCode', () {
    test('classifies known failures', () {
      expect(
        importDiagnosticCode(const InvalidArchiveException('x')),
        DiagnosticCode.invalidArchive,
      );
      expect(
        importDiagnosticCode(
          const ImagePipelineException(
            ImagePipelineFailureKind.invalidData,
            'selection archive',
          ),
        ),
        DiagnosticCode.invalidArchive,
      );
      expect(
        importDiagnosticCode(
          const FileSystemException(
            'write failed',
            '/x',
            OSError('No space left on device', 28),
          ),
        ),
        DiagnosticCode.insufficientStorage,
      );
      expect(
        importDiagnosticCode(
          ProjectImportFinalizationPendingException(
            projectId: 'p',
            cause: StateError('x'),
          ),
        ),
        DiagnosticCode.none,
      );
      expect(
        importDiagnosticCode(StateError('unknown')),
        DiagnosticCode.unexpected,
      );
    });
  });
}
