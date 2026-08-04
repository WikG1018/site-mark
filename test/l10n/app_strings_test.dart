import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
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
  'backupProjectFailed': (strings) => strings.backupProjectFailed(_projectName),
  'backupStorageInsufficient': (strings) => strings.backupStorageInsufficient,
  'backupCorrupted': (strings) => strings.backupCorrupted,
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
  'backupProjectFailed': '无法备份项目“Project Alpha”。请重试；若仍失败，请单独选择该项目备份。',
  'backupStorageInsufficient': '存储空间不足，无法完成操作。请释放空间后重试。',
  'backupCorrupted': '备份已损坏或校验不一致。请选择其他 SiteMark 备份后重试。',
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
  'backupProjectFailed':
      'Could not back up "Project Alpha". Try again; if it still fails, select only this project and retry.',
  'backupStorageInsufficient':
      'Not enough storage space to complete this operation. Free some space and try again.',
  'backupCorrupted':
      'The backup is corrupted or its checksum does not match. Choose another SiteMark backup and try again.',
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
