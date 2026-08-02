import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/l10n/app_strings.dart';

void main() {
  test(
    'capture reuse and backup messages are complete in Chinese and English',
    () {
      const zh = AppStrings(Locale('zh'));
      const en = AppStrings(Locale('en'));
      final messages =
          <({String label, String Function(AppStrings strings) read})>[
            (label: 'recently used', read: (strings) => strings.recentlyUsed),
            (label: 'more suggestions', read: (strings) => strings.more),
            (label: 'search history', read: (strings) => strings.searchHistory),
            (
              label: 'empty suggestions',
              read: (strings) => strings.noRecentSuggestions,
            ),
            (
              label: 'suggestion load failure',
              read: (strings) => strings.suggestionsLoadFailed,
            ),
            (label: 'templates', read: (strings) => strings.captureTemplates),
            (
              label: 'create template',
              read: (strings) => strings.captureTemplateCreate,
            ),
            (
              label: 'template name',
              read: (strings) => strings.captureTemplateName,
            ),
            (
              label: 'empty templates',
              read: (strings) => strings.captureTemplateEmpty,
            ),
            (
              label: 'template applied',
              read: (strings) => strings.captureTemplateApplied,
            ),
            (
              label: 'template load failure',
              read: (strings) => strings.captureTemplateLoadFailed,
            ),
            (
              label: 'template save failure',
              read: (strings) => strings.captureTemplateSaveFailed,
            ),
            (
              label: 'template rename failure',
              read: (strings) => strings.captureTemplateRenameFailed,
            ),
            (
              label: 'template delete failure',
              read: (strings) => strings.captureTemplateDeleteFailed,
            ),
            (
              label: 'template delete title',
              read: (strings) => strings.captureTemplateDeleteTitle,
            ),
            (
              label: 'template delete notice',
              read: (strings) => strings.captureTemplateDeleteNotice,
            ),
            (
              label: 'template rename',
              read: (strings) => strings.captureTemplateRename,
            ),
            (
              label: 'empty template name',
              read: (strings) => strings.captureTemplateEmptyName,
            ),
            (
              label: 'long template name',
              read: (strings) => strings.captureTemplateNameTooLong,
            ),
            (
              label: 'empty work location',
              read: (strings) => strings.captureTemplateEmptyWorkLocation,
            ),
            (
              label: 'long work location',
              read: (strings) => strings.captureTemplateWorkLocationTooLong,
            ),
            (
              label: 'empty work content',
              read: (strings) => strings.captureTemplateEmptyWorkContent,
            ),
            (
              label: 'long work content',
              read: (strings) => strings.captureTemplateWorkContentTooLong,
            ),
            (
              label: 'empty photographer',
              read: (strings) => strings.captureTemplateEmptyPhotographer,
            ),
            (
              label: 'long photographer',
              read: (strings) => strings.captureTemplatePhotographerTooLong,
            ),
            (
              label: 'duplicate template',
              read: (strings) => strings.captureTemplateDuplicateName,
            ),
            (
              label: 'template limit',
              read: (strings) => strings.captureTemplateLimitReached,
            ),
            (
              label: 'invalid character',
              read: (strings) => strings.captureTemplateInvalidCharacter,
            ),
            (
              label: 'template not found',
              read: (strings) => strings.captureTemplateNotFound,
            ),
            (
              label: 'backup failure',
              read: (strings) => strings.backupFailedFriendly,
            ),
            (
              label: 'project backup failure',
              read: (strings) => strings.backupProjectFailed('示例项目'),
            ),
            (
              label: 'storage space',
              read: (strings) => strings.backupStorageInsufficient,
            ),
          ];

      for (final message in messages) {
        final chinese = message.read(zh);
        final english = message.read(en);
        expect(chinese.trim(), isNotEmpty, reason: '${message.label} zh');
        expect(english.trim(), isNotEmpty, reason: '${message.label} en');
        expect(
          english,
          isNot(chinese),
          reason: '${message.label} locale fallback',
        );
      }
      expect(zh.backupProjectFailed('示例项目'), contains('示例项目'));
      expect(
        en.backupProjectFailed('Example project'),
        contains('Example project'),
      );
    },
  );

  test('delegate supports exactly the declared real app locales', () {
    expect(AppStrings.delegate.isSupported(const Locale('zh')), isTrue);
    expect(AppStrings.delegate.isSupported(const Locale('en')), isTrue);
    expect(AppStrings.delegate.isSupported(const Locale('fr')), isFalse);
    expect(AppStrings.supportedLocales, const [Locale('zh'), Locale('en')]);
  });
}
