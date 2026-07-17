import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_file_info.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/domain/original_photo_state.dart';
import 'package:sitemark/features/capture/capture_image_preview.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/workflow/capture_media_service.dart';

/// Photo detail surface with explicit watermarked/original preview, file
/// metadata, and dual destructive actions.
///
/// The screen watches [AppDatabase.watchCaptureById] for the row and resolves
/// [CaptureMediaService.inspect] via a [FutureBuilder] so the file metadata
/// refreshes whenever the row changes (e.g. after clearing the original).
///
/// When the original is retained a [SegmentedButton] lets the user switch the
/// preview between the watermarked photo and the private original. When the
/// original is cleared or missing the segmented control is hidden and the
/// preview is forced to the watermarked photo.
class CaptureDetailScreen extends ConsumerStatefulWidget {
  const CaptureDetailScreen({
    super.key,
    required this.projectId,
    required this.captureId,
  });

  final String projectId;
  final String captureId;

  @override
  ConsumerState<CaptureDetailScreen> createState() =>
      _CaptureDetailScreenState();
}

class _CaptureDetailScreenState extends ConsumerState<CaptureDetailScreen> {
  CapturePreviewSource _previewSource = CapturePreviewSource.bestAvailable;
  Future<CaptureFileInfo>? _fileInfoFuture;
  String? _fileInfoKey;

  String get _projectId => widget.projectId;
  String get _captureId => widget.captureId;

  Future<CaptureFileInfo> _fileInfoFor(
    CaptureRecord capture,
    CaptureMediaService mediaService,
  ) {
    final key =
        '${capture.id}:${capture.status.name}:'
        '${capture.originalDeletedAt?.microsecondsSinceEpoch}:'
        '${capture.publishedUri}';
    if (_fileInfoFuture == null || _fileInfoKey != key) {
      _fileInfoKey = key;
      _fileInfoFuture = mediaService.inspect(capture);
    }
    return _fileInfoFuture!;
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final database = ref.watch(databaseProvider);
    final mediaService = ref.watch(captureMediaServiceProvider);
    final outputPaths = ref.watch(captureOutputPathsProvider);
    return StreamBuilder<CaptureRecord?>(
      stream: database.watchCaptureById(_captureId),
      builder: (context, snapshot) {
        final capture = snapshot.data;
        if (capture == null) {
          return Scaffold(
            appBar: AppBar(title: Text(strings.captureDetail)),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        return FutureBuilder<CaptureFileInfo>(
          future: _fileInfoFor(capture, mediaService),
          builder: (context, infoSnapshot) {
            final info = infoSnapshot.data;
            final originalRetained =
                info?.originalState == OriginalPhotoState.retained;
            final effectiveSource = originalRetained
                ? _previewSource
                : CapturePreviewSource.watermarked;
            final canRetry =
                capture.status == CaptureStatus.failed && originalRetained;
            final isBusy =
                capture.status == CaptureStatus.captured ||
                capture.status == CaptureStatus.rendering;
            return Scaffold(
              appBar: AppBar(
                title: Text(capture.photoNumber ?? strings.captureDetail),
                actions: [
                  if (!isBusy && originalRetained)
                    IconButton(
                      onPressed: () => context.go(
                        '/projects/$_projectId/captures/$_captureId/edit',
                      ),
                      tooltip: strings.editRecord,
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  if (!isBusy && originalRetained)
                    IconButton(
                      key: const Key('delete-original'),
                      onPressed: () => _deleteOriginal(capture),
                      tooltip: strings.deleteOriginal,
                      icon: const Icon(Icons.cleaning_services_outlined),
                    ),
                  if (!isBusy)
                    IconButton(
                      key: const Key('delete-all'),
                      onPressed: () => _deleteAll(capture),
                      tooltip: strings.deleteAll,
                      icon: const Icon(Icons.delete_sweep_outlined),
                    ),
                ],
              ),
              body: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (canRetry)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: FilledButton.icon(
                            onPressed: () => _retry(),
                            icon: const Icon(Icons.refresh),
                            label: Text(strings.retryProcessing),
                          ),
                        ),
                      if (originalRetained)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _PreviewSourceToggle(
                            source: _previewSource,
                            onChanged: (source) => setState(() {
                              _previewSource = source;
                            }),
                          ),
                        ),
                      AspectRatio(
                        aspectRatio: 4 / 3,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: CaptureImagePreview(
                            capture: capture,
                            outputPaths: outputPaths,
                            source: effectiveSource,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (info != null)
                        _DetailCard(
                          children: _fileInfoRows(strings, capture, info),
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
                ],
              ),
            );
          },
        );
      },
    );
  }

  List<Widget> _fileInfoRows(
    AppStrings strings,
    CaptureRecord capture,
    CaptureFileInfo info,
  ) {
    final rows = <Widget>[
      _DetailRow(
        icon: Icons.photo_library_outlined,
        label: strings.originalPhoto,
        value: switch (info.originalState) {
          OriginalPhotoState.retained => strings.originalRetained,
          OriginalPhotoState.cleared => strings.originalCleared,
          OriginalPhotoState.missing => strings.originalMissing,
        },
      ),
    ];
    if (info.original != null) {
      rows.add(
        _DetailRow(
          icon: Icons.photo_outlined,
          label: '${strings.originalPhoto} · ${strings.fileSize}',
          value: formatBytes(info.original!.fileSizeBytes),
        ),
      );
      rows.add(
        _DetailRow(
          icon: Icons.aspect_ratio_outlined,
          label: '${strings.originalPhoto} · ${strings.resolution}',
          value: '${info.original!.width} × ${info.original!.height}',
        ),
      );
      rows.add(
        _DetailRow(
          icon: Icons.text_snippet_outlined,
          label: '${strings.originalPhoto} · ${strings.format}',
          value: info.original!.mimeType,
        ),
      );
    }
    if (info.watermarked != null) {
      rows.add(
        _DetailRow(
          icon: Icons.photo_outlined,
          label: '${strings.watermarkedPhoto} · ${strings.fileSize}',
          value: formatBytes(info.watermarked!.fileSizeBytes),
        ),
      );
      rows.add(
        _DetailRow(
          icon: Icons.aspect_ratio_outlined,
          label: '${strings.watermarkedPhoto} · ${strings.resolution}',
          value: '${info.watermarked!.width} × ${info.watermarked!.height}',
        ),
      );
      rows.add(
        _DetailRow(
          icon: Icons.text_snippet_outlined,
          label: '${strings.watermarkedPhoto} · ${strings.format}',
          value: info.watermarked!.mimeType,
        ),
      );
    }
    rows.add(
      _DetailRow(
        icon: Icons.publish_outlined,
        label: strings.publishedStatus,
        value: capture.publishedUri != null
            ? strings.publishedYes
            : strings.publishedNo,
      ),
    );
    return rows;
  }

  Future<void> _retry() async {
    await ref.read(captureBackgroundSchedulerProvider).retry(_captureId);
  }

  Future<void> _deleteOriginal(CaptureRecord capture) async {
    final strings = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.deleteOriginal),
        content: Text(strings.confirmClearOriginals(1)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(strings.deleteOriginal),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final result = await ref.read(captureMediaServiceProvider).clearOriginals([
      capture.id,
    ]);
    if (!mounted) return;
    final failure = result.failures[capture.id];
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failure ??
              strings.actionResult(
                result.succeededIds.length,
                result.skippedIds.length,
                result.failures.length,
              ),
        ),
      ),
    );
  }

  Future<void> _deleteAll(CaptureRecord capture) async {
    final strings = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.deleteAll),
        content: Text(strings.confirmDeleteAll(1)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(strings.deleteAll),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final result = await ref.read(captureMediaServiceProvider).deleteAll([
      capture.id,
    ]);
    if (!mounted) return;
    if (result.succeededIds.contains(capture.id)) {
      context.go('/projects/$_projectId');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.failures[capture.id] ?? strings.deleteRecord),
        ),
      );
    }
  }
}

/// Two-segment toggle that switches the detail preview between the watermarked
/// photo and the private original. The `show-watermarked` and `show-original`
/// keys are asserted by widget tests.
class _PreviewSourceToggle extends StatelessWidget {
  const _PreviewSourceToggle({required this.source, required this.onChanged});

  final CapturePreviewSource source;
  final ValueChanged<CapturePreviewSource> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return SegmentedButton<CapturePreviewSource>(
      segments: [
        ButtonSegment(
          value: CapturePreviewSource.watermarked,
          label: Text(
            strings.watermarkedPhoto,
            key: const Key('show-watermarked'),
          ),
        ),
        ButtonSegment(
          value: CapturePreviewSource.original,
          label: Text(strings.originalPhoto, key: const Key('show-original')),
        ),
      ],
      selected: {
        source == CapturePreviewSource.bestAvailable
            ? CapturePreviewSource.watermarked
            : source,
      },
      onSelectionChanged: (selection) {
        if (selection.isNotEmpty) onChanged(selection.first);
      },
    );
  }
}

String formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '$bytes B';
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
