import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/domain/capture_failure.dart';
import 'package:sitemark/domain/capture_media_failure.dart';
import 'package:sitemark/l10n/app_strings.dart';

typedef _StringReader = String Function(AppStrings strings);
typedef _LocalizedSnapshot = ({Locale locale, Map<String, String> values});

const _projectName = 'Project Alpha';

final _stringReaders = <String, _StringReader>{
  'recentlyUsed': (strings) => strings.recentlyUsed,
  'more': (strings) => strings.more,
  'searchHistory': (strings) => strings.searchHistory,
  'noRecentSuggestions': (strings) => strings.noRecentSuggestions,
  'suggestionsLoadFailed': (strings) => strings.suggestionsLoadFailed,
  'captureTemplates': (strings) => strings.captureTemplates,
  'captureTemplateCreate': (strings) => strings.captureTemplateCreate,
  'captureTemplateName': (strings) => strings.captureTemplateName,
  'captureTemplateEmpty': (strings) => strings.captureTemplateEmpty,
  'captureTemplateApplied': (strings) => strings.captureTemplateApplied,
  'captureTemplateLoadFailed': (strings) => strings.captureTemplateLoadFailed,
  'captureTemplateSaveFailed': (strings) => strings.captureTemplateSaveFailed,
  'captureTemplateRenameFailed': (strings) =>
      strings.captureTemplateRenameFailed,
  'captureTemplateDeleteFailed': (strings) =>
      strings.captureTemplateDeleteFailed,
  'captureTemplateDeleteTitle': (strings) => strings.captureTemplateDeleteTitle,
  'captureTemplateDeleteNotice': (strings) =>
      strings.captureTemplateDeleteNotice,
  'captureTemplateRename': (strings) => strings.captureTemplateRename,
  'captureTemplateEmptyName': (strings) => strings.captureTemplateEmptyName,
  'captureTemplateNameTooLong': (strings) => strings.captureTemplateNameTooLong,
  'captureTemplateEmptyWorkLocation': (strings) =>
      strings.captureTemplateEmptyWorkLocation,
  'captureTemplateWorkLocationTooLong': (strings) =>
      strings.captureTemplateWorkLocationTooLong,
  'captureTemplateEmptyWorkContent': (strings) =>
      strings.captureTemplateEmptyWorkContent,
  'captureTemplateWorkContentTooLong': (strings) =>
      strings.captureTemplateWorkContentTooLong,
  'captureTemplateEmptyPhotographer': (strings) =>
      strings.captureTemplateEmptyPhotographer,
  'captureTemplatePhotographerTooLong': (strings) =>
      strings.captureTemplatePhotographerTooLong,
  'captureTemplateDuplicateName': (strings) =>
      strings.captureTemplateDuplicateName,
  'captureTemplateLimitReached': (strings) =>
      strings.captureTemplateLimitReached,
  'captureTemplateInvalidCharacter': (strings) =>
      strings.captureTemplateInvalidCharacter,
  'captureTemplateNotFound': (strings) => strings.captureTemplateNotFound,
  'backupFailedFriendly': (strings) => strings.backupFailedFriendly,
  'importFailedFriendly': (strings) => strings.importFailedFriendly,
  'backupProjectFailed': (strings) => strings.backupProjectFailed(_projectName),
  'backupStorageInsufficient': (strings) => strings.backupStorageInsufficient,
  'backupCorrupted': (strings) => strings.backupCorrupted,
  'backupNotSiteMark': (strings) => strings.backupNotSiteMark,
  'backupUnsupportedVersion': (strings) => strings.backupUnsupportedVersion,
  'backupSelectionNotRestorable': (strings) =>
      strings.backupSelectionNotRestorable,
  'backupRestoreNameConflict': (strings) => strings.backupRestoreNameConflict,
  'restoreFinalizationPending': (strings) => strings.restoreFinalizationPending,
  'restoreFailedRollback': (strings) => strings.restoreFailedRollback,
  'restoreFailedGeneral': (strings) => strings.restoreFailedGeneral,
  'captureOriginalMissing': (strings) =>
      strings.captureFailureMessage(CaptureFailureCode.originalMissing),
  'captureOriginalModified': (strings) =>
      strings.captureFailureMessage(CaptureFailureCode.originalModified),
  'captureProcessingFailed': (strings) =>
      strings.captureFailureMessage(CaptureFailureCode.processingFailed),
  'captureUnexpectedFailure': (strings) =>
      strings.captureFailureMessage(CaptureFailureCode.unexpected),
  'captureListLoadFailed': (strings) => strings.captureListLoadFailed,
  'projectStatusActive': (strings) => strings.projectStatusActive,
  'projectStatusCompleted': (strings) => strings.projectStatusCompleted,
  'projectStatusArchived': (strings) => strings.projectStatusArchived,
  'pinProject': (strings) => strings.pinProject,
  'unpinProject': (strings) => strings.unpinProject,
  'markProjectCompleted': (strings) => strings.markProjectCompleted,
  'archiveProject': (strings) => strings.archiveProject,
  'reopenProject': (strings) => strings.reopenProject,
  'restoreProjectToActive': (strings) => strings.restoreProjectToActive,
  'projectLifecycleConflict': (strings) => strings.projectLifecycleConflict,
  'viewArchivedProjects': (strings) => strings.viewArchivedProjects,
  'noActiveProjects': (strings) => strings.noActiveProjects,
  'noCompletedProjects': (strings) => strings.noCompletedProjects,
  'noArchivedProjects': (strings) => strings.noArchivedProjects,
  'projectPhotoCount': (strings) => strings.projectPhotoCount(3),
  'noCaptureRecordsYet': (strings) => strings.noCaptureRecordsYet,
  'mediaFailureRecordMissing': (strings) =>
      strings.captureMediaFailure(CaptureMediaFailure.recordMissing),
  'mediaFailureClearStatus': (strings) =>
      strings.captureMediaFailure(CaptureMediaFailure.clearStatusNotAllowed),
  'mediaFailureDeleteStatus': (strings) =>
      strings.captureMediaFailure(CaptureMediaFailure.deleteStatusNotAllowed),
  'mediaFailureRepublishStatus': (strings) => strings.captureMediaFailure(
    CaptureMediaFailure.republishStatusNotAllowed,
  ),
  'mediaFailureOriginalMissing': (strings) =>
      strings.captureMediaFailure(CaptureMediaFailure.originalMissing),
  'mediaFailureRenderedMissing': (strings) =>
      strings.captureMediaFailure(CaptureMediaFailure.renderedPhotoMissing),
  'mediaFailureOperationFailed': (strings) =>
      strings.captureMediaFailure(CaptureMediaFailure.operationFailed),
};

const expectedZh = <String, String>{
  'recentlyUsed': '最近使用',
  'more': '更多',
  'searchHistory': '搜索历史',
  'noRecentSuggestions': '暂无历史',
  'suggestionsLoadFailed': '加载失败',
  'captureTemplates': '模板',
  'captureTemplateCreate': '保存当前内容',
  'captureTemplateName': '模板名称',
  'captureTemplateEmpty': '暂无模板',
  'captureTemplateApplied': '已应用模板',
  'captureTemplateLoadFailed': '模板加载失败',
  'captureTemplateSaveFailed': '模板保存失败，请重试。',
  'captureTemplateRenameFailed': '模板重命名失败，请重试。',
  'captureTemplateDeleteFailed': '模板删除失败，请重试。',
  'captureTemplateDeleteTitle': '删除此模板？',
  'captureTemplateDeleteNotice': '只会删除此模板，不会影响照片或当前已填写的表单。',
  'captureTemplateRename': '重命名',
  'captureTemplateEmptyName': '请输入模板名称',
  'captureTemplateNameTooLong': '模板名称过长',
  'captureTemplateEmptyWorkLocation': '工程部位不能为空',
  'captureTemplateWorkLocationTooLong': '工程部位过长',
  'captureTemplateEmptyWorkContent': '工作内容不能为空',
  'captureTemplateWorkContentTooLong': '工作内容过长',
  'captureTemplateEmptyPhotographer': '拍摄人不能为空',
  'captureTemplatePhotographerTooLong': '拍摄人过长',
  'captureTemplateDuplicateName': '已存在同名模板',
  'captureTemplateLimitReached': '此项目已达到 100 个模板上限',
  'captureTemplateInvalidCharacter': '模板文字包含不支持的字符',
  'captureTemplateNotFound': '模板已不存在',
  'backupFailedFriendly': '无法读取项目数据或文件，因而无法生成备份。请重试；若仍失败，请逐个项目备份。',
  'importFailedFriendly':
      '无法导入该项目。请选择有效的 SiteMark 项目备份后重试；若仍失败，请释放存储空间或换用其他备份。',
  'backupProjectFailed': '无法备份项目“Project Alpha”。请重试；若仍失败，请单独选择该项目备份。',
  'backupStorageInsufficient': '存储空间不足，无法完成操作。请释放空间后重试。',
  'backupCorrupted': '备份已损坏或校验不一致。请选择其他 SiteMark 备份后重试。',
  'backupNotSiteMark': '所选 ZIP 不是 SiteMark 导出的项目备份。请选择由 SiteMark“备份项目”生成的 ZIP。',
  'backupUnsupportedVersion': '此备份版本高于当前应用支持范围。请先升级 SiteMark，再重新选择该备份。',
  'backupSelectionNotRestorable':
      '所选 ZIP 是照片分享包，不含可恢复的项目数据。请选择通过“备份项目”生成的 ZIP。',
  'backupRestoreNameConflict': '恢复项目名称与现有项目或本次所选名称冲突。请重新开始恢复，并在预览中修改冲突名称后再恢复。',
  'restoreFinalizationPending': '恢复数据已安全保存，但尚未完成显示。请重启 SiteMark，应用会自动完成恢复。',
  'restoreFailedRollback':
      '一个或多个项目恢复失败，本次更改已全部回滚。请重新选择原备份进行恢复；若仍失败，请改用单项目备份逐个恢复。',
  'restoreFailedGeneral': '恢复过程中发生错误，未能完成恢复。请重新选择备份进行恢复；若仍失败，请改用单项目备份逐个恢复。',
  'captureOriginalMissing': '原图已缺失，无法生成水印照片。请返回项目重新拍摄；也可保留此失败记录，或从右上角菜单删除记录。',
  'captureOriginalModified':
      '原图内容与拍摄时校验值不一致，处理已停止。请保留现有原图作为证据并重新拍摄，或从右上角菜单删除此失败记录。',
  'captureProcessingFailed': '照片处理失败，但原图仍保留。请点击“重新处理”；若仍失败，请保留原图并重新拍摄。',
  'captureUnexpectedFailure': '照片因未知原因处理失败。若原图仍保留，请点击“重新处理”；否则请重新拍摄。',
  'captureListLoadFailed': '无法读取本机拍摄记录，请重试。',
  'projectStatusActive': '进行中',
  'projectStatusCompleted': '已完成',
  'projectStatusArchived': '已归档',
  'pinProject': '置顶',
  'unpinProject': '取消置顶',
  'markProjectCompleted': '标记完成',
  'archiveProject': '归档',
  'reopenProject': '重新启用',
  'restoreProjectToActive': '恢复使用',
  'projectLifecycleConflict': '项目状态已变化，请重试',
  'viewArchivedProjects': '查看归档项目',
  'noActiveProjects': '暂无进行中的项目',
  'noCompletedProjects': '暂无已完成的项目',
  'noArchivedProjects': '暂无已归档的项目',
  'projectPhotoCount': '3 张照片',
  'noCaptureRecordsYet': '暂无拍摄记录',
  'mediaFailureRecordMissing': '拍摄记录不存在',
  'mediaFailureClearStatus': '仅可清除就绪或失败记录的原始照片',
  'mediaFailureDeleteStatus': '仅可删除就绪或失败状态的记录',
  'mediaFailureRepublishStatus': '仅可就绪状态的记录重新发布',
  'mediaFailureOriginalMissing': '原图意外缺失，无法完成操作',
  'mediaFailureRenderedMissing': '水印照片文件缺失',
  'mediaFailureOperationFailed': '操作失败，请重试。',
};

const expectedEn = <String, String>{
  'recentlyUsed': 'Recently used',
  'more': 'More',
  'searchHistory': 'Search history',
  'noRecentSuggestions': 'No history',
  'suggestionsLoadFailed': 'Could not load suggestions',
  'captureTemplates': 'Templates',
  'captureTemplateCreate': 'Save current',
  'captureTemplateName': 'Template name',
  'captureTemplateEmpty': 'No templates yet',
  'captureTemplateApplied': 'Template applied',
  'captureTemplateLoadFailed': 'Could not load templates',
  'captureTemplateSaveFailed': 'Could not save template. Try again.',
  'captureTemplateRenameFailed': 'Could not rename template. Try again.',
  'captureTemplateDeleteFailed': 'Could not delete template. Try again.',
  'captureTemplateDeleteTitle': 'Delete this template?',
  'captureTemplateDeleteNotice':
      'Only this template will be deleted. Photos and the current form are not affected.',
  'captureTemplateRename': 'Rename',
  'captureTemplateEmptyName': 'Enter a template name',
  'captureTemplateNameTooLong': 'Template name is too long',
  'captureTemplateEmptyWorkLocation': 'Work location is required',
  'captureTemplateWorkLocationTooLong': 'Work location is too long',
  'captureTemplateEmptyWorkContent': 'Work content is required',
  'captureTemplateWorkContentTooLong': 'Work content is too long',
  'captureTemplateEmptyPhotographer': 'Photographer is required',
  'captureTemplatePhotographerTooLong': 'Photographer is too long',
  'captureTemplateDuplicateName': 'A template with this name already exists',
  'captureTemplateLimitReached': 'This project already has 100 templates',
  'captureTemplateInvalidCharacter':
      'Template text cannot contain unsupported characters',
  'captureTemplateNotFound': 'Template no longer exists',
  'backupFailedFriendly':
      'Project data or files could not be read, so the backup was not created. Try again; if it still fails, back up one project at a time.',
  'importFailedFriendly':
      'Could not import the project. Choose a valid SiteMark project backup and try again; if it still fails, free some storage space or use another backup.',
  'backupProjectFailed':
      'Could not back up "Project Alpha". Try again; if it still fails, select only this project and retry.',
  'backupStorageInsufficient':
      'Not enough storage space to complete this operation. Free some space and try again.',
  'backupCorrupted':
      'The backup is corrupted or its checksum does not match. Choose another SiteMark backup and try again.',
  'backupNotSiteMark':
      'The selected ZIP is not a project backup exported by SiteMark. Choose a ZIP created with Back up projects in SiteMark.',
  'backupUnsupportedVersion':
      'This backup is newer than this app can read. Update SiteMark, then choose the backup again.',
  'backupSelectionNotRestorable':
      'The selected ZIP is a photo-sharing archive and contains no restorable project data. Choose a ZIP created with Back up projects.',
  'backupRestoreNameConflict':
      'A restore project name conflicts with an existing project or another selected name. Start restore again, change each conflicting name in the preview, then restore.',
  'restoreFinalizationPending':
      'Restore data is safely saved but is not visible yet. Restart SiteMark to finish the restore automatically.',
  'restoreFailedRollback':
      'One or more projects could not be restored, so all changes from this restore were rolled back. Choose the original backup and restore again; if it still fails, restore single-project backups one at a time.',
  'restoreFailedGeneral':
      'An error prevented the restore from completing. Choose the backup and restore again; if it still fails, restore single-project backups one at a time.',
  'captureOriginalMissing':
      'The original is missing, so the watermarked photo cannot be created. Return to the project and take the photo again; you can keep this failed record or delete it from the top-right menu.',
  'captureOriginalModified':
      'The original does not match its capture-time checksum, so processing stopped. Keep the current original as evidence and take the photo again, or delete this failed record from the top-right menu.',
  'captureProcessingFailed':
      'Photo processing failed, but the original is retained. Select Retry processing; if it still fails, keep the original and take the photo again.',
  'captureUnexpectedFailure':
      'The photo could not be processed for an unknown reason. If the original is retained, select Retry processing; otherwise take the photo again.',
  'captureListLoadFailed':
      'Local capture records could not be read. Please try again.',
  'projectStatusActive': 'Active',
  'projectStatusCompleted': 'Completed',
  'projectStatusArchived': 'Archived',
  'pinProject': 'Pin project',
  'unpinProject': 'Unpin project',
  'markProjectCompleted': 'Mark completed',
  'archiveProject': 'Archive',
  'reopenProject': 'Reopen project',
  'restoreProjectToActive': 'Restore to active',
  'projectLifecycleConflict': 'Project status changed. Please try again.',
  'viewArchivedProjects': 'View archived projects',
  'noActiveProjects': 'No active projects',
  'noCompletedProjects': 'No completed projects yet',
  'noArchivedProjects': 'No archived projects yet',
  'projectPhotoCount': '3 photos',
  'noCaptureRecordsYet': 'No captures yet',
  'mediaFailureRecordMissing': 'Capture record does not exist',
  'mediaFailureClearStatus':
      'Only ready or failed captures can have originals cleared',
  'mediaFailureDeleteStatus': 'Only ready or failed captures can be deleted',
  'mediaFailureRepublishStatus': 'Only ready captures can be republished',
  'mediaFailureOriginalMissing': 'Original photo is unexpectedly missing',
  'mediaFailureRenderedMissing': 'Rendered photo is missing',
  'mediaFailureOperationFailed': 'Operation failed. Please try again.',
};

void main() {
  testWidgets('zh_CN resolves through app delegates to every exact string', (
    tester,
  ) async {
    final snapshot = await _pumpLocalizedSnapshot(
      tester,
      const Locale('zh', 'CN'),
    );

    _expectSnapshot(snapshot, languageCode: 'zh', expected: expectedZh);
  });

  testWidgets('en_US resolves through app delegates to every exact string', (
    tester,
  ) async {
    final snapshot = await _pumpLocalizedSnapshot(
      tester,
      const Locale('en', 'US'),
    );

    _expectSnapshot(snapshot, languageCode: 'en', expected: expectedEn);
  });

  testWidgets('regional Chinese and unsupported locales use app fallback', (
    tester,
  ) async {
    for (final requestedLocale in const [
      Locale('zh', 'TW'),
      Locale('fr', 'FR'),
    ]) {
      final snapshot = await _pumpLocalizedSnapshot(tester, requestedLocale);

      _expectSnapshot(snapshot, languageCode: 'zh', expected: expectedZh);
    }
  });

  test('delegate supports exactly the declared real app locales', () {
    expect(AppStrings.delegate.isSupported(const Locale('zh')), isTrue);
    expect(AppStrings.delegate.isSupported(const Locale('en')), isTrue);
    expect(AppStrings.delegate.isSupported(const Locale('fr')), isFalse);
    expect(AppStrings.supportedLocales, const [Locale('zh'), Locale('en')]);
  });

  test(
    'media operation failure strings never expose raw exceptions or paths',
    () {
      // Leak markers only: exception type names and private file-path roots.
      const forbidden = [
        'FileSystemException',
        'StateError',
        '/data/',
        '/storage/emulated',
      ];
      for (final locale in const [Locale('zh'), Locale('en')]) {
        final strings = AppStrings(locale);
        for (final failure in CaptureMediaFailure.values) {
          final text = strings.captureMediaFailure(failure);
          expect(
            text,
            isNotEmpty,
            reason: '$locale/$failure must be localized',
          );
          for (final marker in forbidden) {
            expect(text, isNot(contains(marker)), reason: '$locale/$failure');
          }
        }
      }
    },
  );
}

Future<_LocalizedSnapshot> _pumpLocalizedSnapshot(
  WidgetTester tester,
  Locale locale,
) async {
  late _LocalizedSnapshot snapshot;
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(
        builder: (context) {
          final strings = AppStrings.of(context);
          snapshot = (
            locale: strings.locale,
            values: {
              for (final entry in _stringReaders.entries)
                entry.key: entry.value(strings),
            },
          );
          final cupertino = CupertinoLocalizations.of(context);
          return CupertinoButton(
            onPressed: () {},
            child: Text(
              '${strings.captureTemplates}:${cupertino.cancelButtonLabel}',
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  expect(find.byType(CupertinoButton), findsOneWidget);
  return snapshot;
}

void _expectSnapshot(
  _LocalizedSnapshot snapshot, {
  required String languageCode,
  required Map<String, String> expected,
}) {
  expect(snapshot.locale.languageCode, languageCode);
  expect(_stringReaders.keys.toSet(), expected.keys.toSet());
  for (final entry in expected.entries) {
    expect(snapshot.values[entry.key], entry.value, reason: entry.key);
  }
}
