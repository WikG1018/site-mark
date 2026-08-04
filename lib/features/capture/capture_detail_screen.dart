import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_display_name.dart';
import 'package:sitemark/domain/capture_failure.dart';
import 'package:sitemark/domain/capture_failure_guidance.dart';
import 'package:sitemark/domain/capture_file_info.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/domain/original_photo_state.dart';
import 'package:sitemark/domain/project_lifecycle.dart';
import 'package:sitemark/features/capture/capture_detail_action_sheet.dart';
import 'package:sitemark/features/capture/capture_detail_tabs.dart';
import 'package:sitemark/features/capture/capture_fullscreen_sequence.dart';
import 'package:sitemark/features/capture/capture_image_preview.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/motion.dart';
import 'package:sitemark/workflow/capture_media_service.dart';

final class CaptureDetailArguments {
  const CaptureDetailArguments({
    required this.capture,
    required this.initialImagePath,
    this.navigationContext,
  });

  final CaptureRecord capture;
  final String? initialImagePath;

  final CaptureNavigationContext? navigationContext;
}

/// Photo detail surface with explicit watermarked/original preview, file
/// metadata, and dual destructive actions.
///
/// The screen watches [AppDatabase.watchCaptureById] for the row and resolves
/// [CaptureMediaService.inspect] via a [FutureBuilder] so the file metadata
/// refreshes whenever the row changes (e.g. after clearing the original).
///
/// When the original is retained a [SegmentedButton] lets the user switch the
/// preview between the watermarked photo and the private original (the preview
/// cross-fades via [AnimatedSwitcher]). When the original is cleared or missing
/// the segmented control is hidden and the preview is forced to the watermarked
/// photo. For `ready` records the preview pairs with the list thumbnail through
/// a [Hero] tagged `capture-photo-{id}`.
///
/// Clearing the original is deferred: the action shows an undo [SnackBar] and
/// only executes after a five-second window unless undone. Deleting everything
/// keeps an [AlertDialog] confirmation with a red [FilledButton].
class CaptureDetailScreen extends ConsumerStatefulWidget {
  const CaptureDetailScreen({
    super.key,
    required this.projectId,
    required this.captureId,
    this.initialCapture,
    this.initialImagePath,
    this.navigationContext,
  });

  final String projectId;
  final String captureId;
  final CaptureRecord? initialCapture;
  final String? initialImagePath;
  final CaptureNavigationContext? navigationContext;

  @override
  ConsumerState<CaptureDetailScreen> createState() =>
      _CaptureDetailScreenState();
}

class _CaptureDetailScreenState extends ConsumerState<CaptureDetailScreen> {
  static const Duration _clearOriginalsWindow = Duration(seconds: 5);

  CapturePreviewSource _previewSource = CapturePreviewSource.bestAvailable;
  CaptureDetailSection _section = CaptureDetailSection.fieldRecord;
  Future<CaptureFileInfo>? _fileInfoFuture;
  String? _fileInfoKey;
  Timer? _clearOriginalsTimer;

  @override
  void dispose() {
    _clearOriginalsTimer?.cancel();
    super.dispose();
  }

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
    final querySource = ref.watch(captureQueryRepositoryProvider);
    return StreamBuilder<Project?>(
      stream: database.watchProjectById(_projectId),
      builder: (context, projectSnapshot) {
        final projectActive =
            projectSnapshot.data?.lifecycleStatus ==
            ProjectLifecycleStatus.active;
        return StreamBuilder<CaptureRecord?>(
          stream: database.watchCaptureById(_captureId),
          initialData: widget.initialCapture,
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
                final effectiveSource = info == null
                    ? capture.originalDeletedAt != null
                          ? CapturePreviewSource.watermarked
                          : CapturePreviewSource.bestAvailable
                    : originalRetained
                    ? _previewSource
                    : CapturePreviewSource.watermarked;
                final failureCode = capture.status == CaptureStatus.failed
                    ? CaptureFailureCode.fromStorage(capture.failureReason)
                    : null;
                final failureGuidance =
                    failureCode != null &&
                        info != null &&
                        projectSnapshot.hasData
                    ? captureFailureGuidanceForDetail(
                        code: failureCode,
                        originalState: info.originalState,
                        projectActive: projectActive,
                      )
                    : null;
                final canRetry = failureGuidance?.canRetry == true;
                final settled =
                    capture.status == CaptureStatus.ready ||
                    capture.status == CaptureStatus.failed;
                final canDeleteRecord = projectActive && settled;
                final canEdit =
                    projectActive &&
                    capture.status == CaptureStatus.ready &&
                    originalRetained;
                final canDeleteOriginal =
                    projectActive && settled && originalRetained;
                final heroTag = capture.status == CaptureStatus.ready
                    ? 'capture-photo-${capture.id}'
                    : null;
                Widget preview = AspectRatio(
                  aspectRatio: 4 / 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AnimatedSwitcher(
                      duration: AppMotion.medium2,
                      child: CaptureImagePreview(
                        // Keep the destination element alive if an unexpected
                        // missing original makes bestAvailable resolve to the
                        // same rendered file as the explicit watermarked source.
                        key: ValueKey('capture-preview-${capture.id}'),
                        capture: capture,
                        outputPaths: outputPaths,
                        source: effectiveSource,
                        heroDestination: heroTag != null,
                        initialImagePath: widget.initialImagePath,
                        navigationContext: widget.navigationContext,
                        querySource: querySource,
                      ),
                    ),
                  ),
                );
                if (heroTag != null) {
                  // Keep one HeroState alive while file metadata and preview
                  // resolution arrive. Replacing the Hero during a forward
                  // flight makes Flutter abandon the destination shuttle.
                  preview = Hero(
                    key: ValueKey('capture-photo-slot-${capture.id}'),
                    tag: heroTag,
                    child: preview,
                  );
                }
                final title = captureListDisplayName(
                  capturedAt: capture.capturedAt,
                  photoNumber: capture.photoNumber,
                  fallback: strings.captureDetail,
                );
                return Scaffold(
                  appBar: AppBar(
                    title: Text(title),
                    actions: [
                      if (canDeleteRecord)
                        Semantics(
                          key: const Key('capture-detail-actions'),
                          label: MaterialLocalizations.of(
                            context,
                          ).moreButtonTooltip,
                          button: true,
                          onTap: () => _openActions(
                            capture,
                            canEdit: canEdit,
                            canDeleteOriginal: canDeleteOriginal,
                          ),
                          child: ExcludeSemantics(
                            child: IconButton(
                              onPressed: () => _openActions(
                                capture,
                                canEdit: canEdit,
                                canDeleteOriginal: canDeleteOriginal,
                              ),
                              tooltip: MaterialLocalizations.of(
                                context,
                              ).moreButtonTooltip,
                              icon: const Icon(Icons.more_vert),
                            ),
                          ),
                        ),
                    ],
                  ),
                  body: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (failureGuidance != null)
                            Container(
                              key: const Key('capture-failure-guidance'),
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onErrorContainer,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      strings.captureFailureGuidanceMessage(
                                        failureGuidance,
                                      ),
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onErrorContainer,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (canRetry)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: FilledButton.icon(
                                key: const Key('capture-retry-processing'),
                                onPressed: _retry,
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
                          preview,
                          const SizedBox(height: 14),
                          CaptureDetailTabs(
                            value: _section,
                            onChanged: (section) => setState(() {
                              _section = section;
                            }),
                          ),
                          const SizedBox(height: 14),
                          if (_section == CaptureDetailSection.fieldRecord)
                            _DetailCard(
                              children: _fieldRecordRows(strings, capture),
                            )
                          else if (info != null)
                            _DetailCard(
                              children: _fileInfoRows(strings, capture, info),
                            )
                          else
                            const Center(child: CircularProgressIndicator()),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  List<Widget> _fieldRecordRows(AppStrings strings, CaptureRecord capture) {
    return [
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
      _DetailRow(
        icon: Icons.schedule_outlined,
        label: strings.capturedAt,
        value: capture.capturedAt?.toIso8601String() ?? '-',
      ),
      if (capture.latitude != null && capture.longitude != null)
        _DetailRow(
          icon: Icons.my_location_outlined,
          label: strings.coordinates,
          value:
              '${capture.latitude!.toStringAsFixed(6)}, '
              '${capture.longitude!.toStringAsFixed(6)}',
        ),
    ];
  }

  List<Widget> _fileInfoRows(
    AppStrings strings,
    CaptureRecord capture,
    CaptureFileInfo info,
  ) {
    final rows = <Widget>[
      _DetailRow(
        icon: Icons.badge_outlined,
        label: strings.fullFileName,
        value: capture.photoNumber == null
            ? '-'
            : capture.photoNumber!.toLowerCase().endsWith('.jpg')
            ? capture.photoNumber!
            : '${capture.photoNumber}.jpg',
        selectable: true,
      ),
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
    rows.add(
      _DetailRow(
        icon: Icons.fingerprint,
        label: strings.originalSha256,
        value: capture.originalSha256 ?? '-',
        selectable: true,
      ),
    );
    return rows;
  }

  Future<void> _openActions(
    CaptureRecord capture, {
    required bool canEdit,
    required bool canDeleteOriginal,
  }) async {
    final projectId = _projectId;
    final captureId = capture.id;
    final action = await showCaptureDetailActionSheet(
      context,
      canEdit: canEdit,
      canDeleteOriginal: canDeleteOriginal,
    );
    if (!mounted || action == null) return;
    if (_projectId != projectId || _captureId != captureId) return;

    final current = await _currentCaptureForAction(
      action,
      projectId: projectId,
      captureId: captureId,
    );
    if (!mounted || current == null) return;
    switch (action) {
      case CaptureDetailAction.edit:
        unawaited(
          context.push('/projects/$projectId/captures/$captureId/edit'),
        );
        return;
      case CaptureDetailAction.deleteOriginal:
        _deleteOriginal(current);
        return;
      case CaptureDetailAction.deleteRecord:
        await _deleteAll(current);
        return;
    }
  }

  Future<CaptureRecord?> _currentCaptureForAction(
    CaptureDetailAction action, {
    required String projectId,
    required String captureId,
  }) async {
    final database = ref.read(databaseProvider);
    final mediaService = ref.read(captureMediaServiceProvider);
    final project = await database.projectById(projectId);
    if (!_matchesActionScope(projectId, captureId)) return null;
    final capture = await database.captureById(captureId);
    if (!_matchesActionScope(projectId, captureId)) return null;
    if (!_baseActionAllowed(action, project, capture)) return null;

    OriginalPhotoState? inspectedOriginalState;
    if (_requiresRetainedOriginal(action)) {
      final info = await mediaService.inspect(capture!);
      if (!_matchesActionScope(projectId, captureId)) return null;
      inspectedOriginalState = info.originalState;
      if (inspectedOriginalState != OriginalPhotoState.retained) return null;
    }

    // Keep the final database consistency window short. File inspection above
    // never runs inside this transaction.
    final latest = await database.transaction(() async {
      final latestProject = await database.projectById(projectId);
      if (!_matchesActionScope(projectId, captureId)) return null;
      final latestCapture = await database.captureById(captureId);
      if (!_matchesActionScope(projectId, captureId)) return null;
      if (latestProject == null || latestCapture == null) return null;
      return (project: latestProject, capture: latestCapture);
    });
    if (!_matchesActionScope(projectId, captureId) || latest == null) {
      return null;
    }
    if (!_finalActionAllowed(
      action,
      latest.project,
      latest.capture,
      inspectedOriginalState,
    )) {
      return null;
    }
    return latest.capture;
  }

  bool _matchesActionScope(String projectId, String captureId) =>
      mounted && _projectId == projectId && _captureId == captureId;

  bool _baseActionAllowed(
    CaptureDetailAction action,
    Project? project,
    CaptureRecord? capture,
  ) {
    if (project?.lifecycleStatus != ProjectLifecycleStatus.active ||
        capture == null ||
        capture.projectId != project?.id) {
      return false;
    }
    final statusAllowed = switch (action) {
      CaptureDetailAction.edit => capture.status == CaptureStatus.ready,
      CaptureDetailAction.deleteOriginal || CaptureDetailAction.deleteRecord =>
        capture.status == CaptureStatus.ready ||
            capture.status == CaptureStatus.failed,
    };
    if (!statusAllowed) return false;
    return !_requiresRetainedOriginal(action) ||
        capture.originalDeletedAt == null;
  }

  bool _finalActionAllowed(
    CaptureDetailAction action,
    Project project,
    CaptureRecord capture,
    OriginalPhotoState? inspectedOriginalState,
  ) {
    return _baseActionAllowed(action, project, capture) &&
        (!_requiresRetainedOriginal(action) ||
            inspectedOriginalState == OriginalPhotoState.retained);
  }

  bool _requiresRetainedOriginal(CaptureDetailAction action) =>
      action == CaptureDetailAction.edit ||
      action == CaptureDetailAction.deleteOriginal;

  Future<void> _retry() async {
    await ref.read(captureBackgroundSchedulerProvider).retry(_captureId);
  }

  void _deleteOriginal(CaptureRecord capture) {
    final strings = AppStrings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    _clearOriginalsTimer?.cancel();
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(strings.clearOriginalsScheduled(1)),
        duration: _clearOriginalsWindow,
        action: SnackBarAction(
          label: strings.undo,
          onPressed: () {
            _clearOriginalsTimer?.cancel();
            _clearOriginalsTimer = null;
            messenger.hideCurrentSnackBar();
          },
        ),
      ),
    );
    _clearOriginalsTimer = Timer(_clearOriginalsWindow, () {
      _clearOriginalsTimer = null;
      _executeClearOriginals(capture);
    });
  }

  Future<void> _executeClearOriginals(CaptureRecord capture) async {
    final current = await _currentCaptureForAction(
      CaptureDetailAction.deleteOriginal,
      projectId: capture.projectId,
      captureId: capture.id,
    );
    if (!mounted || current == null) return;
    final strings = AppStrings.of(context);
    final result = await ref.read(captureMediaServiceProvider).clearOriginals([
      current.id,
    ]);
    if (!mounted) return;
    final failure = result.failures[current.id];
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
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () {
              HapticFeedback.heavyImpact();
              Navigator.pop(dialogContext, true);
            },
            child: Text(strings.deleteAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final current = await _currentCaptureForAction(
      CaptureDetailAction.deleteRecord,
      projectId: capture.projectId,
      captureId: capture.id,
    );
    if (!mounted || current == null) return;
    final result = await ref.read(captureMediaServiceProvider).deleteAll([
      current.id,
    ]);
    if (!mounted) return;
    if (result.succeededIds.contains(current.id)) {
      context.go('/projects/$_projectId');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.failures[current.id] ?? strings.deleteRecord),
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
