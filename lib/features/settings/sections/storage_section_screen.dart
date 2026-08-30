import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/domain/app_storage_usage.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/shared/ui/adaptive_dialog.dart';

class StorageSectionScreen extends ConsumerStatefulWidget {
  const StorageSectionScreen({super.key});

  @override
  ConsumerState<StorageSectionScreen> createState() =>
      _StorageSectionScreenState();
}

class _StorageSectionScreenState extends ConsumerState<StorageSectionScreen> {
  Future<void> _clearLocalExports(BuildContext context) async {
    final strings = AppStrings.of(context);
    final confirmed = await showAppDialog<bool>(
      context: context,
      title: Text(strings.clearLocalExports),
      content: Text(strings.clearLocalExportsPrompt),
      actions: [
        AppDialogAction(label: strings.cancel, result: false),
        AppDialogAction(
          key: const Key('confirm-clear-exports'),
          label: strings.clear,
          result: true,
          isDefault: true,
        ),
      ],
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
    final usage = ref.watch(storageUsageProvider);
    return Scaffold(
      appBar: AppBar(title: Text(strings.storageScope)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Column(
            key: const Key('storage-section'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Spacer(),
                  IconButton(
                    key: const Key('storage-refresh'),
                    onPressed: () => ref.invalidate(storageUsageProvider),
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
                      onTap: () => context.go('/records'),
                    ),
                    ListTile(
                      key: const Key('clear-local-exports'),
                      leading: const Icon(Icons.delete_sweep_outlined),
                      title: Text(strings.clearLocalExports),
                      subtitle: Text(strings.clearLocalExportsHint),
                      onTap: value.exportBytes == 0
                          ? null
                          : () => _clearLocalExports(context),
                    ),
                  ],
                ),
                error: (_, _) => Column(
                  children: [
                    Text(strings.storageLoadFailed),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: const Key('retry-storage-load'),
                      onPressed: () => ref.invalidate(storageUsageProvider),
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
          ),
        ],
      ),
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
