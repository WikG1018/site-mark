import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/l10n/app_strings.dart';

/// 二级菜单入口的设置页。原 805 行的单体屏幕已拆分为 7 个独立子页面，
/// 通过 [context.go] 跳转到对应的二级路由（路由在 `lib/app.dart` 中由
/// Task 11 注册）。
class GlobalSettingsScreen extends StatelessWidget {
  const GlobalSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final entries = <(IconData, String, String)>[
      (
        Icons.water_drop_outlined,
        strings.newProjectDefaults,
        '/settings/watermark',
      ),
      (Icons.palette_outlined, strings.appearance, '/settings/appearance'),
      (Icons.language, strings.language, '/settings/language'),
      (Icons.storage_outlined, strings.storageMenuLabel, '/settings/storage'),
      (Icons.location_on_outlined, strings.locationLabel, '/settings/location'),
      (
        Icons.notifications_outlined,
        strings.completionNotificationTitle,
        '/settings/notification',
      ),
      (Icons.info_outline, strings.about, '/settings/about'),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(strings.settings)),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final (icon, title, route) = entries[index];
          return Card(
            child: ListTile(
              leading: Icon(icon),
              title: Text(title),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(route),
            ),
          );
        },
      ),
    );
  }
}
