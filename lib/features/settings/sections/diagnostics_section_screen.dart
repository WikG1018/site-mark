import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/features/settings/settings_section_scaffold.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/shared/ui/adaptive_dialog.dart';

class DiagnosticsSectionScreen extends ConsumerWidget {
  const DiagnosticsSectionScreen({
    super.key,
    this.onGenerateAndShare,
    this.onClear,
  });

  final Future<void> Function(BuildContext context)? onGenerateAndShare;
  final Future<void> Function(BuildContext context)? onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppStrings.of(context);
    return SettingsSectionScaffold(
      title: strings.diagnosticsAndFeedback,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.privacyProtection,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(strings.diagnosticsStoredLocally),
                  const SizedBox(height: 6),
                  Text(strings.diagnosticBundlePrivacyNotice),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Platform behavior differences (background scheduling downgrade,
          // photo-library deletion confirmation, approximate location). The
          // deletion wording stays uniform on every platform — only iOS pops
          // the system dialog, so "may confirm" is the honest common ground;
          // the iOS-specific scheduling note is the one content branch.
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.platformDifferences,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(strings.backgroundProcessingDescription),
                  if (defaultTargetPlatform == TargetPlatform.iOS) ...[
                    const SizedBox(height: 6),
                    Text(strings.backgroundProcessingIosNote),
                  ],
                  const SizedBox(height: 6),
                  Text(strings.photoLibraryDeleteConfirmationNote),
                  const SizedBox(height: 6),
                  Text(strings.locationAccuracyNote),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(strings.diagnosticsRetentionHint),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onGenerateAndShare == null
                ? () => _generateAndShare(context, ref)
                : () => onGenerateAndShare!(context),
            icon: const Icon(Icons.ios_share_outlined),
            label: Text(strings.generateAndShareDiagnosticBundle),
          ),
          TextButton(
            onPressed: onClear == null
                ? () => _clear(context, ref)
                : () => onClear!(context),
            child: Text(strings.clearLocalDiagnostics),
          ),
        ],
      ),
    );
  }

  Future<void> _generateAndShare(BuildContext context, WidgetRef ref) async {
    final strings = AppStrings.of(context);
    final confirmed = await showAppDialog<bool>(
      context: context,
      title: Text(strings.shareDiagnosticBundleTitle),
      content: Text(strings.shareDiagnosticBundleContent),
      actions: [
        AppDialogAction(label: strings.cancel, result: false),
        AppDialogAction(
          label: strings.confirmGenerate,
          result: true,
          isDefault: true,
        ),
      ],
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final service = await ref.read(diagnosticBundleServiceProvider.future);
      final dropped = ref.read(diagnosticRecorderProvider).droppedCount;
      final path = await service.generate(droppedEventCount: dropped);
      await ref.read(shareFileServiceProvider).shareFile(path);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.diagnosticBundleFailed)));
    }
  }

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final strings = AppStrings.of(context);
    final confirmed = await showAppDialog<bool>(
      context: context,
      title: Text(strings.clearDiagnosticsTitle),
      content: Text(strings.clearDiagnosticsContent),
      actions: [
        AppDialogAction(label: strings.cancel, result: false),
        AppDialogAction(label: strings.clear, result: true, isDefault: true),
      ],
    );
    if (confirmed != true) return;
    final service = await ref.read(diagnosticBundleServiceProvider.future);
    await service.store.clear();
  }
}
