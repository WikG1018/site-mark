import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/domain/app_storage_usage.dart';
import 'package:sitemark/features/settings/settings_group.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/shared/ui/floating_dock_layout.dart';
import 'package:sitemark/shared/ui/adaptive_page_scaffold.dart';

class GlobalSettingsScreen extends ConsumerWidget {
  const GlobalSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppStrings.of(context);
    final settings = _settledValue(ref.watch(appSettingsProvider));
    final storageUsage = _settledValue(ref.watch(storageUsageProvider));
    final languageSummary = settings == null
        ? null
        : switch (settings.localeCode) {
            'zh' => strings.chinese,
            'en' => strings.english,
            _ => strings.systemLanguage,
          };
    final notificationSummary = settings == null
        ? null
        : settings.completionNotificationsEnabled
        ? strings.enabled
        : strings.disabled;
    final storageSummary = storageUsage == null
        ? null
        : formatStorageBytes(storageUsage.totalBytes);

    return AdaptivePageScaffold.raw(
      title: strings.settings,
      iosBodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          12,
          0,
          12,
          floatingDockReservedSpaceOf(context),
        ),
        children: [
          SettingsGroup(
            key: const Key('settings-group-capture'),
            title: strings.settingsCaptureAndRecords,
            children: [
              SettingsEntry(
                key: const Key('settings-entry-watermark'),
                icon: Icons.water_drop_outlined,
                title: strings.newProjectDefaults,
                route: '/settings/watermark',
              ),
              SettingsEntry(
                key: const Key('settings-entry-location'),
                icon: Icons.location_on_outlined,
                title: strings.locationLabel,
                route: '/settings/location',
              ),
              SettingsEntry(
                key: const Key('settings-entry-notification'),
                icon: Icons.notifications_outlined,
                title: strings.completionNotificationTitle,
                subtitle: notificationSummary,
                reserveSubtitleSpace: true,
                route: '/settings/notification',
              ),
            ],
          ),
          SettingsGroup(
            key: const Key('settings-group-data'),
            title: strings.settingsDataAndSafety,
            children: [
              SettingsEntry(
                key: const Key('backup-restore-menu'),
                icon: Icons.settings_backup_restore_outlined,
                title: strings.backupAndRestore,
                route: '/settings/backup-restore',
              ),
              SettingsEntry(
                key: const Key('settings-entry-storage'),
                icon: Icons.storage_outlined,
                title: strings.storageMenuLabel,
                subtitle: storageSummary,
                reserveSubtitleSpace: true,
                route: '/settings/storage',
              ),
              SettingsEntry(
                key: const Key('settings-entry-nas-sync'),
                icon: Icons.dns_outlined,
                title: strings.nasSync,
                subtitle: strings.nasSyncSubtitle,
                reserveSubtitleSpace: true,
                route: '/settings/nas-sync',
              ),
              SettingsEntry(
                key: const Key('settings-entry-diagnostics'),
                icon: Icons.health_and_safety_outlined,
                title: strings.diagnosticsAndFeedback,
                route: '/settings/diagnostics',
              ),
            ],
          ),
          SettingsGroup(
            key: const Key('settings-group-app'),
            title: strings.settingsApplication,
            children: [
              SettingsEntry(
                key: const Key('settings-entry-appearance'),
                icon: Icons.palette_outlined,
                title: strings.appearance,
                route: '/settings/appearance',
              ),
              SettingsEntry(
                key: const Key('settings-entry-language'),
                icon: Icons.language,
                title: strings.language,
                subtitle: languageSummary,
                reserveSubtitleSpace: true,
                route: '/settings/language',
              ),
              SettingsEntry(
                key: const Key('settings-entry-about'),
                icon: Icons.info_outline,
                title: strings.about,
                route: '/settings/about',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

T? _settledValue<T>(AsyncValue<T> state) {
  return switch (state) {
    AsyncData<T>(:final value) when !state.isLoading => value,
    _ => null,
  };
}
