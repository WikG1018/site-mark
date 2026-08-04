## Commit list

0949bc2 feat: rewrite settings screen as secondary menu

## Diff stat

 lib/features/settings/global_settings_screen.dart  | 813 +--------------------
 .../settings/global_settings_screen_test.dart      | 647 ++--------------
 2 files changed, 68 insertions(+), 1392 deletions(-)

## Full diff

diff --git a/lib/features/settings/global_settings_screen.dart b/lib/features/settings/global_settings_screen.dart
index 26b549d..1c450c0 100644
--- a/lib/features/settings/global_settings_screen.dart
+++ b/lib/features/settings/global_settings_screen.dart
@@ -1,805 +1,42 @@
 import 'package:flutter/material.dart';
-import 'package:flutter_riverpod/flutter_riverpod.dart';
 import 'package:go_router/go_router.dart';
-import 'package:package_info_plus/package_info_plus.dart';
-import 'package:sitemark/app.dart';
-import 'package:sitemark/data/app_database.dart';
-import 'package:sitemark/domain/app_links.dart';
-import 'package:sitemark/domain/app_storage_usage.dart';
 import 'package:sitemark/l10n/app_strings.dart';
-import 'package:sitemark/platform/notification_service.dart';
-import 'package:sitemark/workflow/location_permission_service.dart';
-import 'package:sitemark_system_api/sitemark_system_api.dart';
 
-/// Fallback version/build used when [PackageInfo.fromPlatform] fails (e.g. in
-/// unit tests where no platform plugin is available).
-const _fallbackVersion = '0.4.0';
-const _fallbackBuild = '4';
-
-/// Accent swatches offered as new-project watermark defaults. Order matches
-/// the project-level watermark settings screen for visual consistency.
-const _accentSwatches = <({int argb, Key key})>[
-  (argb: 0xff37c58b, key: Key('accent-green')),
-  (argb: 0xff1565c0, key: Key('accent-blue')),
-  (argb: 0xffef6c00, key: Key('accent-orange')),
-];
-
-/// Segmented buttons default to a 40dp minimum height, below Android's 48dp
-/// tap-target guideline; lifting the floor keeps the settings page compliant.
-const _segmentTapTargetStyle = ButtonStyle(
-  minimumSize: WidgetStatePropertyAll<Size>(Size.fromHeight(48)),
-);
-
-class GlobalSettingsScreen extends ConsumerStatefulWidget {
+/// 二级菜单入口的设置页。原 805 行的单体屏幕已拆分为 7 个独立子页面，
+/// 通过 [context.go] 跳转到对应的二级路由（路由在 `lib/app.dart` 中由
+/// Task 11 注册）。
+class GlobalSettingsScreen extends StatelessWidget {
   const GlobalSettingsScreen({super.key});
 
-  @override
-  ConsumerState<GlobalSettingsScreen> createState() =>
-      _GlobalSettingsScreenState();
-}
-
-class _GlobalSettingsScreenState extends ConsumerState<GlobalSettingsScreen>
-    with WidgetsBindingObserver {
-  late final Future<AppSetting> _initialSettings;
-  AppSetting? _settings;
-  String _version = _fallbackVersion;
-  String _buildNumber = _fallbackBuild;
-  // Tracks the opacity slider position during an active drag so the thumb and
-  // percentage label follow the finger. Cleared on `onChangeEnd` (where the
-  // value is persisted); `null` means "not dragging - show the persisted value".
-  double? _dragValue;
-  // Tracks the font-scale slider position during an active drag so the thumb
-  // and percentage label follow the finger. Cleared on `onChangeEnd` (where
-  // the value is persisted); `null` means "not dragging - show the persisted
-  // value".
-  double? _fontScaleDragValue;
-
-  /// Cached location-permission view state. Loaded once during initialization
-  /// and refreshed on app resume so the tile reflects permission changes the
-  /// user made in the system dialog or settings. `null` means the first load
-  /// has not finished.
-  LocationPermissionViewState? _permissionState;
-
-  @override
-  void initState() {
-    super.initState();
-    // Store the future once so a rebuild does not re-trigger the load (mirrors
-    // the project watermark settings screen's FutureBuilder pattern).
-    _initialSettings = ref.read(databaseProvider).getAppSettings();
-    _loadPackageInfo();
-    _loadPermission();
-    WidgetsBinding.instance.addObserver(this);
-  }
-
-  @override
-  void didChangeAppLifecycleState(AppLifecycleState state) {
-    super.didChangeAppLifecycleState(state);
-    // Refresh after the user returns from the system permission dialog or
-    // settings page so the tile reflects the new permission state.
-    if (state == AppLifecycleState.resumed) {
-      _loadPermission();
-    }
-  }
-
-  Future<void> _loadPermission() async {
-    try {
-      final state = await ref.read(locationPermissionServiceProvider).load();
-      if (!mounted) return;
-      setState(() => _permissionState = state);
-    } catch (_) {
-      // The platform bridge is unavailable (e.g. in unit tests without a
-      // platform override). Default to a disabled, non-explanation state so
-      // the tile renders deterministically instead of spinning forever.
-      if (!mounted) return;
-      setState(() {
-        _permissionState = const LocationPermissionViewState(
-          permission: LocationPermissionState.denied,
-          showExplanation: false,
-        );
-      });
-    }
-  }
-
-  Future<void> _onLocationTapped() async {
-    final service = ref.read(locationPermissionServiceProvider);
-    final current = _permissionState;
-    if (current == null || current.locationEnabled) return;
-    if (current.openSettings) {
-      // Route to system settings; the resumed lifecycle callback refreshes
-      // the tile when the user returns.
-      await service.openSettings();
-      return;
-    }
-    final state = await service.request();
-    if (!mounted) return;
-    setState(() => _permissionState = state);
-  }
-
-  Future<void> _loadPackageInfo() async {
-    try {
-      final info = await PackageInfo.fromPlatform();
-      if (!mounted) return;
-      setState(() {
-        _version = info.version.isEmpty ? _fallbackVersion : info.version;
-        _buildNumber = info.buildNumber.isEmpty
-            ? _fallbackBuild
-            : info.buildNumber;
-      });
-    } catch (_) {
-      // Keep the fallback constants; the About section still renders.
-    }
-  }
-
-  /// Persists [op] and applies the returned [AppSetting] to local state so the
-  /// UI reflects the new value without an always-open watch stream (which
-  /// would keep the test frame loop busy).
-  Future<void> _apply(Future<AppSetting> Function(AppDatabase db) op) async {
-    final updated = await op(ref.read(databaseProvider));
-    if (!mounted) return;
-    setState(() => _settings = updated);
-  }
-
-  Future<void> _onCompletionNotificationChanged(bool value) async {
-    if (!value) {
-      await _apply(
-        (db) => db.updateAppSettings(completionNotificationsEnabled: false),
-      );
-      return;
-    }
-    var granted = true;
-    try {
-      granted = await ref
-          .read(completionNotificationServiceProvider)
-          .requestPermission();
-    } on UnimplementedError {
-      granted = true;
-    }
-    if (!mounted) return;
-    if (granted) {
-      await _apply(
-        (db) => db.updateAppSettings(completionNotificationsEnabled: true),
-      );
-    } else {
-      ScaffoldMessenger.of(context).showSnackBar(
-        SnackBar(
-          content: Text(AppStrings.of(context).notificationPermissionDenied),
-        ),
-      );
-    }
-  }
-
-  @override
-  void dispose() {
-    WidgetsBinding.instance.removeObserver(this);
-    super.dispose();
-  }
-
-  Future<void> _openRepository(BuildContext context) async {
-    try {
-      final opened = await ref
-          .read(externalLinkServiceProvider)
-          .open(siteMarkRepositoryUri);
-      if (!opened && context.mounted) {
-        ScaffoldMessenger.of(context).showSnackBar(
-          SnackBar(content: Text(AppStrings.of(context).openLinkFailed)),
-        );
-      }
-    } catch (_) {
-      if (context.mounted) {
-        ScaffoldMessenger.of(context).showSnackBar(
-          SnackBar(content: Text(AppStrings.of(context).openLinkFailed)),
-        );
-      }
-    }
-  }
-
-  Future<void> _clearLocalExports(BuildContext context) async {
-    final strings = AppStrings.of(context);
-    final confirmed = await showDialog<bool>(
-      context: context,
-      builder: (dialogContext) => AlertDialog(
-        title: Text(strings.clearLocalExports),
-        content: Text(strings.clearLocalExportsPrompt),
-        actions: [
-          TextButton(
-            onPressed: () => Navigator.of(dialogContext).pop(false),
-            child: Text(strings.cancel),
-          ),
-          FilledButton(
-            key: const Key('confirm-clear-exports'),
-            onPressed: () => Navigator.of(dialogContext).pop(true),
-            child: Text(strings.clear),
-          ),
-        ],
-      ),
-    );
-    if (confirmed != true || !context.mounted) return;
-
-    try {
-      final result = await ref.read(storageUsageServiceProvider).clearExports();
-      ref.invalidate(storageUsageProvider);
-      if (!context.mounted) return;
-      ScaffoldMessenger.of(context).showSnackBar(
-        SnackBar(
-          content: Text(strings.localExportsCleared(result.deletedFiles)),
-        ),
-      );
-    } catch (_) {
-      if (!context.mounted) return;
-      ScaffoldMessenger.of(
-        context,
-      ).showSnackBar(SnackBar(content: Text(strings.clearLocalExportsFailed)));
-    }
-  }
-
   @override
   Widget build(BuildContext context) {
     final strings = AppStrings.of(context);
-    final storageUsage = ref.watch(storageUsageProvider);
+    final entries = <(IconData, String, String)>[
+      (Icons.water_drop_outlined, strings.newProjectDefaults, '/settings/watermark'),
+      (Icons.palette_outlined, strings.appearance, '/settings/appearance'),
+      (Icons.language, strings.language, '/settings/language'),
+      (Icons.storage_outlined, strings.storageScope, '/settings/storage'),
+      (Icons.location_on_outlined, strings.locationLabel, '/settings/location'),
+      (Icons.notifications_outlined, strings.completionNotificationTitle, '/settings/notification'),
+      (Icons.info_outline, strings.about, '/settings/about'),
+    ];
     return Scaffold(
       appBar: AppBar(title: Text(strings.settings)),
-      body: FutureBuilder<AppSetting>(
-        future: _initialSettings,
-        builder: (context, snapshot) {
-          final settings = _settings ?? snapshot.data;
-          if (settings == null) {
-            return const Center(child: CircularProgressIndicator());
-          }
-          return ListView(
-            padding: const EdgeInsets.all(20),
-            children: [
-              _SectionHeader(label: strings.appearance),
-              const SizedBox(height: 8),
-              Text(
-                strings.theme,
-                style: Theme.of(context).textTheme.titleMedium,
-              ),
-              const SizedBox(height: 8),
-              SegmentedButton<String>(
-                key: const Key('theme-segmented'),
-                style: _segmentTapTargetStyle,
-                segments: [
-                  ButtonSegment(
-                    value: 'system',
-                    label: Text(
-                      strings.systemTheme,
-                      key: const Key('theme-system'),
-                    ),
-                  ),
-                  ButtonSegment(
-                    value: 'light',
-                    label: Text(
-                      strings.lightTheme,
-                      key: const Key('theme-light'),
-                    ),
-                  ),
-                  ButtonSegment(
-                    value: 'dark',
-                    label: Text(
-                      strings.darkTheme,
-                      key: const Key('theme-dark'),
-                    ),
-                  ),
-                ],
-                selected: {settings.themeMode},
-                onSelectionChanged: (selection) => _apply(
-                  (db) => db.updateAppSettings(themeMode: selection.single),
-                ),
-              ),
-              const SizedBox(height: 8),
-              SwitchListTile(
-                key: const Key('dynamic-color-switch'),
-                title: Text(strings.dynamicColorTitle),
-                subtitle: Text(strings.dynamicColorSubtitle),
-                value: settings.useDynamicColor,
-                onChanged: (value) => _apply(
-                  (db) => db.updateAppSettings(useDynamicColor: value),
-                ),
-              ),
-              const SizedBox(height: 24),
-              Text(
-                strings.language,
-                style: Theme.of(context).textTheme.titleMedium,
-              ),
-              const SizedBox(height: 8),
-              SegmentedButton<String?>(
-                key: const Key('language-segmented'),
-                style: _segmentTapTargetStyle,
-                segments: [
-                  ButtonSegment(
-                    value: null,
-                    label: Text(
-                      strings.systemLanguage,
-                      key: const Key('language-system'),
-                    ),
-                  ),
-                  ButtonSegment(
-                    value: 'zh',
-                    label: Text(strings.chinese, key: const Key('language-zh')),
-                  ),
-                  ButtonSegment(
-                    value: 'en',
-                    label: Text(strings.english, key: const Key('language-en')),
-                  ),
-                ],
-                selected: {settings.localeCode},
-                onSelectionChanged: (selection) => _apply(
-                  (db) =>
-                      db.updateAppSettings(localeCode: selection.single ?? ''),
-                ),
-              ),
-              const SizedBox(height: 32),
-              _SectionHeader(label: strings.newProjectDefaults),
-              const SizedBox(height: 8),
-              Text(
-                strings.watermarkPosition,
-                style: Theme.of(context).textTheme.titleMedium,
-              ),
-              const SizedBox(height: 8),
-              SegmentedButton<String>(
-                key: const Key('default-position-segmented'),
-                style: _segmentTapTargetStyle,
-                segments: [
-                  ButtonSegment(
-                    value: 'bottomLeft',
-                    label: Text(
-                      strings.bottomLeft,
-                      key: const Key('default-position-bottomLeft'),
-                    ),
-                  ),
-                  ButtonSegment(
-                    value: 'bottomRight',
-                    label: Text(
-                      strings.bottomRight,
-                      key: const Key('default-position-bottomRight'),
-                    ),
-                  ),
-                ],
-                selected: {settings.defaultWatermarkPosition},
-                onSelectionChanged: (selection) => _apply(
-                  (db) => db.updateAppSettings(
-                    defaultWatermarkPosition: selection.single,
-                  ),
-                ),
-              ),
-              const SizedBox(height: 24),
-              Builder(
-                builder: (context) {
-                  // Resolve the displayed opacity: follow the finger while
-                  // dragging, otherwise reflect the persisted value.
-                  final opacity =
-                      (_dragValue ?? settings.defaultWatermarkOpacity).clamp(
-                        0.20,
-                        0.95,
-                      );
-                  final percent = (opacity * 100).round();
-                  return Column(
-                    crossAxisAlignment: CrossAxisAlignment.stretch,
-                    children: [
-                      Row(
-                        children: [
-                          Expanded(
-                            child: Text(
-                              strings.watermarkOpacity,
-                              style: Theme.of(context).textTheme.titleMedium,
-                            ),
-                          ),
-                          Text('$percent%'),
-                        ],
-                      ),
-                      Slider(
-                        key: const Key('opacity-slider'),
-                        value: opacity,
-                        min: 0.20,
-                        max: 0.95,
-                        divisions: 75,
-                        label: '$percent%',
-                        // Live-drag feedback: track the thumb position without
-                        // hammering the database on every pixel of movement.
-                        onChanged: (value) {
-                          setState(() => _dragValue = value);
-                        },
-                        // Persist only on release, then drop back to the
-                        // persisted value as the source of truth.
-                        onChangeEnd: (value) {
-                          _apply(
-                            (db) => db.updateAppSettings(
-                              defaultWatermarkOpacity: value,
-                            ),
-                          );
-                          setState(() => _dragValue = null);
-                        },
-                      ),
-                    ],
-                  );
-                },
-              ),
-              const SizedBox(height: 8),
-              Text(
-                strings.opacityHint,
-                style: Theme.of(context).textTheme.bodySmall,
-              ),
-              const SizedBox(height: 20),
-              Builder(
-                builder: (context) {
-                  // Resolve the displayed font scale: follow the finger while
-                  // dragging, otherwise reflect the persisted value.
-                  final fontScale =
-                      (_fontScaleDragValue ??
-                              settings.defaultWatermarkFontScale)
-                          .clamp(0.80, 1.60);
-                  final percent = (fontScale * 100).round();
-                  return Column(
-                    crossAxisAlignment: CrossAxisAlignment.stretch,
-                    children: [
-                      Row(
-                        children: [
-                          Expanded(
-                            child: Text(
-                              strings.watermarkFontSize,
-                              style: Theme.of(context).textTheme.titleMedium,
-                            ),
-                          ),
-                          Text('$percent%'),
-                        ],
-                      ),
-                      Slider(
-                        key: const Key('default-font-scale-slider'),
-                        value: fontScale,
-                        min: 0.80,
-                        max: 1.60,
-                        divisions: 16,
-                        label: '$percent%',
-                        onChanged: (value) {
-                          setState(() => _fontScaleDragValue = value);
-                        },
-                        onChangeEnd: (value) {
-                          _apply(
-                            (db) => db.updateAppSettings(
-                              defaultWatermarkFontScale: value,
-                            ),
-                          );
-                          setState(() => _fontScaleDragValue = null);
-                        },
-                      ),
-                    ],
-                  );
-                },
-              ),
-              const SizedBox(height: 8),
-              Text(
-                strings.fontScaleHint,
-                style: Theme.of(context).textTheme.bodySmall,
-              ),
-              const SizedBox(height: 20),
-              Text(
-                strings.accentColor,
-                style: Theme.of(context).textTheme.titleMedium,
-              ),
-              const SizedBox(height: 12),
-              Wrap(
-                spacing: 10,
-                runSpacing: 10,
-                children: [
-                  for (final swatch in _accentSwatches)
-                    _AccentChoice(
-                      choiceKey: swatch.key,
-                      colorArgb: swatch.argb,
-                      selected:
-                          settings.defaultWatermarkAccentColorArgb ==
-                          swatch.argb,
-                      onSelected: () => _apply(
-                        (db) => db.updateAppSettings(
-                          defaultWatermarkAccentColorArgb: swatch.argb,
-                        ),
-                      ),
-                    ),
-                ],
-              ),
-              const SizedBox(height: 32),
-              _StorageSection(
-                usage: storageUsage,
-                onRefresh: () => ref.invalidate(storageUsageProvider),
-                onManageRecords: () => context.go('/records'),
-                onClearExports: () => _clearLocalExports(context),
-              ),
-              const SizedBox(height: 32),
-              _SectionHeader(label: strings.locationLabel),
-              const SizedBox(height: 8),
-              _LocationPermissionTile(
-                state: _permissionState,
-                onTap: _onLocationTapped,
-              ),
-              const SizedBox(height: 32),
-              SwitchListTile(
-                key: const Key('completion-notification-switch'),
-                title: Text(strings.completionNotificationTitle),
-                subtitle: Text(strings.completionNotificationSubtitle),
-                value: settings.completionNotificationsEnabled,
-                onChanged: _onCompletionNotificationChanged,
-              ),
-              const SizedBox(height: 32),
-              _AboutSection(
-                version: _version,
-                buildNumber: _buildNumber,
-                onOpenRepository: () => _openRepository(context),
-              ),
-            ],
+      body: ListView.builder(
+        padding: const EdgeInsets.all(12),
+        itemCount: entries.length,
+        itemBuilder: (context, index) {
+          final (icon, title, route) = entries[index];
+          return Card(
+            child: ListTile(
+              leading: Icon(icon),
+              title: Text(title),
+              trailing: const Icon(Icons.chevron_right),
+              onTap: () => context.go(route),
+            ),
           );
         },
       ),
     );
   }
 }
-
-class _StorageSection extends StatelessWidget {
-  const _StorageSection({
-    required this.usage,
-    required this.onRefresh,
-    required this.onManageRecords,
-    required this.onClearExports,
-  });
-
-  final AsyncValue<AppStorageUsage> usage;
-  final VoidCallback onRefresh;
-  final VoidCallback onManageRecords;
-  final VoidCallback onClearExports;
-
-  @override
-  Widget build(BuildContext context) {
-    final strings = AppStrings.of(context);
-    return Column(
-      key: const Key('storage-section'),
-      crossAxisAlignment: CrossAxisAlignment.stretch,
-      children: [
-        Row(
-          children: [
-            Expanded(child: _SectionHeader(label: strings.storageScope)),
-            IconButton(
-              key: const Key('storage-refresh'),
-              onPressed: onRefresh,
-              tooltip: strings.refreshStorage,
-              icon: const Icon(Icons.refresh),
-            ),
-          ],
-        ),
-        const SizedBox(height: 8),
-        usage.when(
-          data: (value) => Column(
-            children: [
-              Card(
-                child: Column(
-                  children: [
-                    _StorageRow(
-                      label: strings.storageTotal,
-                      bytes: value.totalBytes,
-                      emphasized: true,
-                    ),
-                    const Divider(height: 1),
-                    _StorageRow(
-                      label: strings.privateOriginals,
-                      bytes: value.originalBytes,
-                    ),
-                    _StorageRow(
-                      label: strings.privateWatermarked,
-                      bytes: value.renderedBytes,
-                    ),
-                    _StorageRow(
-                      label: strings.localExportFiles,
-                      bytes: value.exportBytes,
-                    ),
-                    _StorageRow(
-                      label: strings.databaseAndOther,
-                      bytes: value.databaseAndOtherBytes,
-                    ),
-                  ],
-                ),
-              ),
-              ListTile(
-                key: const Key('manage-storage-records'),
-                leading: const Icon(Icons.photo_library_outlined),
-                title: Text(strings.manageRecords),
-                trailing: const Icon(Icons.chevron_right),
-                onTap: onManageRecords,
-              ),
-              ListTile(
-                key: const Key('clear-local-exports'),
-                leading: const Icon(Icons.delete_sweep_outlined),
-                title: Text(strings.clearLocalExports),
-                subtitle: Text(strings.clearLocalExportsHint),
-                onTap: value.exportBytes == 0 ? null : onClearExports,
-              ),
-            ],
-          ),
-          error: (_, _) => Column(
-            children: [
-              Text(strings.storageLoadFailed),
-              const SizedBox(height: 8),
-              OutlinedButton.icon(
-                key: const Key('retry-storage-load'),
-                onPressed: onRefresh,
-                icon: const Icon(Icons.refresh),
-                label: Text(strings.retry),
-              ),
-            ],
-          ),
-          loading: () => const Padding(
-            padding: EdgeInsets.all(20),
-            child: Center(child: CircularProgressIndicator()),
-          ),
-        ),
-      ],
-    );
-  }
-}
-
-class _StorageRow extends StatelessWidget {
-  const _StorageRow({
-    required this.label,
-    required this.bytes,
-    this.emphasized = false,
-  });
-
-  final String label;
-  final int bytes;
-  final bool emphasized;
-
-  @override
-  Widget build(BuildContext context) {
-    final style = emphasized ? Theme.of(context).textTheme.titleMedium : null;
-    return ListTile(
-      dense: true,
-      title: Text(label, style: style),
-      trailing: Text(formatStorageBytes(bytes), style: style),
-    );
-  }
-}
-
-class _SectionHeader extends StatelessWidget {
-  const _SectionHeader({required this.label});
-
-  final String label;
-
-  @override
-  Widget build(BuildContext context) {
-    return Text(
-      label,
-      style: Theme.of(context).textTheme.titleLarge?.copyWith(
-        color: Theme.of(context).colorScheme.primary,
-      ),
-    );
-  }
-}
-
-/// ListTile that surfaces the current location-permission state. When the
-/// permission is not granted, tapping the tile requests it (or opens system
-/// settings when the platform reports `permanentlyDenied`).
-class _LocationPermissionTile extends StatelessWidget {
-  const _LocationPermissionTile({required this.state, required this.onTap});
-
-  final LocationPermissionViewState? state;
-  final VoidCallback onTap;
-
-  @override
-  Widget build(BuildContext context) {
-    final strings = AppStrings.of(context);
-    final current = state;
-    final enabled = current?.locationEnabled ?? false;
-    return ListTile(
-      key: const Key('location-permission-setting'),
-      leading: const Icon(Icons.location_on_outlined),
-      title: Text(strings.locationLabel),
-      trailing: current == null
-          ? const SizedBox(
-              width: 16,
-              height: 16,
-              child: CircularProgressIndicator(strokeWidth: 2),
-            )
-          : Text(enabled ? strings.enabled : strings.disabled),
-      subtitle: current != null && !enabled
-          ? Text(
-              current.openSettings
-                  ? strings.locationPermanentlyDeniedHint
-                  : strings.locationDisabledHint,
-            )
-          : null,
-      onTap: current == null || enabled ? null : onTap,
-    );
-  }
-}
-
-class _AccentChoice extends StatelessWidget {
-  const _AccentChoice({
-    required this.choiceKey,
-    required this.colorArgb,
-    required this.selected,
-    required this.onSelected,
-  });
-
-  final Key choiceKey;
-  final int colorArgb;
-  final bool selected;
-  final VoidCallback onSelected;
-
-  @override
-  Widget build(BuildContext context) {
-    return ChoiceChip(
-      key: choiceKey,
-      selected: selected,
-      avatar: CircleAvatar(backgroundColor: Color(colorArgb)),
-      label: Text(_label(context, colorArgb)),
-      onSelected: (_) => onSelected(),
-    );
-  }
-
-  String _label(BuildContext context, int argb) {
-    final strings = AppStrings.of(context);
-    if (argb == 0xff37c58b) return strings.green;
-    if (argb == 0xff1565c0) return strings.blue;
-    if (argb == 0xffef6c00) return strings.orange;
-    return '';
-  }
-}
-
-class _AboutSection extends StatelessWidget {
-  const _AboutSection({
-    required this.version,
-    required this.buildNumber,
-    required this.onOpenRepository,
-  });
-
-  final String version;
-  final String buildNumber;
-  final VoidCallback onOpenRepository;
-
-  @override
-  Widget build(BuildContext context) {
-    final strings = AppStrings.of(context);
-    return Column(
-      crossAxisAlignment: CrossAxisAlignment.start,
-      children: [
-        _SectionHeader(label: strings.about),
-        const SizedBox(height: 12),
-        ListTile(
-          leading: const Icon(Icons.info_outline),
-          title: Text(strings.version),
-          trailing: Text('$version+$buildNumber'),
-        ),
-        ListTile(
-          leading: const Icon(Icons.shield_outlined),
-          title: Text(strings.privacyStatements),
-        ),
-        Padding(
-          padding: const EdgeInsets.symmetric(horizontal: 16),
-          child: Text(
-            strings.privacySummary,
-            style: Theme.of(context).textTheme.bodySmall,
-          ),
-        ),
-        ListTile(
-          key: const Key('github-repository-link'),
-          leading: const Icon(Icons.source_outlined),
-          title: Text(strings.repository),
-          subtitle: const Text(siteMarkRepositoryUrl),
-          trailing: const Icon(Icons.open_in_new),
-          onTap: onOpenRepository,
-        ),
-        ListTile(
-          leading: const Icon(Icons.description_outlined),
-          title: Text(strings.license),
-          subtitle: Text(strings.licenseValue),
-        ),
-        const SizedBox(height: 8),
-        FilledButton.tonalIcon(
-          onPressed: () => showLicensePage(
-            context: context,
-            applicationName: strings.appName,
-            applicationVersion: '$version+$buildNumber',
-          ),
-          icon: const Icon(Icons.article_outlined),
-          label: Text(strings.licenses),
-        ),
-      ],
-    );
-  }
-}
diff --git a/test/features/settings/global_settings_screen_test.dart b/test/features/settings/global_settings_screen_test.dart
index 9470651..69a392e 100644
--- a/test/features/settings/global_settings_screen_test.dart
+++ b/test/features/settings/global_settings_screen_test.dart
@@ -1,322 +1,104 @@
 import 'package:drift/native.dart';
 import 'package:flutter/material.dart';
 import 'package:flutter_localizations/flutter_localizations.dart';
 import 'package:flutter_riverpod/flutter_riverpod.dart';
 import 'package:flutter_test/flutter_test.dart';
 import 'package:go_router/go_router.dart';
 import 'package:sitemark/app.dart';
-import 'package:sitemark/domain/app_links.dart';
-import 'package:sitemark/domain/app_storage_usage.dart';
-import 'package:sitemark/platform/external_link_service.dart';
-import 'package:sitemark/platform/notification_service.dart';
-import 'package:sitemark/platform/platform_services.dart';
-import 'package:sitemark_system_api/sitemark_system_api.dart';
 import 'package:sitemark/data/app_database.dart';
+import 'package:sitemark/domain/app_storage_usage.dart';
 import 'package:sitemark/features/settings/global_settings_screen.dart';
 import 'package:sitemark/l10n/app_strings.dart';
 import 'package:sitemark/workflow/app_storage_service.dart';
 
 void main() {
   late AppDatabase database;
 
   setUp(() {
     database = AppDatabase.forTesting(NativeDatabase.memory());
   });
 
   tearDown(() async {
     await database.close();
   });
 
   /// Pumps the [GlobalSettingsScreen] in a localized Material harness wired to
   /// the in-memory [database] via Riverpod overrides.
-  Future<void> pumpSettings(
-    WidgetTester tester, {
-    AppDatabase? db,
-    PlatformServices? platform,
-    ExternalLinkService? externalLinks,
-    StorageUsageService? storage,
-    CompletionNotificationService? notifications,
-  }) async {
-    final resolved = db ?? database;
-    // Default to a fake platform so the screen's permission load resolves
-    // deterministically instead of hanging on the real platform channel.
-    final resolvedPlatform = platform ?? _SettingsTestPlatformServices();
-    final resolvedLinks = externalLinks ?? _RecordingExternalLinkService();
-    final resolvedStorage =
-        storage ??
-        _RecordingStorageUsageService(const [
-          AppStorageUsage(
-            originalBytes: 0,
-            renderedBytes: 0,
-            exportBytes: 0,
-            databaseAndOtherBytes: 0,
-          ),
-        ]);
-    // Open the lazy in-memory database and ensure the singleton settings row
-    // before the screen reads it, so the FutureBuilder resolves on the first
-    // pumped frame instead of stalling `pumpAndSettle` on the DB open.
-    await resolved.getAppSettings();
+  Future<void> pumpSettings(WidgetTester tester) async {
+    await database.getAppSettings();
     await tester.pumpWidget(
       ProviderScope(
-        overrides: [
-          databaseProvider.overrideWithValue(resolved),
-          platformServicesProvider.overrideWithValue(resolvedPlatform),
-          externalLinkServiceProvider.overrideWithValue(resolvedLinks),
-          storageUsageServiceProvider.overrideWithValue(resolvedStorage),
-          if (notifications != null)
-            completionNotificationServiceProvider.overrideWithValue(
-              notifications,
-            ),
-        ],
+        overrides: [databaseProvider.overrideWithValue(database)],
         child: MaterialApp(
           locale: const Locale('zh'),
           supportedLocales: AppStrings.supportedLocales,
           localizationsDelegates: const [
             AppStrings.delegate,
             GlobalMaterialLocalizations.delegate,
             GlobalWidgetsLocalizations.delegate,
             GlobalCupertinoLocalizations.delegate,
           ],
           home: const GlobalSettingsScreen(),
         ),
       ),
     );
     await tester.pumpAndSettle();
   }
 
-  testWidgets('theme and language persist through database settings', (
-    tester,
-  ) async {
-    await pumpSettings(tester, db: database);
-    await tester.tap(find.byKey(const Key('theme-dark')));
-    await tester.tap(find.byKey(const Key('language-en')));
-    await tester.pumpAndSettle();
-
-    final settings = await database.getAppSettings();
-    expect(settings.themeMode, 'dark');
-    expect(settings.localeCode, 'en');
-  });
-
-  testWidgets(
-    'opacity slider persists on change end within the 0.20-0.95 range',
-    (tester) async {
-      await pumpSettings(tester, db: database);
-      // The default opacity (0.78) already satisfies the 0.20-0.95 bounds, so a
-      // bare range check cannot detect a regression where onChangeEnd never
-      // persists. Drag the thumb hard to the right end: with divisions: 75 over
-      // [0.20, 0.95] the value snaps to exactly 0.95, which differs from 0.78.
-      // Asserting 0.95 proves onChangeEnd wrote the dragged value to the DB.
-      await tester.timedDrag(
-        find.byKey(const Key('opacity-slider')),
-        const Offset(500, 0),
-        const Duration(milliseconds: 200),
-      );
-      await tester.pumpAndSettle();
-
-      final settings = await database.getAppSettings();
-      expect(settings.defaultWatermarkOpacity, 0.95);
-      expect(settings.defaultWatermarkOpacity, lessThanOrEqualTo(0.95));
-      expect(settings.defaultWatermarkOpacity, greaterThanOrEqualTo(0.20));
-    },
-  );
-
-  testWidgets('default font scale persists on release', (tester) async {
+  testWidgets('shows 7 settings entries', (tester) async {
     await pumpSettings(tester);
-    final sliderFinder = find.byKey(const Key('default-font-scale-slider'));
-    final scrollable = find.byType(Scrollable).first;
-    await tester.scrollUntilVisible(sliderFinder, 200, scrollable: scrollable);
-    // scrollUntilVisible stops once the slider is built, but ListView's
-    // off-screen cache extent can leave the thumb just below the viewport.
-    // ensureVisible scrolls it fully on-screen so the drag hit-tests it.
-    await tester.ensureVisible(sliderFinder);
-    await tester.pumpAndSettle();
-    await tester.timedDrag(
-      sliderFinder,
-      const Offset(500, 0),
-      const Duration(milliseconds: 200),
-    );
-    await tester.pumpAndSettle();
-    expect((await database.getAppSettings()).defaultWatermarkFontScale, 1.60);
-  });
-
-  testWidgets('accent swatch selection persists', (tester) async {
-    await pumpSettings(tester, db: database);
-    await tester.scrollUntilVisible(
-      find.byKey(const Key('accent-orange')),
-      200,
-      scrollable: find.byType(Scrollable).first,
-    );
-    await tester.tap(find.byKey(const Key('accent-orange')));
-    await tester.pumpAndSettle();
-
-    final settings = await database.getAppSettings();
-    expect(settings.defaultWatermarkAccentColorArgb, 0xffef6c00);
-  });
-
-  testWidgets('watermark position segmented control persists', (tester) async {
-    await pumpSettings(tester, db: database);
-    await tester.tap(find.byKey(const Key('default-position-bottomRight')));
-    await tester.pumpAndSettle();
-
-    final settings = await database.getAppSettings();
-    expect(settings.defaultWatermarkPosition, 'bottomRight');
-  });
-
-  testWidgets('dynamic color switch persists to the database', (tester) async {
-    await pumpSettings(tester, db: database);
-    await tester.tap(find.byKey(const Key('dynamic-color-switch')));
-    await tester.pumpAndSettle();
-
-    expect((await database.getAppSettings()).useDynamicColor, isTrue);
-
-    await tester.tap(find.byKey(const Key('dynamic-color-switch')));
-    await tester.pumpAndSettle();
-    expect((await database.getAppSettings()).useDynamicColor, isFalse);
-  });
-
-  testWidgets('completion notification switch persists when permission is '
-      'granted', (tester) async {
-    final notifications = _FakeCompletionNotificationService(
-      permissionResult: true,
-    );
-    await pumpSettings(tester, db: database, notifications: notifications);
-    final toggle = find.byKey(const Key('completion-notification-switch'));
-    await tester.scrollUntilVisible(
-      toggle,
-      200,
-      scrollable: find.byType(Scrollable).first,
-    );
-    await tester.ensureVisible(toggle);
-    await tester.pumpAndSettle();
-    await tester.tap(toggle);
-    await tester.pumpAndSettle();
-
-    expect(notifications.requestPermissionCount, 1);
-    expect(
-      (await database.getAppSettings()).completionNotificationsEnabled,
-      isTrue,
-    );
-  });
-
-  testWidgets('completion notification switch stays off and shows a snackbar '
-      'when permission is denied', (tester) async {
-    final notifications = _FakeCompletionNotificationService(
-      permissionResult: false,
-    );
-    await pumpSettings(tester, db: database, notifications: notifications);
-    final toggle = find.byKey(const Key('completion-notification-switch'));
-    await tester.scrollUntilVisible(
-      toggle,
-      200,
-      scrollable: find.byType(Scrollable).first,
-    );
-    await tester.ensureVisible(toggle);
-    await tester.pumpAndSettle();
-    await tester.tap(toggle);
-    await tester.pumpAndSettle();
-
-    expect(notifications.requestPermissionCount, 1);
-    expect(
-      (await database.getAppSettings()).completionNotificationsEnabled,
-      isFalse,
-    );
-    expect(find.text('通知权限被拒绝，可在系统设置中开启'), findsOneWidget);
-    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
-  });
-
-  testWidgets('about section shows fallback version when PackageInfo fails', (
-    tester,
-  ) async {
-    await pumpSettings(tester, db: database);
-    await tester.scrollUntilVisible(
-      find.textContaining('0.4.0'),
-      200,
-      scrollable: find.byType(Scrollable).first,
-    );
-    expect(find.textContaining('0.4.0'), findsOneWidget);
+    expect(find.text('新建项目水印默认值'), findsOneWidget);
+    expect(find.text('外观'), findsOneWidget);
+    expect(find.text('语言'), findsOneWidget);
+    expect(find.text('SiteMark 应用内数据占用（不含系统相册）'), findsOneWidget);
+    expect(find.text('定位'), findsOneWidget);
+    expect(find.text('完成通知'), findsOneWidget);
+    expect(find.text('关于'), findsOneWidget);
   });
 
-  testWidgets('storage section shows totals, refreshes, and clears exports', (
-    tester,
-  ) async {
-    final storage = _RecordingStorageUsageService([
-      const AppStorageUsage(
-        originalBytes: 1024 * 1024,
-        renderedBytes: 2 * 1024 * 1024,
-        exportBytes: 3 * 1024 * 1024,
-        databaseAndOtherBytes: 4 * 1024 * 1024,
-      ),
-      const AppStorageUsage(
-        originalBytes: 1024 * 1024,
-        renderedBytes: 2 * 1024 * 1024,
-        exportBytes: 0,
-        databaseAndOtherBytes: 4 * 1024 * 1024,
-      ),
-    ]);
-    await pumpSettings(tester, storage: storage);
-    final scrollable = find.byType(Scrollable).first;
-    await tester.scrollUntilVisible(
-      find.byKey(const Key('storage-section')),
-      300,
-      scrollable: scrollable,
+  testWidgets('settings route is reachable from the app shell', (tester) async {
+    await database.getAppSettings();
+    final router = GoRouter(
+      routes: [
+        GoRoute(
+          path: '/',
+          builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
+          routes: [
+            GoRoute(
+              path: 'settings',
+              builder: (context, state) => const GlobalSettingsScreen(),
+            ),
+          ],
+        ),
+      ],
     );
-
-    expect(find.text('SiteMark 应用内数据占用（不含系统相册）'), findsOneWidget);
-    expect(find.text('10 MB'), findsOneWidget);
-    expect(find.text('1 MB'), findsOneWidget);
-    expect(find.text('2 MB'), findsOneWidget);
-    expect(find.text('3 MB'), findsOneWidget);
-    expect(find.text('4 MB'), findsOneWidget);
-
-    await tester.ensureVisible(find.byKey(const Key('storage-refresh')));
-    await tester.tap(find.byKey(const Key('storage-refresh')));
-    await tester.pumpAndSettle();
-    expect(storage.loadCount, 2);
-
-    // Restore a non-zero export value to exercise the destructive action.
-    storage.values.add(
-      const AppStorageUsage(
-        originalBytes: 1024 * 1024,
-        renderedBytes: 2 * 1024 * 1024,
-        exportBytes: 3 * 1024 * 1024,
-        databaseAndOtherBytes: 4 * 1024 * 1024,
+    await tester.pumpWidget(
+      ProviderScope(
+        overrides: [databaseProvider.overrideWithValue(database)],
+        child: MaterialApp.router(
+          locale: const Locale('zh'),
+          supportedLocales: AppStrings.supportedLocales,
+          localizationsDelegates: const [
+            AppStrings.delegate,
+            GlobalMaterialLocalizations.delegate,
+            GlobalWidgetsLocalizations.delegate,
+            GlobalCupertinoLocalizations.delegate,
+          ],
+          routerConfig: router,
+        ),
       ),
     );
-    await tester.tap(find.byKey(const Key('storage-refresh')));
-    await tester.pumpAndSettle();
-    await tester.ensureVisible(find.byKey(const Key('clear-local-exports')));
-    await tester.tap(find.byKey(const Key('clear-local-exports')));
-    await tester.pumpAndSettle();
-    await tester.tap(find.byKey(const Key('confirm-clear-exports')));
-    await tester.pumpAndSettle();
-    expect(storage.clearCount, 1);
-    expect(storage.loadCount, 4);
-  });
-
-  testWidgets('storage error state retries successfully', (tester) async {
-    final storage = _RetryingStorageUsageService();
-    await pumpSettings(tester, storage: storage);
-    await tester.scrollUntilVisible(
-      find.byKey(const Key('storage-section')),
-      300,
-      scrollable: find.byType(Scrollable).first,
-    );
-    expect(find.text('无法读取存储占用'), findsOneWidget);
-
-    await tester.ensureVisible(find.byKey(const Key('retry-storage-load')));
-    await tester.pumpAndSettle();
-    await tester.tap(find.byKey(const Key('retry-storage-load')));
+    router.go('/settings');
     await tester.pumpAndSettle();
 
-    expect(storage.loadCount, 2);
-    expect(find.text('无法读取存储占用'), findsNothing);
+    expect(find.byType(GlobalSettingsScreen), findsOneWidget);
   });
 
   test(
     'storage usage stays cached after settings disposal until invalidated',
     () async {
       final storage = _RecordingStorageUsageService(const [
         AppStorageUsage(
           originalBytes: 1,
           renderedBytes: 2,
           exportBytes: 3,
@@ -346,313 +128,20 @@ void main() {
       );
       await container.read(storageUsageProvider.future);
       expect(storage.loadCount, 1);
 
       container.invalidate(storageUsageProvider);
       await container.read(storageUsageProvider.future);
       expect(storage.loadCount, 2);
       reenteredListener.close();
     },
   );
-
-  testWidgets('storage manage-records entry opens the records route', (
-    tester,
-  ) async {
-    await database.getAppSettings();
-    final router = GoRouter(
-      initialLocation: '/settings',
-      routes: [
-        GoRoute(
-          path: '/settings',
-          builder: (context, state) => const GlobalSettingsScreen(),
-        ),
-        GoRoute(
-          path: '/records',
-          builder: (context, state) =>
-              const Scaffold(body: Text('records destination')),
-        ),
-      ],
-    );
-    addTearDown(router.dispose);
-    await tester.pumpWidget(
-      ProviderScope(
-        overrides: [
-          databaseProvider.overrideWithValue(database),
-          platformServicesProvider.overrideWithValue(
-            _SettingsTestPlatformServices(),
-          ),
-          storageUsageServiceProvider.overrideWithValue(
-            _RecordingStorageUsageService(const [
-              AppStorageUsage(
-                originalBytes: 0,
-                renderedBytes: 0,
-                exportBytes: 0,
-                databaseAndOtherBytes: 0,
-              ),
-            ]),
-          ),
-        ],
-        child: MaterialApp.router(
-          locale: const Locale('zh'),
-          supportedLocales: AppStrings.supportedLocales,
-          localizationsDelegates: const [
-            AppStrings.delegate,
-            GlobalMaterialLocalizations.delegate,
-            GlobalWidgetsLocalizations.delegate,
-            GlobalCupertinoLocalizations.delegate,
-          ],
-          routerConfig: router,
-        ),
-      ),
-    );
-    await tester.pumpAndSettle();
-    await tester.scrollUntilVisible(
-      find.byKey(const Key('manage-storage-records')),
-      300,
-      scrollable: find.byType(Scrollable).first,
-    );
-    await tester.ensureVisible(find.byKey(const Key('manage-storage-records')));
-    await tester.pumpAndSettle();
-    await tester.tap(find.byKey(const Key('manage-storage-records')));
-    await tester.pumpAndSettle();
-
-    expect(find.text('records destination'), findsOneWidget);
-  });
-
-  testWidgets('about shows and opens the full GitHub repository URL', (
-    tester,
-  ) async {
-    final links = _RecordingExternalLinkService();
-    await pumpSettings(tester, db: database, externalLinks: links);
-    await tester.scrollUntilVisible(
-      find.text(siteMarkRepositoryUrl),
-      200,
-      scrollable: find.byType(Scrollable).first,
-    );
-    expect(find.text('GitHub 代码仓库'), findsOneWidget);
-    expect(find.text(siteMarkRepositoryUrl), findsOneWidget);
-
-    await tester.ensureVisible(find.byKey(const Key('github-repository-link')));
-    await tester.pumpAndSettle();
-    await tester.tap(find.byKey(const Key('github-repository-link')));
-    await tester.pump();
-    expect(links.opened, [siteMarkRepositoryUri]);
-  });
-
-  testWidgets('about shows a snackbar when opening the repository fails', (
-    tester,
-  ) async {
-    final links = _RecordingExternalLinkService(result: false);
-    await pumpSettings(tester, db: database, externalLinks: links);
-    await tester.scrollUntilVisible(
-      find.text(siteMarkRepositoryUrl),
-      200,
-      scrollable: find.byType(Scrollable).first,
-    );
-    await tester.ensureVisible(find.byKey(const Key('github-repository-link')));
-    await tester.pumpAndSettle();
-    await tester.tap(find.byKey(const Key('github-repository-link')));
-    await tester.pump();
-    expect(find.text('无法打开浏览器'), findsOneWidget);
-    expect(links.opened, [siteMarkRepositoryUri]);
-  });
-
-  testWidgets('location tile shows disabled when permission is denied', (
-    tester,
-  ) async {
-    await pumpSettings(
-      tester,
-      platform: _SettingsTestPlatformServices(
-        permissionState: LocationPermissionState.denied,
-      ),
-    );
-    await tester.scrollUntilVisible(
-      find.byKey(const Key('location-permission-setting')),
-      200,
-      scrollable: find.byType(Scrollable).first,
-    );
-    expect(find.text('未开启'), findsOneWidget);
-  });
-
-  testWidgets('location tile shows enabled when permission is granted', (
-    tester,
-  ) async {
-    await pumpSettings(
-      tester,
-      platform: _SettingsTestPlatformServices(
-        permissionState: LocationPermissionState.granted,
-      ),
-    );
-    await tester.scrollUntilVisible(
-      find.byKey(const Key('location-permission-setting')),
-      200,
-      scrollable: find.byType(Scrollable).first,
-    );
-    expect(find.text('已开启'), findsOneWidget);
-  });
-
-  testWidgets('tapping the disabled location tile requests permission', (
-    tester,
-  ) async {
-    await tester.binding.setSurfaceSize(const Size(800, 1200));
-    addTearDown(() => tester.binding.setSurfaceSize(null));
-    final platform = _SettingsTestPlatformServices(
-      permissionState: LocationPermissionState.denied,
-      requestResult: LocationPermissionState.denied,
-    );
-    await pumpSettings(tester, platform: platform);
-    await tester.scrollUntilVisible(
-      find.byKey(const Key('location-permission-setting')),
-      200,
-      scrollable: find.byType(Scrollable).first,
-    );
-    await tester.ensureVisible(
-      find.byKey(const Key('location-permission-setting')),
-    );
-    await tester.pumpAndSettle();
-    await tester.tap(find.byKey(const Key('location-permission-setting')));
-    await tester.pumpAndSettle();
-
-    expect(platform.requestLocationPermissionCount, 1);
-    final settings = await database.getAppSettings();
-    expect(settings.locationPermissionPromptDismissed, isTrue);
-  });
-
-  testWidgets('settings route is reachable from the app shell', (tester) async {
-    await database.getAppSettings();
-    final router = GoRouter(
-      routes: [
-        GoRoute(
-          path: '/',
-          builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
-          routes: [
-            GoRoute(
-              path: 'settings',
-              builder: (context, state) => const GlobalSettingsScreen(),
-            ),
-          ],
-        ),
-      ],
-    );
-    await tester.pumpWidget(
-      ProviderScope(
-        overrides: [
-          databaseProvider.overrideWithValue(database),
-          platformServicesProvider.overrideWithValue(
-            _SettingsTestPlatformServices(),
-          ),
-          storageUsageServiceProvider.overrideWithValue(
-            _RecordingStorageUsageService(const [
-              AppStorageUsage(
-                originalBytes: 0,
-                renderedBytes: 0,
-                exportBytes: 0,
-                databaseAndOtherBytes: 0,
-              ),
-            ]),
-          ),
-        ],
-        child: MaterialApp.router(
-          locale: const Locale('zh'),
-          supportedLocales: AppStrings.supportedLocales,
-          localizationsDelegates: const [
-            AppStrings.delegate,
-            GlobalMaterialLocalizations.delegate,
-            GlobalWidgetsLocalizations.delegate,
-            GlobalCupertinoLocalizations.delegate,
-          ],
-          routerConfig: router,
-        ),
-      ),
-    );
-    router.go('/settings');
-    await tester.pumpAndSettle();
-
-    expect(find.byType(GlobalSettingsScreen), findsOneWidget);
-  });
-}
-
-class _SettingsTestPlatformServices implements PlatformServices {
-  _SettingsTestPlatformServices({
-    this.permissionState = LocationPermissionState.denied,
-    this.requestResult = LocationPermissionState.denied,
-  });
-
-  LocationPermissionState permissionState;
-  LocationPermissionState requestResult;
-  int requestLocationPermissionCount = 0;
-  int openApplicationSettingsCount = 0;
-
-  @override
-  Future<LocationPermissionState> getLocationPermissionState() async =>
-      permissionState;
-
-  @override
-  Future<LocationPermissionState> requestLocationPermission() async {
-    requestLocationPermissionCount++;
-    return requestResult;
-  }
-
-  @override
-  Future<void> openApplicationSettings() async {
-    openApplicationSettingsCount++;
-  }
-
-  @override
-  Future<String> createCameraTarget(String captureId) async =>
-      '/private/$captureId.jpg';
-
-  @override
-  Future<CameraCaptureResult> launchCamera(String captureId) async =>
-      CameraCaptureResult(
-        outcome: CameraOutcome.captured,
-        outputPath: '/private/$captureId.jpg',
-      );
-
-  @override
-  Future<RecoveredCameraCapture?> recoverCameraCapture() async => null;
-
-  @override
-  Future<void> finishCameraCapture(String captureId, bool keepOriginal) async {}
-
-  @override
-  Future<LocationResult> requestCurrentLocation(int timeoutMillis) async =>
-      LocationResult(outcome: LocationOutcome.unavailable);
-
-  @override
-  Future<String> publishJpeg(String sourcePath, String displayName) async =>
-      'content://media/site-mark/1';
-
-  @override
-  Future<void> deletePublishedImage(String contentUri) async {}
-
-  @override
-  Future<ImageMetadataResult> inspectImage(String path) async =>
-      ImageMetadataResult(
-        width: 0,
-        height: 0,
-        fileSizeBytes: 0,
-        mimeType: 'image/jpeg',
-      );
-}
-
-class _RecordingExternalLinkService implements ExternalLinkService {
-  _RecordingExternalLinkService({this.result = true});
-
-  final bool result;
-  final List<Uri> opened = [];
-
-  @override
-  Future<bool> open(Uri uri) async {
-    opened.add(uri);
-    return result;
-  }
 }
 
 class _RecordingStorageUsageService implements StorageUsageService {
   _RecordingStorageUsageService(this.values);
 
   final List<AppStorageUsage> values;
   int loadCount = 0;
   int clearCount = 0;
 
   @override
@@ -670,60 +159,10 @@ class _RecordingStorageUsageService implements StorageUsageService {
       AppStorageUsage(
         originalBytes: current.originalBytes,
         renderedBytes: current.renderedBytes,
         exportBytes: 0,
         databaseAndOtherBytes: current.databaseAndOtherBytes,
       ),
     );
     return const ClearExportsResult(deletedFiles: 1, freedBytes: 1024);
   }
 }
-
-class _RetryingStorageUsageService implements StorageUsageService {
-  int loadCount = 0;
-
-  @override
-  Future<AppStorageUsage> load() async {
-    loadCount++;
-    if (loadCount == 1) throw StateError('read failed');
-    return const AppStorageUsage(
-      originalBytes: 0,
-      renderedBytes: 0,
-      exportBytes: 0,
-      databaseAndOtherBytes: 0,
-    );
-  }
-
-  @override
-  Future<ClearExportsResult> clearExports() async {
-    return const ClearExportsResult(deletedFiles: 0, freedBytes: 0);
-  }
-}
-
-class _FakeCompletionNotificationService
-    implements CompletionNotificationService {
-  _FakeCompletionNotificationService({this.permissionResult = true});
-
-  bool permissionResult;
-  int requestPermissionCount = 0;
-
-  @override
-  Future<void> initialize(
-    void Function(String deepLinkPath) onTapDeepLink,
-  ) async {}
-
-  @override
-  Future<bool> requestPermission() async {
-    requestPermissionCount++;
-    return permissionResult;
-  }
-
-  @override
-  Future<void> showCaptureReady({
-    required String projectId,
-    required String captureId,
-    required String photoNumber,
-  }) async {}
-
-  @override
-  Future<void> setEnabled(bool enabled) async {}
-}
