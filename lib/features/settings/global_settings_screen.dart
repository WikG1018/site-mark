import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/app_links.dart';
import 'package:sitemark/domain/app_storage_usage.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/platform/notification_service.dart';
import 'package:sitemark/workflow/location_permission_service.dart';
import 'package:sitemark_system_api/sitemark_system_api.dart';

/// Fallback version/build used when [PackageInfo.fromPlatform] fails (e.g. in
/// unit tests where no platform plugin is available).
const _fallbackVersion = '0.2.0';
const _fallbackBuild = '2';

/// Accent swatches offered as new-project watermark defaults. Order matches
/// the project-level watermark settings screen for visual consistency.
const _accentSwatches = <({int argb, Key key})>[
  (argb: 0xff37c58b, key: Key('accent-green')),
  (argb: 0xff1565c0, key: Key('accent-blue')),
  (argb: 0xffef6c00, key: Key('accent-orange')),
];

/// Segmented buttons default to a 40dp minimum height, below Android's 48dp
/// tap-target guideline; lifting the floor keeps the settings page compliant.
const _segmentTapTargetStyle = ButtonStyle(
  minimumSize: WidgetStatePropertyAll<Size>(Size.fromHeight(48)),
);

class GlobalSettingsScreen extends ConsumerStatefulWidget {
  const GlobalSettingsScreen({super.key});

  @override
  ConsumerState<GlobalSettingsScreen> createState() =>
      _GlobalSettingsScreenState();
}

class _GlobalSettingsScreenState extends ConsumerState<GlobalSettingsScreen>
    with WidgetsBindingObserver {
  late final Future<AppSetting> _initialSettings;
  AppSetting? _settings;
  String _version = _fallbackVersion;
  String _buildNumber = _fallbackBuild;
  // Tracks the opacity slider position during an active drag so the thumb and
  // percentage label follow the finger. Cleared on `onChangeEnd` (where the
  // value is persisted); `null` means "not dragging - show the persisted value".
  double? _dragValue;
  // Tracks the font-scale slider position during an active drag so the thumb
  // and percentage label follow the finger. Cleared on `onChangeEnd` (where
  // the value is persisted); `null` means "not dragging - show the persisted
  // value".
  double? _fontScaleDragValue;

  /// Cached location-permission view state. Loaded once during initialization
  /// and refreshed on app resume so the tile reflects permission changes the
  /// user made in the system dialog or settings. `null` means the first load
  /// has not finished.
  LocationPermissionViewState? _permissionState;

  @override
  void initState() {
    super.initState();
    // Store the future once so a rebuild does not re-trigger the load (mirrors
    // the project watermark settings screen's FutureBuilder pattern).
    _initialSettings = ref.read(databaseProvider).getAppSettings();
    _loadPackageInfo();
    _loadPermission();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Refresh after the user returns from the system permission dialog or
    // settings page so the tile reflects the new permission state.
    if (state == AppLifecycleState.resumed) {
      _loadPermission();
    }
  }

  Future<void> _loadPermission() async {
    try {
      final state = await ref.read(locationPermissionServiceProvider).load();
      if (!mounted) return;
      setState(() => _permissionState = state);
    } catch (_) {
      // The platform bridge is unavailable (e.g. in unit tests without a
      // platform override). Default to a disabled, non-explanation state so
      // the tile renders deterministically instead of spinning forever.
      if (!mounted) return;
      setState(() {
        _permissionState = const LocationPermissionViewState(
          permission: LocationPermissionState.denied,
          showExplanation: false,
        );
      });
    }
  }

  Future<void> _onLocationTapped() async {
    final service = ref.read(locationPermissionServiceProvider);
    final current = _permissionState;
    if (current == null || current.locationEnabled) return;
    if (current.openSettings) {
      // Route to system settings; the resumed lifecycle callback refreshes
      // the tile when the user returns.
      await service.openSettings();
      return;
    }
    final state = await service.request();
    if (!mounted) return;
    setState(() => _permissionState = state);
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _version = info.version.isEmpty ? _fallbackVersion : info.version;
        _buildNumber = info.buildNumber.isEmpty
            ? _fallbackBuild
            : info.buildNumber;
      });
    } catch (_) {
      // Keep the fallback constants; the About section still renders.
    }
  }

  /// Persists [op] and applies the returned [AppSetting] to local state so the
  /// UI reflects the new value without an always-open watch stream (which
  /// would keep the test frame loop busy).
  Future<void> _apply(Future<AppSetting> Function(AppDatabase db) op) async {
    final updated = await op(ref.read(databaseProvider));
    if (!mounted) return;
    setState(() => _settings = updated);
  }

  Future<void> _onCompletionNotificationChanged(bool value) async {
    if (!value) {
      await _apply(
        (db) => db.updateAppSettings(completionNotificationsEnabled: false),
      );
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
      await _apply(
        (db) => db.updateAppSettings(completionNotificationsEnabled: true),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context).notificationPermissionDenied),
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _openRepository(BuildContext context) async {
    try {
      final opened = await ref
          .read(externalLinkServiceProvider)
          .open(siteMarkRepositoryUri);
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).openLinkFailed)),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).openLinkFailed)),
        );
      }
    }
  }

  Future<void> _clearLocalExports(BuildContext context) async {
    final strings = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.clearLocalExports),
        content: Text(strings.clearLocalExportsPrompt),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            key: const Key('confirm-clear-exports'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(strings.clear),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      final result = await ref.read(storageUsageServiceProvider).clearExports();
      ref.invalidate(storageUsageProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(strings.localExportsCleared(result.deletedFiles)),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.clearLocalExportsFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final storageUsage = ref.watch(storageUsageProvider);
    return Scaffold(
      appBar: AppBar(title: Text(strings.settings)),
      body: FutureBuilder<AppSetting>(
        future: _initialSettings,
        builder: (context, snapshot) {
          final settings = _settings ?? snapshot.data;
          if (settings == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _SectionHeader(label: strings.appearance),
              const SizedBox(height: 8),
              Text(
                strings.theme,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                key: const Key('theme-segmented'),
                style: _segmentTapTargetStyle,
                segments: [
                  ButtonSegment(
                    value: 'system',
                    label: Text(
                      strings.systemTheme,
                      key: const Key('theme-system'),
                    ),
                  ),
                  ButtonSegment(
                    value: 'light',
                    label: Text(
                      strings.lightTheme,
                      key: const Key('theme-light'),
                    ),
                  ),
                  ButtonSegment(
                    value: 'dark',
                    label: Text(
                      strings.darkTheme,
                      key: const Key('theme-dark'),
                    ),
                  ),
                ],
                selected: {settings.themeMode},
                onSelectionChanged: (selection) => _apply(
                  (db) => db.updateAppSettings(themeMode: selection.single),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                key: const Key('dynamic-color-switch'),
                title: Text(strings.dynamicColorTitle),
                subtitle: Text(strings.dynamicColorSubtitle),
                value: settings.useDynamicColor,
                onChanged: (value) => _apply(
                  (db) => db.updateAppSettings(useDynamicColor: value),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                strings.language,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              SegmentedButton<String?>(
                key: const Key('language-segmented'),
                style: _segmentTapTargetStyle,
                segments: [
                  ButtonSegment(
                    value: null,
                    label: Text(
                      strings.systemLanguage,
                      key: const Key('language-system'),
                    ),
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
                selected: {settings.localeCode},
                onSelectionChanged: (selection) => _apply(
                  (db) =>
                      db.updateAppSettings(localeCode: selection.single ?? ''),
                ),
              ),
              const SizedBox(height: 32),
              _SectionHeader(label: strings.newProjectDefaults),
              const SizedBox(height: 8),
              Text(
                strings.watermarkPosition,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                key: const Key('default-position-segmented'),
                style: _segmentTapTargetStyle,
                segments: [
                  ButtonSegment(
                    value: 'bottomLeft',
                    label: Text(
                      strings.bottomLeft,
                      key: const Key('default-position-bottomLeft'),
                    ),
                  ),
                  ButtonSegment(
                    value: 'bottomRight',
                    label: Text(
                      strings.bottomRight,
                      key: const Key('default-position-bottomRight'),
                    ),
                  ),
                ],
                selected: {settings.defaultWatermarkPosition},
                onSelectionChanged: (selection) => _apply(
                  (db) => db.updateAppSettings(
                    defaultWatermarkPosition: selection.single,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Builder(
                builder: (context) {
                  // Resolve the displayed opacity: follow the finger while
                  // dragging, otherwise reflect the persisted value.
                  final opacity =
                      (_dragValue ?? settings.defaultWatermarkOpacity).clamp(
                        0.20,
                        0.95,
                      );
                  final percent = (opacity * 100).round();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              strings.watermarkOpacity,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          Text('$percent%'),
                        ],
                      ),
                      Slider(
                        key: const Key('opacity-slider'),
                        value: opacity,
                        min: 0.20,
                        max: 0.95,
                        divisions: 75,
                        label: '$percent%',
                        // Live-drag feedback: track the thumb position without
                        // hammering the database on every pixel of movement.
                        onChanged: (value) {
                          setState(() => _dragValue = value);
                        },
                        // Persist only on release, then drop back to the
                        // persisted value as the source of truth.
                        onChangeEnd: (value) {
                          _apply(
                            (db) => db.updateAppSettings(
                              defaultWatermarkOpacity: value,
                            ),
                          );
                          setState(() => _dragValue = null);
                        },
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),
              Text(
                strings.opacityHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              Builder(
                builder: (context) {
                  // Resolve the displayed font scale: follow the finger while
                  // dragging, otherwise reflect the persisted value.
                  final fontScale =
                      (_fontScaleDragValue ??
                              settings.defaultWatermarkFontScale)
                          .clamp(0.80, 1.60);
                  final percent = (fontScale * 100).round();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              strings.watermarkFontSize,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          Text('$percent%'),
                        ],
                      ),
                      Slider(
                        key: const Key('default-font-scale-slider'),
                        value: fontScale,
                        min: 0.80,
                        max: 1.60,
                        divisions: 16,
                        label: '$percent%',
                        onChanged: (value) {
                          setState(() => _fontScaleDragValue = value);
                        },
                        onChangeEnd: (value) {
                          _apply(
                            (db) => db.updateAppSettings(
                              defaultWatermarkFontScale: value,
                            ),
                          );
                          setState(() => _fontScaleDragValue = null);
                        },
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),
              Text(
                strings.fontScaleHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              Text(
                strings.accentColor,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final swatch in _accentSwatches)
                    _AccentChoice(
                      choiceKey: swatch.key,
                      colorArgb: swatch.argb,
                      selected:
                          settings.defaultWatermarkAccentColorArgb ==
                          swatch.argb,
                      onSelected: () => _apply(
                        (db) => db.updateAppSettings(
                          defaultWatermarkAccentColorArgb: swatch.argb,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 32),
              _StorageSection(
                usage: storageUsage,
                onRefresh: () => ref.invalidate(storageUsageProvider),
                onManageRecords: () => context.go('/records'),
                onClearExports: () => _clearLocalExports(context),
              ),
              const SizedBox(height: 32),
              _SectionHeader(label: strings.locationLabel),
              const SizedBox(height: 8),
              _LocationPermissionTile(
                state: _permissionState,
                onTap: _onLocationTapped,
              ),
              const SizedBox(height: 32),
              SwitchListTile(
                key: const Key('completion-notification-switch'),
                title: Text(strings.completionNotificationTitle),
                subtitle: Text(strings.completionNotificationSubtitle),
                value: settings.completionNotificationsEnabled,
                onChanged: _onCompletionNotificationChanged,
              ),
              const SizedBox(height: 32),
              _AboutSection(
                version: _version,
                buildNumber: _buildNumber,
                onOpenRepository: () => _openRepository(context),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StorageSection extends StatelessWidget {
  const _StorageSection({
    required this.usage,
    required this.onRefresh,
    required this.onManageRecords,
    required this.onClearExports,
  });

  final AsyncValue<AppStorageUsage> usage;
  final VoidCallback onRefresh;
  final VoidCallback onManageRecords;
  final VoidCallback onClearExports;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Column(
      key: const Key('storage-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _SectionHeader(label: strings.storageScope)),
            IconButton(
              key: const Key('storage-refresh'),
              onPressed: onRefresh,
              tooltip: strings.refreshStorage,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 8),
        usage.when(
          data: (value) => Column(
            children: [
              Card(
                child: Column(
                  children: [
                    _StorageRow(
                      label: strings.storageTotal,
                      bytes: value.totalBytes,
                      emphasized: true,
                    ),
                    const Divider(height: 1),
                    _StorageRow(
                      label: strings.privateOriginals,
                      bytes: value.originalBytes,
                    ),
                    _StorageRow(
                      label: strings.privateWatermarked,
                      bytes: value.renderedBytes,
                    ),
                    _StorageRow(
                      label: strings.localExportFiles,
                      bytes: value.exportBytes,
                    ),
                    _StorageRow(
                      label: strings.databaseAndOther,
                      bytes: value.databaseAndOtherBytes,
                    ),
                  ],
                ),
              ),
              ListTile(
                key: const Key('manage-storage-records'),
                leading: const Icon(Icons.photo_library_outlined),
                title: Text(strings.manageRecords),
                trailing: const Icon(Icons.chevron_right),
                onTap: onManageRecords,
              ),
              ListTile(
                key: const Key('clear-local-exports'),
                leading: const Icon(Icons.delete_sweep_outlined),
                title: Text(strings.clearLocalExports),
                subtitle: Text(strings.clearLocalExportsHint),
                onTap: value.exportBytes == 0 ? null : onClearExports,
              ),
            ],
          ),
          error: (_, _) => Column(
            children: [
              Text(strings.storageLoadFailed),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('retry-storage-load'),
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
                label: Text(strings.retry),
              ),
            ],
          ),
          loading: () => const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ],
    );
  }
}

class _StorageRow extends StatelessWidget {
  const _StorageRow({
    required this.label,
    required this.bytes,
    this.emphasized = false,
  });

  final String label;
  final int bytes;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final style = emphasized ? Theme.of(context).textTheme.titleMedium : null;
    return ListTile(
      dense: true,
      title: Text(label, style: style),
      trailing: Text(formatStorageBytes(bytes), style: style),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

/// ListTile that surfaces the current location-permission state. When the
/// permission is not granted, tapping the tile requests it (or opens system
/// settings when the platform reports `permanentlyDenied`).
class _LocationPermissionTile extends StatelessWidget {
  const _LocationPermissionTile({required this.state, required this.onTap});

  final LocationPermissionViewState? state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final current = state;
    final enabled = current?.locationEnabled ?? false;
    return ListTile(
      key: const Key('location-permission-setting'),
      leading: const Icon(Icons.location_on_outlined),
      title: Text(strings.locationLabel),
      trailing: current == null
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(enabled ? strings.enabled : strings.disabled),
      subtitle: current != null && !enabled
          ? Text(
              current.openSettings
                  ? strings.locationPermanentlyDeniedHint
                  : strings.locationDisabledHint,
            )
          : null,
      onTap: current == null || enabled ? null : onTap,
    );
  }
}

class _AccentChoice extends StatelessWidget {
  const _AccentChoice({
    required this.choiceKey,
    required this.colorArgb,
    required this.selected,
    required this.onSelected,
  });

  final Key choiceKey;
  final int colorArgb;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      key: choiceKey,
      selected: selected,
      avatar: CircleAvatar(backgroundColor: Color(colorArgb)),
      label: Text(_label(context, colorArgb)),
      onSelected: (_) => onSelected(),
    );
  }

  String _label(BuildContext context, int argb) {
    final strings = AppStrings.of(context);
    if (argb == 0xff37c58b) return strings.green;
    if (argb == 0xff1565c0) return strings.blue;
    if (argb == 0xffef6c00) return strings.orange;
    return '';
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection({
    required this.version,
    required this.buildNumber,
    required this.onOpenRepository,
  });

  final String version;
  final String buildNumber;
  final VoidCallback onOpenRepository;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(label: strings.about),
        const SizedBox(height: 12),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(strings.version),
          trailing: Text('$version+$buildNumber'),
        ),
        ListTile(
          leading: const Icon(Icons.shield_outlined),
          title: Text(strings.privacyStatements),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            strings.privacySummary,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        ListTile(
          key: const Key('github-repository-link'),
          leading: const Icon(Icons.source_outlined),
          title: Text(strings.repository),
          subtitle: const Text(siteMarkRepositoryUrl),
          trailing: const Icon(Icons.open_in_new),
          onTap: onOpenRepository,
        ),
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: Text(strings.license),
          subtitle: Text(strings.licenseValue),
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: () => showLicensePage(
            context: context,
            applicationName: strings.appName,
            applicationVersion: '$version+$buildNumber',
          ),
          icon: const Icon(Icons.article_outlined),
          label: Text(strings.licenses),
        ),
      ],
    );
  }
}
