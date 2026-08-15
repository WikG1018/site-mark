import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_failure.dart';
import 'package:sitemark/domain/capture_file_info.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/domain/project_lifecycle.dart';
import 'package:sitemark/features/capture/capture_detail_screen.dart';
import 'package:sitemark/features/capture/capture_image_preview.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/workflow/capture_media_service.dart';
import 'package:sitemark_system_api/sitemark_system_api.dart';

void main() {
  late _DetailDatabase database;
  late _DetailFiles files;
  late _DetailPlatform platform;
  late _DetailPaths paths;
  late _DetailMediaService media;

  Widget buildDetailApp({
    required CaptureMediaService mediaService,
    CaptureRecord? initialCapture,
    Locale locale = const Locale('zh'),
  }) {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        captureOutputPathsProvider.overrideWithValue(paths),
        captureMediaServiceProvider.overrideWithValue(mediaService),
      ],
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: CaptureDetailScreen(
          projectId: 'project-1',
          captureId: 'capture-1',
          initialCapture: initialCapture,
        ),
      ),
    );
  }

  Future<void> pumpReadyDetail(
    WidgetTester tester, {
    required bool originalExists,
    bool settle = true,
    bool includeInitialCapture = false,
    bool originalDeleted = false,
    Locale locale = const Locale('zh'),
    CaptureStatus status = CaptureStatus.ready,
    CaptureFailureCode failureCode = CaptureFailureCode.processingFailed,
    ProjectLifecycleStatus projectStatus = ProjectLifecycleStatus.active,
    Object? inspectError,
  }) async {
    database = _DetailDatabase();
    addTearDown(database.close);
    await database.createProject(id: 'project-1', name: '东区厂房改造');
    final pending = await database.createPendingCapture(
      id: 'capture-1',
      projectId: 'project-1',
      originalPath: '/private/original.jpg',
      workLocation: 'A 区',
      workContent: '风管检查',
      photographer: '张工',
      watermarkLocaleCode: 'zh',
      locationResolution: 'resolved',
    );
    await database.markCaptured(
      captureId: pending.id,
      capturedAt: DateTime(2026, 8, 4, 9),
    );
    if (status != CaptureStatus.captured) {
      await database.markRendering(
        captureId: pending.id,
        originalSha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );
    }
    if (status == CaptureStatus.ready) {
      await database.markReady(
        captureId: pending.id,
        publishedUri: 'content://media/site-mark/1',
      );
    } else if (status == CaptureStatus.failed) {
      await database.markFailed(
        captureId: pending.id,
        reason: failureCode.storageCode,
      );
    }
    if (originalDeleted) {
      await database.markOriginalDeleted(pending.id);
    }
    final readyCapture = await database.captureById(pending.id);
    if (projectStatus != ProjectLifecycleStatus.active) {
      await database.updateProjectLifecycleStatus(
        projectId: 'project-1',
        expectedStatus: ProjectLifecycleStatus.active,
        targetStatus: projectStatus,
      );
    }

    files = _DetailFiles();
    if (originalExists) files.existing.add('/private/original.jpg');
    files.existing.add('/rendered/capture-1.jpg');
    platform = _DetailPlatform()
      ..metadataByPath['/private/original.jpg'] = ImageMetadataResult(
        width: 4000,
        height: 3000,
        fileSizeBytes: 5_000_000,
        mimeType: 'image/jpeg',
      )
      ..metadataByPath['/rendered/capture-1.jpg'] = ImageMetadataResult(
        width: 4000,
        height: 3000,
        fileSizeBytes: 3_200_000,
        mimeType: 'image/jpeg',
      );
    paths = _DetailPaths();
    media = _DetailMediaService(
      database: database,
      platform: platform,
      outputPaths: paths,
      files: files,
    )..inspectError = inspectError;

    await tester.pumpWidget(
      buildDetailApp(
        mediaService: media,
        initialCapture: includeInitialCapture ? readyCapture : null,
        locale: locale,
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  /// Disposes the widget tree by replacing it with an empty widget, then
  /// pumps a frame so the StreamBuilder subscription is cancelled before
  /// addTearDown closes the database. This avoids pending-timer assertions.
  Future<void> disposeDetail(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> showFileInfo(WidgetTester tester) async {
    final tab = find.byKey(const Key('detail-tab-file-info'));
    await tester.ensureVisible(tab);
    await tester.pumpAndSettle();
    await tester.tap(tab);
    await tester.pumpAndSettle();
  }

  testWidgets('detail uses short title, tabs, and file metadata section', (
    tester,
  ) async {
    await pumpReadyDetail(tester, originalExists: true);

    expect(find.text('2026-08-04 · 001'), findsOneWidget);
    expect(find.text('东区厂房改造-SM-20260804-001.jpg'), findsNothing);
    expect(find.byKey(const Key('detail-tab-field-record')), findsOneWidget);
    expect(find.byKey(const Key('detail-tab-file-info')), findsOneWidget);
    expect(find.text('A 区'), findsOneWidget);
    expect(find.text('4.8 MB'), findsNothing);

    await showFileInfo(tester);

    expect(find.text('东区厂房改造-SM-20260804-001.jpg'), findsOneWidget);
    expect(find.text('4.8 MB'), findsOneWidget);
    expect(find.text('3.1 MB'), findsOneWidget);
    expect(find.text('4000 × 3000'), findsNWidgets(2));
    expect(find.text('image/jpeg'), findsNWidgets(2));
    expect(find.text('已发布'), findsOneWidget);
    expect(
      find.text(
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('show-original')), findsOneWidget);
    expect(find.byKey(const Key('delete-original')), findsNothing);
    expect(find.byKey(const Key('delete-all')), findsNothing);
    expect(find.byKey(const Key('capture-detail-actions')), findsOneWidget);
    await disposeDetail(tester);
  });

  testWidgets('action sheet contains text actions and dangerous styling', (
    tester,
  ) async {
    await pumpReadyDetail(tester, originalExists: true);

    await tester.tap(find.byKey(const Key('capture-detail-actions')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('capture-detail-action-sheet')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('edit-record')), findsOneWidget);
    expect(find.byKey(const Key('delete-original')), findsOneWidget);
    final deleteRecord = tester.widget<ListTile>(
      find.byKey(const Key('delete-record')),
    );
    expect(
      (deleteRecord.leading! as Icon).color,
      Theme.of(
        tester.element(find.byKey(const Key('delete-record'))),
      ).colorScheme.error,
    );
    expect(
      (deleteRecord.title as Text).style?.color,
      Theme.of(
        tester.element(find.byKey(const Key('delete-record'))),
      ).colorScheme.error,
    );

    await disposeDetail(tester);
  });

  testWidgets('system back closes the action sheet before detail', (
    tester,
  ) async {
    await pumpReadyDetail(tester, originalExists: true);
    await tester.tap(find.byKey(const Key('capture-detail-actions')));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('capture-detail-action-sheet')), findsNothing);
    expect(find.byType(CaptureDetailScreen), findsOneWidget);
    await disposeDetail(tester);
  });

  testWidgets('tabs and action controls expose tappable semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpReadyDetail(tester, originalExists: true);

    final actions = tester.getSemantics(
      find.byKey(const Key('capture-detail-actions')),
    );
    expect(actions.label, isNotEmpty);
    expect(actions.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

    await tester.ensureVisible(
      find.byKey(const Key('detail-tab-field-record')),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('现场记录')), findsOneWidget);
    final fileInfoTab = find.bySemanticsLabel(RegExp('文件信息'));
    expect(fileInfoTab, findsOneWidget);
    await tester.tap(fileInfoTab);
    await tester.pumpAndSettle();
    expect(find.text('完整文件名'), findsOneWidget);

    await tester.tap(find.byKey(const Key('capture-detail-actions')));
    await tester.pumpAndSettle();
    final deleteRecord = tester.getSemantics(
      find.byKey(const Key('delete-record')),
    );
    expect(deleteRecord.label, contains('删除记录'));
    expect(
      deleteRecord.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );
    await disposeDetail(tester);
    semantics.dispose();
  });

  testWidgets('tab selection survives capture stream refresh', (tester) async {
    await pumpReadyDetail(tester, originalExists: true);
    await showFileInfo(tester);
    expect(find.text('完整文件名'), findsOneWidget);

    await database.markOriginalDeleted('capture-1');
    await tester.pumpAndSettle();

    expect(find.text('完整文件名'), findsOneWidget);
    expect(find.text('原图已清理'), findsOneWidget);
    expect(find.text('A 区'), findsNothing);
    await disposeDetail(tester);
  });

  testWidgets('detail is scrollable at 360dp and 3x in both locales', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final locale in const [Locale('zh'), Locale('en')]) {
      await pumpReadyDetail(tester, originalExists: true, locale: locale);
      expect(
        find.text(locale.languageCode == 'zh' ? '现场记录' : 'Field record'),
        findsOneWidget,
      );
      expect(
        find.text(locale.languageCode == 'zh' ? '文件信息' : 'File info'),
        findsOneWidget,
      );
      await showFileInfo(tester);
      expect(
        find.text(locale.languageCode == 'zh' ? '完整文件名' : 'Full file name'),
        findsOneWidget,
      );
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.text(
          locale.languageCode == 'zh' ? '原图 SHA-256' : 'Original SHA-256',
        ),
        findsOneWidget,
      );
      await disposeDetail(tester);
    }
  });

  testWidgets('detail exposes the record Hero on its first route frame', (
    tester,
  ) async {
    await pumpReadyDetail(
      tester,
      originalExists: true,
      settle: false,
      includeInitialCapture: true,
    );

    final hero = tester.widget<Hero>(find.byType(Hero));
    final firstFrameHeroElement = tester.element(find.byType(Hero));
    final firstFramePreviewElement = tester.element(
      find.byType(CaptureImagePreview),
    );
    expect(hero.tag, 'capture-photo-capture-1');
    // The preview must forward the same tag so opening fullscreen pairs the
    // hero flight (regression: the tag was not forwarded, so fullscreen
    // opened without a hero transition).
    expect(
      tester
          .widget<CaptureImagePreview>(find.byType(CaptureImagePreview))
          .heroTag,
      'capture-photo-capture-1',
    );
    expect(
      tester
          .widget<CaptureImagePreview>(find.byType(CaptureImagePreview))
          .source,
      CapturePreviewSource.bestAvailable,
    );

    await tester.pumpAndSettle();
    expect(tester.element(find.byType(Hero)), same(firstFrameHeroElement));
    expect(
      tester.element(find.byType(CaptureImagePreview)),
      same(firstFramePreviewElement),
    );
    await disposeDetail(tester);
  });

  testWidgets('cleared original keeps a stable watermarked Hero destination', (
    tester,
  ) async {
    await pumpReadyDetail(
      tester,
      originalExists: false,
      originalDeleted: true,
      settle: false,
      includeInitialCapture: true,
    );

    final firstFramePreviewElement = tester.element(
      find.byType(CaptureImagePreview),
    );
    expect(
      tester
          .widget<CaptureImagePreview>(find.byType(CaptureImagePreview))
          .source,
      CapturePreviewSource.watermarked,
    );

    await tester.pumpAndSettle();
    expect(
      tester.element(find.byType(CaptureImagePreview)),
      same(firstFramePreviewElement),
    );
    await disposeDetail(tester);
  });

  testWidgets('unexpected missing original does not replace the Hero preview', (
    tester,
  ) async {
    await pumpReadyDetail(
      tester,
      originalExists: false,
      settle: false,
      includeInitialCapture: true,
    );

    final firstFramePreviewElement = tester.element(
      find.byType(CaptureImagePreview),
    );
    expect(
      tester
          .widget<CaptureImagePreview>(find.byType(CaptureImagePreview))
          .source,
      CapturePreviewSource.bestAvailable,
    );

    await tester.pumpAndSettle();
    expect(
      tester.element(find.byType(CaptureImagePreview)),
      same(firstFramePreviewElement),
    );
    expect(
      tester
          .widget<CaptureImagePreview>(find.byType(CaptureImagePreview))
          .source,
      CapturePreviewSource.watermarked,
    );
    await disposeDetail(tester);
  });

  testWidgets('original preview keeps the record photo Hero tag', (
    tester,
  ) async {
    await pumpReadyDetail(tester, originalExists: true);

    await tester.tap(find.byKey(const Key('show-original')));
    await tester.pumpAndSettle();

    final preview = tester.widget<CaptureImagePreview>(
      find.byType(CaptureImagePreview),
    );
    expect(preview.source, CapturePreviewSource.original);
    expect(preview.heroTag, 'capture-photo-capture-1');
    expect(
      tester.widget<Hero>(find.byType(Hero)).tag,
      'capture-photo-capture-1',
    );
    await disposeDetail(tester);
  });

  testWidgets('deleting original keeps detail and disables original preview', (
    tester,
  ) async {
    await pumpReadyDetail(tester, originalExists: true);
    await tester.tap(find.byKey(const Key('capture-detail-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-original')));
    // Advance past the 5-second undo window so the timer fires.
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    await showFileInfo(tester);
    expect(find.text('原图已清理'), findsOneWidget);
    expect(find.byKey(const Key('show-original')), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(await database.captureById('capture-1'), isNotNull);
    await disposeDetail(tester);
  });

  testWidgets('undo cancels the delete-original timer', (tester) async {
    await pumpReadyDetail(tester, originalExists: true);
    await tester.tap(find.byKey(const Key('capture-detail-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-original')));
    // Let the SnackBar appear without advancing past the 5-second window.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();

    expect(find.text('原图已清理'), findsNothing);
    expect(find.byKey(const Key('show-original')), findsOneWidget);
    expect(
      (await database.captureById('capture-1'))?.originalDeletedAt,
      isNull,
    );
    await disposeDetail(tester);
  });

  testWidgets('missing original is explicit and disables original actions', (
    tester,
  ) async {
    await pumpReadyDetail(tester, originalExists: false);

    await showFileInfo(tester);
    expect(find.text('原图缺失'), findsOneWidget);
    expect(find.byKey(const Key('show-original')), findsNothing);
    await tester.tap(find.byKey(const Key('capture-detail-actions')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('delete-original')), findsNothing);
    expect(find.byKey(const Key('edit-record')), findsNothing);
    expect(find.byKey(const Key('delete-record')), findsOneWidget);

    await disposeDetail(tester);
  });

  testWidgets('failed detail offers cleanup and record deletion but no edit', (
    tester,
  ) async {
    await pumpReadyDetail(
      tester,
      originalExists: true,
      status: CaptureStatus.failed,
    );

    await tester.tap(find.byKey(const Key('capture-detail-actions')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('edit-record')), findsNothing);
    expect(find.byKey(const Key('delete-original')), findsOneWidget);
    expect(find.byKey(const Key('delete-record')), findsOneWidget);
    await disposeDetail(tester);
  });

  for (final locale in const [Locale('zh'), Locale('en')]) {
    testWidgets('failed detail gives code-matched guidance and retry controls in '
        '${locale.languageCode}', (tester) async {
      final expectations =
          <
            CaptureFailureCode,
            ({bool originalExists, bool retry, String reason, String nextStep})
          >{
            CaptureFailureCode.originalMissing: (
              originalExists: false,
              retry: false,
              reason: locale.languageCode == 'zh'
                  ? '原图已缺失'
                  : 'original is missing',
              nextStep: locale.languageCode == 'zh'
                  ? '返回项目重新拍摄'
                  : 'Return to the project and take the photo again',
            ),
            CaptureFailureCode.originalModified: (
              originalExists: true,
              retry: false,
              reason: locale.languageCode == 'zh'
                  ? '校验值不一致'
                  : 'does not match its capture-time checksum',
              nextStep: locale.languageCode == 'zh'
                  ? '保留现有原图作为证据并重新拍摄'
                  : 'Keep the current original as evidence and take the photo again',
            ),
            CaptureFailureCode.processingFailed: (
              originalExists: true,
              retry: true,
              reason: locale.languageCode == 'zh'
                  ? '照片处理失败'
                  : 'Photo processing failed',
              nextStep: locale.languageCode == 'zh'
                  ? '点击“重新处理”'
                  : 'Select Retry processing',
            ),
            CaptureFailureCode.unexpected: (
              originalExists: true,
              retry: true,
              reason: locale.languageCode == 'zh'
                  ? '未知原因处理失败'
                  : 'unknown reason',
              nextStep: locale.languageCode == 'zh'
                  ? '点击“重新处理”'
                  : 'Select Retry processing',
            ),
          };

      for (final entry in expectations.entries) {
        await pumpReadyDetail(
          tester,
          originalExists: entry.value.originalExists,
          status: CaptureStatus.failed,
          failureCode: entry.key,
          locale: locale,
        );

        final guidance = find.byKey(const Key('capture-failure-guidance'));
        expect(guidance, findsOneWidget, reason: entry.key.name);
        expect(
          find.descendant(
            of: guidance,
            matching: find.textContaining(entry.value.reason),
          ),
          findsOneWidget,
          reason: entry.key.name,
        );
        expect(
          find.descendant(
            of: guidance,
            matching: find.textContaining(entry.value.nextStep),
          ),
          findsOneWidget,
          reason: entry.key.name,
        );
        expect(
          find.byKey(const Key('capture-retry-processing')),
          entry.value.retry ? findsOneWidget : findsNothing,
          reason: entry.key.name,
        );
        await disposeDetail(tester);
      }
    });
  }

  for (final locale in const [Locale('zh'), Locale('en')]) {
    testWidgets('processing failure guidance matches final actions in '
        '${locale.languageCode}', (tester) async {
      final cases =
          <
            ({
              String name,
              bool originalExists,
              bool originalDeleted,
              ProjectLifecycleStatus projectStatus,
              bool retry,
              String nextStep,
            })
          >[
            (
              name: 'retained-active',
              originalExists: true,
              originalDeleted: false,
              projectStatus: ProjectLifecycleStatus.active,
              retry: true,
              nextStep: locale.languageCode == 'zh'
                  ? '点击“重新处理”'
                  : 'Select Retry processing',
            ),
            (
              name: 'missing-active',
              originalExists: false,
              originalDeleted: false,
              projectStatus: ProjectLifecycleStatus.active,
              retry: false,
              nextStep: locale.languageCode == 'zh'
                  ? '原图当前缺失'
                  : 'The original is currently missing',
            ),
            (
              name: 'cleared-active',
              originalExists: false,
              originalDeleted: true,
              projectStatus: ProjectLifecycleStatus.active,
              retry: false,
              nextStep: locale.languageCode == 'zh'
                  ? '原图已清理'
                  : 'The original has been cleared',
            ),
            (
              name: 'retained-read-only',
              originalExists: true,
              originalDeleted: false,
              projectStatus: ProjectLifecycleStatus.completed,
              retry: false,
              nextStep: locale.languageCode == 'zh'
                  ? '项目当前为只读状态'
                  : 'The project is read-only',
            ),
          ];

      for (final item in cases) {
        await pumpReadyDetail(
          tester,
          originalExists: item.originalExists,
          originalDeleted: item.originalDeleted,
          status: CaptureStatus.failed,
          failureCode: CaptureFailureCode.processingFailed,
          projectStatus: item.projectStatus,
          locale: locale,
        );

        final guidance = find.byKey(const Key('capture-failure-guidance'));
        expect(guidance, findsOneWidget, reason: item.name);
        expect(
          find.descendant(
            of: guidance,
            matching: find.textContaining(item.nextStep),
          ),
          findsOneWidget,
          reason: item.name,
        );
        expect(
          find.byKey(const Key('capture-retry-processing')),
          item.retry ? findsOneWidget : findsNothing,
          reason: item.name,
        );
        if (!item.retry) {
          expect(
            find.descendant(
              of: guidance,
              matching: find.textContaining(
                locale.languageCode == 'zh'
                    ? '点击“重新处理”'
                    : 'Select Retry processing',
              ),
            ),
            findsNothing,
            reason: item.name,
          );
        }
        await disposeDetail(tester);
      }
    });
  }

  for (final locale in const [Locale('zh'), Locale('en')]) {
    testWidgets('inspect failure keeps safe processing guidance in '
        '${locale.languageCode}', (tester) async {
      await pumpReadyDetail(
        tester,
        originalExists: true,
        status: CaptureStatus.failed,
        failureCode: CaptureFailureCode.processingFailed,
        locale: locale,
        inspectError: StateError('raw inspect failure'),
      );

      final guidance = find.byKey(const Key('capture-failure-guidance'));
      expect(guidance, findsOneWidget);
      expect(
        find.descendant(
          of: guidance,
          matching: find.textContaining(
            locale.languageCode == 'zh' ? '照片处理失败' : 'Photo processing failed',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: guidance,
          matching: find.textContaining(
            locale.languageCode == 'zh'
                ? '无法检查原图状态，暂不提供重新处理'
                : 'The original photo state could not be checked, so Retry processing is unavailable for now',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: guidance,
          matching: find.textContaining(
            locale.languageCode == 'zh'
                ? '稍后重新打开详情检查'
                : 'reopen the details later to check again',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: guidance,
          matching: find.textContaining(
            locale.languageCode == 'zh'
                ? '右上角菜单删除记录'
                : 'top-right menu to delete it',
          ),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('capture-retry-processing')), findsNothing);
      expect(find.textContaining('raw inspect failure'), findsNothing);
      expect(find.byKey(const Key('capture-detail-actions')), findsOneWidget);

      await disposeDetail(tester);
    });
  }

  for (final locale in const [Locale('zh'), Locale('en')]) {
    for (final status in const [CaptureStatus.ready, CaptureStatus.failed]) {
      testWidgets(
        '${status.name} file info retries a localized inspection error in ${locale.languageCode}',
        (tester) async {
          await pumpReadyDetail(
            tester,
            originalExists: true,
            status: status,
            locale: locale,
            inspectError: StateError('raw inspect failure'),
          );

          final fileInfoTab = find.byKey(const Key('detail-tab-file-info'));
          await tester.ensureVisible(fileInfoTab);
          await tester.pumpAndSettle();
          await tester.tap(fileInfoTab);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          final error = find.byKey(const Key('file-info-inspection-error'));
          expect(error, findsOneWidget);
          expect(
            find.descendant(
              of: error,
              matching: find.textContaining(
                locale.languageCode == 'zh'
                    ? '无法检查文件信息'
                    : 'File information could not be checked',
              ),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: error,
              matching: find.textContaining(
                locale.languageCode == 'zh'
                    ? '请保留此记录并重新检查'
                    : 'Keep this record and check again',
              ),
            ),
            findsOneWidget,
          );
          expect(find.textContaining('raw inspect failure'), findsNothing);
          expect(find.byKey(const Key('file-info-retry')), findsOneWidget);
          expect(media.inspectCalls, 1);

          media.inspectError = null;
          await tester.tap(find.byKey(const Key('file-info-retry')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          await tester.pump(const Duration(milliseconds: 1));

          expect(
            find.byKey(const Key('file-info-inspection-error')),
            findsNothing,
          );
          expect(find.byKey(const Key('file-info-retry')), findsNothing);
          expect(find.text('4.8 MB'), findsOneWidget);
          expect(media.inspectCalls, 2);
          await disposeDetail(tester);
        },
      );
    }
  }

  testWidgets('file info refreshes when the media service is replaced', (
    tester,
  ) async {
    await pumpReadyDetail(tester, originalExists: true);
    final originalMedia = media;
    expect(originalMedia.inspectCalls, 1);

    final replacementMedia = _DetailMediaService(
      database: database,
      platform: platform,
      outputPaths: paths,
      files: files,
    );
    await tester.pumpWidget(
      buildDetailApp(
        mediaService: replacementMedia,
        initialCapture: await database.captureById('capture-1'),
      ),
    );
    await tester.pumpAndSettle();

    expect(originalMedia.inspectCalls, 1);
    expect(replacementMedia.inspectCalls, 1);
    await disposeDetail(tester);
  });

  testWidgets('processing and read-only details expose no mutation menu', (
    tester,
  ) async {
    await pumpReadyDetail(
      tester,
      originalExists: true,
      status: CaptureStatus.rendering,
    );
    expect(find.byKey(const Key('capture-detail-actions')), findsNothing);
    await disposeDetail(tester);

    await pumpReadyDetail(
      tester,
      originalExists: true,
      projectStatus: ProjectLifecycleStatus.completed,
    );
    expect(find.byKey(const Key('capture-detail-actions')), findsNothing);
    await disposeDetail(tester);
  });

  testWidgets('stale action is ignored when project becomes read-only', (
    tester,
  ) async {
    await pumpReadyDetail(tester, originalExists: true);
    await tester.tap(find.byKey(const Key('capture-detail-actions')));
    await tester.pumpAndSettle();
    await database.updateProjectLifecycleStatus(
      projectId: 'project-1',
      expectedStatus: ProjectLifecycleStatus.active,
      targetStatus: ProjectLifecycleStatus.completed,
    );

    await tester.tap(find.byKey(const Key('delete-original')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    expect(
      (await database.captureById('capture-1'))?.originalDeletedAt,
      isNull,
    );
    expect(files.existing, contains('/private/original.jpg'));
    await disposeDetail(tester);
  });

  testWidgets('stale delete is ignored when record starts processing', (
    tester,
  ) async {
    await pumpReadyDetail(tester, originalExists: true);
    await tester.tap(find.byKey(const Key('capture-detail-actions')));
    await tester.pumpAndSettle();
    await database.markCaptured(
      captureId: 'capture-1',
      capturedAt: DateTime(2026, 8, 4, 10),
    );

    await tester.tap(find.byKey(const Key('delete-record')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(await database.captureById('capture-1'), isNotNull);
    expect(files.existing, contains('/private/original.jpg'));
    await disposeDetail(tester);
  });

  testWidgets('edit revalidates project after delayed file inspection', (
    tester,
  ) async {
    await pumpReadyDetail(tester, originalExists: true);
    final releaseInspect = media.delayNextInspect();

    await tester.tap(find.byKey(const Key('capture-detail-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-record')));
    await tester.pump();
    await tester.pump();
    expect(media.inspectBlocked, isTrue);

    await database.updateProjectLifecycleStatus(
      projectId: 'project-1',
      expectedStatus: ProjectLifecycleStatus.active,
      targetStatus: ProjectLifecycleStatus.completed,
    );
    releaseInspect.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(CaptureDetailScreen), findsOneWidget);
    await disposeDetail(tester);
  });

  testWidgets(
    'delete original revalidates capture after delayed file inspection',
    (tester) async {
      await pumpReadyDetail(tester, originalExists: true);
      final releaseInspect = media.delayNextInspect();

      await tester.tap(find.byKey(const Key('capture-detail-actions')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete-original')));
      await tester.pump();
      await tester.pump();
      expect(media.inspectBlocked, isTrue);

      await database.markCaptured(
        captureId: 'capture-1',
        capturedAt: DateTime(2026, 8, 4, 10),
      );
      releaseInspect.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('将在 5 秒后清理 1 张原图'), findsNothing);
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(media.clearOriginalCalls, 0);
      expect(files.existing, contains('/private/original.jpg'));
      await disposeDetail(tester);
    },
  );

  testWidgets('delete record revalidates a delayed project read', (
    tester,
  ) async {
    await pumpReadyDetail(tester, originalExists: true);
    final releaseProjectRead = database.delayNextProjectRead();

    await tester.tap(find.byKey(const Key('capture-detail-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-record')));
    await tester.pump();
    await tester.pump();
    expect(database.projectReadBlocked, isTrue);

    await database.updateProjectLifecycleStatus(
      projectId: 'project-1',
      expectedStatus: ProjectLifecycleStatus.active,
      targetStatus: ProjectLifecycleStatus.archived,
    );
    releaseProjectRead.complete();
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(media.deleteAllCalls, 0);
    expect(await database.captureById('capture-1'), isNotNull);
    await disposeDetail(tester);
  });

  testWidgets('delete record revalidates a delayed capture read', (
    tester,
  ) async {
    await pumpReadyDetail(tester, originalExists: true);
    final releaseCaptureRead = database.delayNextCaptureRead();

    await tester.tap(find.byKey(const Key('capture-detail-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-record')));
    await tester.pump();
    await tester.pump();
    expect(database.captureReadBlocked, isTrue);

    await database.markCaptured(
      captureId: 'capture-1',
      capturedAt: DateTime(2026, 8, 4, 10),
    );
    releaseCaptureRead.complete();
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(media.deleteAllCalls, 0);
    expect(await database.captureById('capture-1'), isNotNull);
    await disposeDetail(tester);
  });

  testWidgets('delete original timer revalidates before clearing files', (
    tester,
  ) async {
    await pumpReadyDetail(tester, originalExists: true);
    await tester.tap(find.byKey(const Key('capture-detail-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-original')));
    await tester.pump();
    expect(find.text('将在 5 秒后清理 1 张原图'), findsOneWidget);

    await database.markCaptured(
      captureId: 'capture-1',
      capturedAt: DateTime(2026, 8, 4, 10),
    );
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    expect(media.clearOriginalCalls, 0);
    expect(files.existing, contains('/private/original.jpg'));
    await disposeDetail(tester);
  });

  testWidgets('delete record dialog revalidates after confirmation', (
    tester,
  ) async {
    await pumpReadyDetail(tester, originalExists: true);
    await tester.tap(find.byKey(const Key('capture-detail-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-record')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    await database.markCaptured(
      captureId: 'capture-1',
      capturedAt: DateTime(2026, 8, 4, 10),
    );
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(media.deleteAllCalls, 0);
    expect(await database.captureById('capture-1'), isNotNull);
    expect(files.existing, contains('/private/original.jpg'));
    await disposeDetail(tester);
  });

  testWidgets('failed original file cleanup commits for startup retry', (
    tester,
  ) async {
    await pumpReadyDetail(tester, originalExists: true);
    files.deleteError = StateError('delete blocked');

    await tester.tap(find.byKey(const Key('capture-detail-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-original')));
    await tester.pump();
    // Verify the undo Snackbar appears.
    expect(find.text('将在 5 秒后清理 1 张原图'), findsOneWidget);

    // Advance past the 5-second undo window.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    // The user-visible database change is committed, while the durable marker
    // keeps the physical file eligible for a later startup retry.
    expect(
      (await database.captureById('capture-1'))?.originalDeletedAt,
      isNotNull,
    );
    expect(files.existing, contains('/private/original.jpg'));

    files.deleteError = null;
    await media.cleanupInterrupted();
    expect(files.existing, isNot(contains('/private/original.jpg')));

    await disposeDetail(tester);
  });

  testWidgets('formats captured at with the locale instead of ISO-8601', (
    tester,
  ) async {
    final capturedAt = DateTime(2026, 8, 4, 9);
    await pumpReadyDetail(tester, originalExists: true);
    expect(
      find.text(DateFormat.yMMMd('zh').add_Hm().format(capturedAt)),
      findsOneWidget,
    );
    expect(find.textContaining('2026-08-04T'), findsNothing);
    await disposeDetail(tester);

    await pumpReadyDetail(
      tester,
      originalExists: true,
      locale: const Locale('en'),
    );
    expect(
      find.text(DateFormat.yMMMd('en').add_Hm().format(capturedAt)),
      findsOneWidget,
    );
    expect(find.textContaining('2026-08-04T'), findsNothing);
    await disposeDetail(tester);
  });

  testWidgets('missing capture shows not-found instead of a spinner', (
    tester,
  ) async {
    database = _DetailDatabase();
    addTearDown(database.close);
    await database.createProject(id: 'project-1', name: '东区厂房改造');
    files = _DetailFiles();
    platform = _DetailPlatform();
    paths = _DetailPaths();
    media = _DetailMediaService(
      database: database,
      platform: platform,
      outputPaths: paths,
      files: files,
    );

    await tester.pumpWidget(buildDetailApp(mediaService: media));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('capture-not-found')), findsOneWidget);
    expect(find.text('拍摄记录不存在或已删除'), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await disposeDetail(tester);
  });

  testWidgets('capture lookup error shows an explicit load-failed state', (
    tester,
  ) async {
    database = _ErrorCaptureWatchDatabase();
    addTearDown(database.close);
    await database.createProject(id: 'project-1', name: '东区厂房改造');
    files = _DetailFiles();
    platform = _DetailPlatform();
    paths = _DetailPaths();
    media = _DetailMediaService(
      database: database,
      platform: platform,
      outputPaths: paths,
      files: files,
    );

    await tester.pumpWidget(
      buildDetailApp(mediaService: media, locale: const Locale('en')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('capture-load-error')), findsOneWidget);
    expect(
      find.text(AppStrings(const Locale('en')).captureLoadFailed),
      findsWidgets,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await disposeDetail(tester);
  });
}

class _ErrorCaptureWatchDatabase extends _DetailDatabase {
  @override
  Stream<CaptureRecord?> watchCaptureById(String captureId) {
    return Stream<CaptureRecord?>.error(StateError('lookup failed'));
  }
}

class _DetailDatabase extends AppDatabase {
  _DetailDatabase() : super.forTesting(NativeDatabase.memory());

  Completer<void>? _projectReadRelease;
  Completer<void>? _projectReadStarted;
  Completer<void>? _captureReadRelease;
  Completer<void>? _captureReadStarted;

  Completer<void> delayNextProjectRead() {
    final release = Completer<void>();
    _projectReadRelease = release;
    _projectReadStarted = Completer<void>();
    return release;
  }

  Completer<void> delayNextCaptureRead() {
    final release = Completer<void>();
    _captureReadRelease = release;
    _captureReadStarted = Completer<void>();
    return release;
  }

  bool get projectReadBlocked => _projectReadStarted?.isCompleted ?? false;
  bool get captureReadBlocked => _captureReadStarted?.isCompleted ?? false;

  @override
  Future<Project?> projectById(String projectId) async {
    final snapshot = await super.projectById(projectId);
    final release = _projectReadRelease;
    if (release == null) return snapshot;
    _projectReadRelease = null;
    _projectReadStarted?.complete();
    await release.future;
    return snapshot;
  }

  @override
  Future<CaptureRecord?> captureById(String captureId) async {
    final snapshot = await super.captureById(captureId);
    final release = _captureReadRelease;
    if (release == null) return snapshot;
    _captureReadRelease = null;
    _captureReadStarted?.complete();
    await release.future;
    return snapshot;
  }
}

class _DetailMediaService extends CaptureMediaService {
  _DetailMediaService({
    required super.database,
    required super.platform,
    required super.outputPaths,
    required super.files,
  });

  Completer<void>? _inspectRelease;
  Completer<void>? _inspectStarted;
  Object? inspectError;
  int inspectCalls = 0;
  int clearOriginalCalls = 0;
  int deleteAllCalls = 0;

  Completer<void> delayNextInspect() {
    final release = Completer<void>();
    _inspectRelease = release;
    _inspectStarted = Completer<void>();
    return release;
  }

  bool get inspectBlocked => _inspectStarted?.isCompleted ?? false;

  @override
  Future<CaptureFileInfo> inspect(CaptureRecord record) async {
    inspectCalls += 1;
    final error = inspectError;
    if (error != null) throw error;
    final snapshot = await super.inspect(record);
    final release = _inspectRelease;
    if (release == null) return snapshot;
    _inspectRelease = null;
    _inspectStarted?.complete();
    await release.future;
    return snapshot;
  }

  @override
  Future<CaptureActionResult> clearOriginals(List<String> captureIds) {
    clearOriginalCalls += 1;
    return super.clearOriginals(captureIds);
  }

  @override
  Future<CaptureActionResult> deleteAll(List<String> captureIds) {
    deleteAllCalls += 1;
    return super.deleteAll(captureIds);
  }
}

class _DetailFiles implements PrivateFileStore {
  final Set<String> existing = {};
  Object? deleteError;
  @override
  Future<bool> exists(String path) async => existing.contains(path);
  @override
  Future<void> deleteIfExists(String path) async {
    final error = deleteError;
    if (error != null) throw error;
    existing.remove(path);
  }
}

class _DetailPaths implements CaptureOutputPaths {
  @override
  Future<String> renderedPhotoPath(String captureId) async =>
      '/rendered/$captureId.jpg';
}

class _DetailPlatform implements PlatformServices {
  final Map<String, ImageMetadataResult> metadataByPath = {};
  @override
  Future<ImageMetadataResult> inspectImage(String path) async =>
      metadataByPath[path]!;
  @override
  Future<void> deletePublishedImage(String contentUri) async {}
  @override
  Future<String> publishJpeg(String sourcePath, String displayName) async =>
      'content://media/site-mark/1';
  @override
  Future<LocationPermissionState> getLocationPermissionState() async =>
      LocationPermissionState.denied;
  @override
  Future<LocationPermissionState> requestLocationPermission() async =>
      LocationPermissionState.denied;
  @override
  Future<void> openApplicationSettings() async {}
  @override
  Future<LocationResult> requestCurrentLocation(int timeoutMillis) async =>
      LocationResult(outcome: LocationOutcome.permissionDenied);
  @override
  Future<String> createCameraTarget(String captureId) =>
      throw UnsupportedError('camera not used');
  @override
  Future<CameraCaptureResult> launchCamera(String captureId) =>
      throw UnsupportedError('camera not used');
  @override
  Future<RecoveredCameraCapture?> recoverCameraCapture() async => null;
  @override
  Future<void> finishCameraCapture(String captureId, bool keepOriginal) async {}
}
