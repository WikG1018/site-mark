// lib/features/settings/sections/notification_section_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sitemark/features/settings/app_setting_controller.dart';
import 'package:sitemark/features/settings/settings_section_scaffold.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/platform/notification_service.dart';

class NotificationSectionScreen extends ConsumerWidget {
  const NotificationSectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppStrings.of(context);
    final asyncSettings = ref.watch(appSettingControllerProvider);
    final settings = asyncSettings.value;
    if (settings == null) {
      return SettingsSectionScaffold(
        title: strings.completionNotificationTitle,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return SettingsSectionScaffold(
      title: strings.completionNotificationTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            key: const Key('completion-notification-switch'),
            title: Text(strings.completionNotificationTitle),
            subtitle: Text(strings.completionNotificationSubtitle),
            value: settings.completionNotificationsEnabled,
            onChanged: (value) =>
                _onCompletionNotificationChanged(context, ref, value),
          ),
        ],
      ),
    );
  }

  Future<void> _onCompletionNotificationChanged(
    BuildContext context,
    WidgetRef ref,
    bool value,
  ) async {
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
    if (!context.mounted) return;
    if (granted) {
      await ref
          .read(appSettingControllerProvider.notifier)
          .update((s) => s.copyWith(completionNotificationsEnabled: true));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context).notificationPermissionDenied),
        ),
      );
    }
  }
}
