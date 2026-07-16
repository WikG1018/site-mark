import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/features/capture/capture_image_preview.dart';
import 'package:sitemark/l10n/app_strings.dart';

class CaptureDetailScreen extends ConsumerWidget {
  const CaptureDetailScreen({
    super.key,
    required this.projectId,
    required this.captureId,
  });

  final String projectId;
  final String captureId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppStrings.of(context);
    return StreamBuilder<CaptureRecord?>(
      stream: ref.watch(databaseProvider).watchCaptureById(captureId),
      builder: (context, snapshot) {
        final capture = snapshot.data;
        final isBusy =
            capture != null &&
            (capture.status == CaptureStatus.captured ||
                capture.status == CaptureStatus.rendering);
        final canRetry =
            capture != null &&
            capture.status == CaptureStatus.failed &&
            File(capture.originalPath).existsSync();
        return Scaffold(
          appBar: AppBar(
            title: Text(capture?.photoNumber ?? strings.captureDetail),
            actions: [
              if (capture != null && !isBusy) ...[
                IconButton(
                  onPressed: () => context.go(
                    '/projects/$projectId/captures/$captureId/edit',
                  ),
                  tooltip: strings.editRecord,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  onPressed: () => _delete(context, ref),
                  tooltip: strings.deleteRecord,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ],
          ),
          body: capture == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (canRetry)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: FilledButton.icon(
                          onPressed: () => _retry(context, ref),
                          icon: const Icon(Icons.refresh),
                          label: Text(strings.retryProcessing),
                        ),
                      ),
                    AspectRatio(
                      aspectRatio: 4 / 3,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CaptureImagePreview(
                          capture: capture,
                          outputPaths: ref.watch(captureOutputPathsProvider),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _DetailCard(
                      children: [
                        _DetailRow(
                          icon: Icons.place_outlined,
                          label: strings.workLocation,
                          value: capture.workLocation,
                        ),
                        _DetailRow(
                          icon: Icons.construction_outlined,
                          label: strings.workContent,
                          value: capture.workContent,
                        ),
                        _DetailRow(
                          icon: Icons.person_outline,
                          label: strings.photographer,
                          value: capture.photographer,
                        ),
                        if (capture.notes != null)
                          _DetailRow(
                            icon: Icons.notes_outlined,
                            label: strings.notesOptional,
                            value: capture.notes!,
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _DetailCard(
                      children: [
                        _DetailRow(
                          icon: Icons.schedule_outlined,
                          label: strings.capturedAt,
                          value: capture.capturedAt?.toIso8601String() ?? '-',
                        ),
                        if (capture.latitude != null)
                          _DetailRow(
                            icon: Icons.my_location_outlined,
                            label: strings.coordinates,
                            value:
                                '${capture.latitude!.toStringAsFixed(6)}, '
                                '${capture.longitude!.toStringAsFixed(6)}',
                          ),
                        _DetailRow(
                          icon: Icons.fingerprint,
                          label: strings.originalSha256,
                          value: capture.originalSha256 ?? '-',
                          selectable: true,
                        ),
                      ],
                    ),
                  ],
                ),
        );
      },
    );
  }

  Future<void> _retry(BuildContext context, WidgetRef ref) async {
    await ref.read(captureBackgroundSchedulerProvider).retry(captureId);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final strings = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.deleteRecord),
        content: Text(strings.deleteRecordPrompt),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(strings.deleteRecord),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(captureWorkflowProvider).deleteCapture(captureId);
    if (context.mounted) context.go('/projects/$projectId');
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(children: children),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.selectable = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final valueWidget = selectable
        ? SelectableText(value, style: Theme.of(context).textTheme.bodyMedium)
        : Text(value, style: Theme.of(context).textTheme.bodyMedium);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          SizedBox(
            width: 112,
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
          Expanded(child: valueWidget),
        ],
      ),
    );
  }
}
