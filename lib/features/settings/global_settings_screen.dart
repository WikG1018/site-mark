import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/domain/app_storage_usage.dart';
import 'package:sitemark/features/settings/app_setting_controller.dart';
import 'package:sitemark/features/settings/settings_group.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/navigation/scroll_chrome.dart';
import 'package:sitemark/platform/notification_service.dart';
import 'package:sitemark/shared/ui/adaptive_toast.dart';
import 'package:sitemark/shared/ui/floating_dock_layout.dart';
import 'package:sitemark/shared/ui/adaptive_page_scaffold.dart';
import 'package:sitemark/workflow/location_permission_service.dart';
import 'package:sitemark_system_api/sitemark_system_api.dart';

class GlobalSettingsScreen extends ConsumerStatefulWidget {
  const GlobalSettingsScreen({super.key});

  @override
  ConsumerState<GlobalSettingsScreen> createState() =>
      _GlobalSettingsScreenState();
}

class _GlobalSettingsScreenState extends ConsumerState<GlobalSettingsScreen> {
  bool _requestingLocation = false;

  Future<void> _onLocationChanged(bool value) async {
    if (_requestingLocation) return;
    if (!value) {
      await ref
          .read(appSettingControllerProvider.notifier)
          .update((s) => s.copyWith(locationCaptureEnabled: false));
      return;
    }
    setState(() => _requestingLocation = true);
    try {
      final service = ref.read(locationPermissionServiceProvider);
      LocationPermissionViewState state;
      try {
        state = await service.load();
      } catch (_) {
        state = LocationPermissionViewState(
          permission: LocationPermissionState.denied,
          showExplanation: false,
        );
      }
      if (!state.locationEnabled) {
        if (state.openSettings) {
          await service.openSettings();
          try {
            state = await service.load();
          } catch (_) {}
        } else {
          try {
            state = await service.request();
          } catch (_) {}
        }
      }
      if (!mounted) return;
      await ref
          .read(appSettingControllerProvider.notifier)
          .update(
            (s) => s.copyWith(locationCaptureEnabled: state.locationEnabled),
          );
      if (!state.locationEnabled && mounted) {
        showAppToast(context, AppStrings.of(context).locationDisabledHint);
      }
    } finally {
      if (mounted) {
        setState(() => _requestingLocation = false);
      }
    }
  }

  Future<void> _onCompletionNotificationChanged(bool value) async {
    if (!value) {
      await ref
          .read(appSettingControllerProvider.notifier)
          .update((s) => s.copyWith(completionNotificationsEnabled: false));
      return;
    }
    var granted = true;
    try {
      granted = await ref
          .read(completionNotificationServiceProvider)
          .requestPermission();
    } on UnimplementedError {
      granted = true;
    }
    if (!mounted) return;
    if (granted) {
      await ref
          .read(appSettingControllerProvider.notifier)
          .update((s) => s.copyWith(completionNotificationsEnabled: true));
    } else {
      showAppToast(
        context,
        AppStrings.of(context).notificationPermissionDenied,
      );
    }
  }

  Future<void> _onAutoPublishChanged(bool value) async {
    await ref
        .read(appSettingControllerProvider.notifier)
        .update((s) => s.copyWith(autoPublishToGallery: value));
  }

  @override
  Widget build(BuildContext context) {
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
    final storageSummary = storageUsage == null
        ? null
        : formatStorageBytes(storageUsage.totalBytes);

    return AdaptivePageScaffold.raw(
      hideOnScroll: true,
      title: strings.settings,
      iosBodyPadding: EdgeInsets.zero,
      body: Builder(
        builder: (context) => ListView(
          padding: EdgeInsets.fromLTRB(
            12,
            scrollChromeTopInsetOf(context),
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
                SettingsSwitchEntry(
                  key: const Key('settings-entry-location'),
                  icon: Icons.location_on_outlined,
                  title: strings.locationLabel,
                  subtitle: strings.locationCaptureSubtitle,
                  value: settings?.locationCaptureEnabled ?? false,
                  enabled: settings != null && !_requestingLocation,
                  onChanged: settings == null ? null : _onLocationChanged,
                ),
                SettingsSwitchEntry(
                  key: const Key('settings-entry-notification'),
                  icon: Icons.notifications_outlined,
                  title: strings.completionNotificationTitle,
                  subtitle: strings.completionNotificationSubtitle,
                  value: settings?.completionNotificationsEnabled ?? false,
                  enabled: settings != null,
                  onChanged: settings == null
                      ? null
                      : _onCompletionNotificationChanged,
                ),
                SettingsSwitchEntry(
                  key: const Key('settings-entry-auto-publish-gallery'),
                  icon: Icons.add_to_photos_outlined,
                  title: strings.autoPublishToGalleryTitle,
                  subtitle: strings.autoPublishToGallerySubtitle,
                  value: settings?.autoPublishToGallery ?? true,
                  enabled: settings != null,
                  onChanged: settings == null ? null : _onAutoPublishChanged,
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
