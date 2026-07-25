// lib/features/settings/sections/language_section_screen.dart
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sitemark/features/settings/app_setting_controller.dart';
import 'package:sitemark/features/settings/settings_section_scaffold.dart';
import 'package:sitemark/l10n/app_strings.dart';

class LanguageSectionScreen extends ConsumerWidget {
  const LanguageSectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppStrings.of(context);
    final asyncSettings = ref.watch(appSettingControllerProvider);
    final settings = asyncSettings.value;
    if (settings == null) {
      return SettingsSectionScaffold(
        title: strings.language,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return SettingsSectionScaffold(
      title: strings.language,
      body: SegmentedButton<String?>(
        key: const Key('language-segmented'),
        style: segmentTapTargetStyle,
        segments: [
          ButtonSegment(
            value: null,
            label: Text(strings.systemLanguage, key: const Key('language-system')),
          ),
          ButtonSegment(
            value: 'zh',
            label: Text(strings.chinese, key: const Key('language-zh')),
          ),
          ButtonSegment(
            value: 'en',
            label: Text(strings.english, key: const Key('language-en')),
          ),
        ],
        selected: {
          (settings.localeCode?.isEmpty ?? true) ? null : settings.localeCode,
        },
        onSelectionChanged: (selection) => ref
            .read(appSettingControllerProvider.notifier)
            .update((s) => s.copyWith(localeCode: Value(selection.single ?? ''))),
      ),
    );
  }
}
