// lib/features/settings/sections/appearance_section_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sitemark/features/settings/accent_choice_chip.dart';
import 'package:sitemark/features/settings/app_setting_controller.dart';
import 'package:sitemark/features/settings/settings_section_scaffold.dart';
import 'package:sitemark/l10n/app_strings.dart';

class AppearanceSectionScreen extends ConsumerWidget {
  const AppearanceSectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppStrings.of(context);
    final asyncSettings = ref.watch(appSettingControllerProvider);
    final settings = asyncSettings.value;
    if (settings == null) {
      return SettingsSectionScaffold(
        title: strings.appearance,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return SettingsSectionScaffold(
      title: strings.appearance,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(strings.theme, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            key: const Key('theme-segmented'),
            style: segmentTapTargetStyle,
            segments: [
              ButtonSegment(
                value: 'system',
                label: Text(strings.systemTheme, key: const Key('theme-system')),
              ),
              ButtonSegment(
                value: 'light',
                label: Text(strings.lightTheme, key: const Key('theme-light')),
              ),
              ButtonSegment(
                value: 'dark',
                label: Text(strings.darkTheme, key: const Key('theme-dark')),
              ),
            ],
            selected: {settings.themeMode},
            onSelectionChanged: (selection) => ref
                .read(appSettingControllerProvider.notifier)
                .update((s) => s.copyWith(themeMode: selection.single)),
          ),
          const SizedBox(height: 8),
          if (!settings.useDynamicColor) ...[
            const SizedBox(height: 12),
            Text(strings.appThemeColor,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final swatch in accentSwatches)
                  AccentChoiceChip(
                    argb: swatch.argb,
                    label: accentLabel(strings, swatch.argb),
                    selected: settings.appSeedColorArgb == swatch.argb,
                    onSelected: () => ref
                        .read(appSettingControllerProvider.notifier)
                        .update((s) =>
                            s.copyWith(appSeedColorArgb: swatch.argb)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          SwitchListTile(
            key: const Key('dynamic-color-switch'),
            title: Text(strings.dynamicColorTitle),
            subtitle: Text(strings.dynamicColorSubtitle),
            value: settings.useDynamicColor,
            onChanged: (value) => ref
                .read(appSettingControllerProvider.notifier)
                .update((s) => s.copyWith(useDynamicColor: value)),
          ),
        ],
      ),
    );
  }
}
