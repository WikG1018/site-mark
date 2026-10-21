import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/domain/app_links.dart';
import 'package:sitemark/domain/release_check.dart';
import 'package:sitemark/features/settings/settings_section_scaffold.dart';
import 'package:sitemark/features/settings/sections/app_update_panel.dart';
import 'package:sitemark/platform/app_update_controller.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/shared/ui/adaptive_segmented_button.dart';
import 'package:sitemark/shared/ui/adaptive_toast.dart';

/// Fallback version/build used when [PackageInfo.fromPlatform] fails (e.g. in
/// unit tests where no platform plugin is available).
const _fallbackPackageInfo = (version: '1.0.31', buildNumber: '46');

class AboutSectionScreen extends ConsumerStatefulWidget {
  const AboutSectionScreen({super.key});

  @override
  ConsumerState<AboutSectionScreen> createState() => _AboutSectionScreenState();
}

class _AboutSectionScreenState extends ConsumerState<AboutSectionScreen> {
  String _version = _fallbackPackageInfo.version;
  String _buildNumber = _fallbackPackageInfo.buildNumber;
  ReleaseCheckMode _mode = ReleaseCheckMode.auto;
  ReleaseCheckOutcome? _outcome;
  bool _checking = false;
  bool _opening = false;
  bool _metadataLoaded = false;
  bool _metadataAvailable = false;
  bool _modeLoaded = false;
  bool _modeSaving = false;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
    _loadMode();
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _version = info.version.isEmpty
            ? _fallbackPackageInfo.version
            : info.version;
        _buildNumber = info.buildNumber.isEmpty
            ? _fallbackPackageInfo.buildNumber
            : info.buildNumber;
        _metadataAvailable =
            parseVersion(info.version) != null &&
            int.tryParse(info.buildNumber) != null;
      });
    } catch (_) {
      // 无平台插件时保留 fallback 常量；关于区块仍可正常渲染。
    } finally {
      if (mounted) setState(() => _metadataLoaded = true);
    }
  }

  Future<void> _loadMode() async {
    try {
      final mode = await ref.read(releaseCheckModeStoreProvider).read();
      if (!mounted) return;
      setState(() => _mode = mode);
    } catch (_) {
      if (!mounted) return;
      setState(() => _mode = ReleaseCheckMode.auto);
    } finally {
      if (mounted) setState(() => _modeLoaded = true);
    }
  }

  Future<void> _setMode(ReleaseCheckMode mode) async {
    if (_checking ||
        !_modeLoaded ||
        _modeSaving ||
        ref.read(appUpdateControllerProvider).busy) {
      return;
    }
    setState(() {
      _mode = mode;
      _outcome = null;
      _modeSaving = true;
    });
    try {
      await ref.read(releaseCheckModeStoreProvider).write(mode);
    } catch (_) {
      // 写失败不发请求。下次打开读失败会回到自动。
    } finally {
      if (mounted) setState(() => _modeSaving = false);
    }
  }

  Future<void> _onCheckTap(BuildContext context) async {
    if (_checking ||
        _opening ||
        !_metadataLoaded ||
        !_modeLoaded ||
        _modeSaving ||
        ref.read(appUpdateControllerProvider).busy) {
      return;
    }
    if (!_metadataAvailable) {
      setState(() => _outcome = const ReleaseCheckOutcome.failed());
      return;
    }
    await _checkForUpdates();
  }

  Future<void> _checkForUpdates() async {
    setState(() {
      _checking = true;
      _outcome = null;
    });
    try {
      final outcome = await ref
          .read(releaseLookupProvider)
          .check(localVersion: _version, mode: _mode);
      if (!mounted) return;
      setState(() {
        _checking = false;
        _outcome = outcome;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _outcome = const ReleaseCheckOutcome.failed();
      });
    }
  }

  Future<void> _openReleasePage(BuildContext context) async {
    final outcome = _outcome;
    if (outcome == null || _opening) return;
    setState(() => _opening = true);
    try {
      final uri = await ref
          .read(releaseLookupProvider)
          .resolveReleasePage(outcome);
      if (!context.mounted) return;
      if (uri == null) {
        showAppToast(context, AppStrings.of(context).openLinkFailed);
        return;
      }
      final opened = await ref.read(externalLinkServiceProvider).open(uri);
      if (!opened && context.mounted) {
        showAppToast(context, AppStrings.of(context).openLinkFailed);
      }
    } catch (_) {
      if (context.mounted) {
        showAppToast(context, AppStrings.of(context).openLinkFailed);
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _openRepository(BuildContext context) async {
    try {
      final opened = await ref
          .read(externalLinkServiceProvider)
          .open(siteMarkRepositoryUri);
      if (!opened && context.mounted) {
        showAppToast(context, AppStrings.of(context).openLinkFailed);
      }
    } catch (_) {
      if (context.mounted) {
        showAppToast(context, AppStrings.of(context).openLinkFailed);
      }
    }
  }

  String? _statusText(AppStrings strings) {
    if (_checking) return strings.checkingForUpdates;
    final outcome = _outcome;
    if (outcome == null) return null;
    return switch (outcome.status) {
      ReleaseCheckStatus.upToDate => strings.upToDate,
      ReleaseCheckStatus.updateAvailable => strings.newVersionFound(
        outcome.versionLabel ?? '',
      ),
      ReleaseCheckStatus.failed => strings.checkForUpdatesFailed,
    };
  }

  bool get _showIosNote =>
      !_checking &&
      _outcome?.hasUpdate == true &&
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final status = _statusText(strings);
    final update = ref.watch(appUpdateControllerProvider);
    final android = defaultTargetPlatform == TargetPlatform.android;
    return ListenableBuilder(
      listenable: update,
      builder: (context, _) => SettingsSectionScaffold(
        title: strings.about,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(strings.version),
              trailing: Text('$_version+$_buildNumber'),
            ),
            ListTile(
              key: const Key('check-for-updates'),
              leading: const Icon(Icons.system_update_alt_outlined),
              title: Text(strings.checkForUpdates),
              subtitle: status == null ? null : Text(status),
              trailing: _checking
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              onTap:
                  _checking ||
                      _opening ||
                      !_metadataLoaded ||
                      !_modeLoaded ||
                      _modeSaving ||
                      update.busy
                  ? null
                  : () => unawaited(_onCheckTap(context)),
            ),
            if (android &&
                (_outcome?.hasUpdate == true || update.download != null)) ...[
              AppUpdatePanel(
                controller: update,
                mode: _mode,
                available: _outcome?.downloadForBuild(_buildNumber),
              ),
              if (_outcome?.hasUpdate == true &&
                  _outcome?.downloadForBuild(_buildNumber) == null &&
                  update.download == null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(strings.updatePackageUnavailable),
                ),
            ],
            if (_outcome?.hasUpdate == true)
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: TextButton(
                  key: const Key('open-release-page'),
                  onPressed: _opening
                      ? null
                      : () => unawaited(_openReleasePage(context)),
                  child: Text(strings.openReleasePage),
                ),
              ),
            if (_showIosNote)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  strings.iosPackageNote,
                  key: const Key('ios-release-note'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.updateSource,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  IgnorePointer(
                    ignoring:
                        _checking || !_modeLoaded || _modeSaving || update.busy,
                    child: AdaptiveSegmentedButton<ReleaseCheckMode>(
                      key: const Key('release-check-mode'),
                      style: segmentTapTargetStyle,
                      segments: [
                        ButtonSegment(
                          value: ReleaseCheckMode.auto,
                          label: Text(strings.releaseCheckAutomatic),
                        ),
                        ButtonSegment(
                          value: ReleaseCheckMode.official,
                          label: Text(strings.releaseCheckOfficialOnly),
                        ),
                        ButtonSegment(
                          value: ReleaseCheckMode.mirror,
                          label: Text(strings.releaseCheckMirrorFirst),
                        ),
                      ],
                      selected: {_mode},
                      onSelectionChanged: (selection) {
                        unawaited(_setMode(selection.single));
                      },
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: Text(strings.privacyStatements),
            ),
            ExpansionTile(
              title: Text(strings.privacyDetails),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Text(
                  strings.privacySummary,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (android) ...[
                  const SizedBox(height: 8),
                  Text(
                    strings.updatePrivacyNotice,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
            ListTile(
              key: const Key('github-repository-link'),
              leading: const Icon(Icons.source_outlined),
              title: Text(strings.repository),
              subtitle: const Text(siteMarkRepositoryUrl),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => _openRepository(context),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(strings.license),
              subtitle: Text(strings.licenseValue),
            ),
            ListTile(
              key: const Key('font-credit'),
              leading: const Icon(Icons.text_fields_outlined),
              title: Text(strings.fontCredit),
              subtitle: Text(strings.fontCreditValue),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                strings.fontCreditDetail,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: () => showLicensePage(
                context: context,
                applicationName: strings.appName,
                applicationVersion: '$_version+$_buildNumber',
              ),
              icon: const Icon(Icons.article_outlined),
              label: Text(strings.licenses),
            ),
          ],
        ),
      ),
    );
  }
}
