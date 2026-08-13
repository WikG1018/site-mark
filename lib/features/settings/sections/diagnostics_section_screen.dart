import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/features/settings/settings_section_scaffold.dart';
import 'package:sitemark/l10n/app_strings.dart';

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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final dialogStrings = AppStrings.of(dialogContext);
        return AlertDialog(
          title: Text(dialogStrings.shareDiagnosticBundleTitle),
          content: Text(dialogStrings.shareDiagnosticBundleContent),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(dialogStrings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(dialogStrings.confirmGenerate),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final service = await ref.read(diagnosticBundleServiceProvider.future);
      final path = await service.generate();
      await ref.read(shareFileServiceProvider).shareFile(path);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.diagnosticBundleFailed)));
    }
  }

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final dialogStrings = AppStrings.of(dialogContext);
        return AlertDialog(
          title: Text(dialogStrings.clearDiagnosticsTitle),
          content: Text(dialogStrings.clearDiagnosticsContent),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(dialogStrings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(dialogStrings.clear),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    final service = await ref.read(diagnosticBundleServiceProvider.future);
    await service.store.clear();
  }
}
