import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/domain/app_links.dart';
import 'package:sitemark/features/settings/settings_section_scaffold.dart';
import 'package:sitemark/l10n/app_strings.dart';

/// Fallback version/build used when [PackageInfo.fromPlatform] fails (e.g. in
/// unit tests where no platform plugin is available).
const _fallbackPackageInfo = (version: '1.0.12', buildNumber: '27');

class AboutSectionScreen extends ConsumerStatefulWidget {
  const AboutSectionScreen({super.key});

  @override
  ConsumerState<AboutSectionScreen> createState() => _AboutSectionScreenState();
}

class _AboutSectionScreenState extends ConsumerState<AboutSectionScreen> {
  String _version = _fallbackPackageInfo.version;
  String _buildNumber = _fallbackPackageInfo.buildNumber;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
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
      });
    } catch (_) {
      // 无平台插件时保留 fallback 常量；关于区块仍可正常渲染。
    }
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

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return SettingsSectionScaffold(
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
            onTap: () => _openRepository(context),
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
              applicationVersion: '$_version+$_buildNumber',
            ),
            icon: const Icon(Icons.article_outlined),
            label: Text(strings.licenses),
          ),
        ],
      ),
    );
  }
}
