import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/domain/capture_failure.dart';
import 'package:sitemark/domain/capture_failure_guidance.dart';
import 'package:sitemark/domain/capture_display_name.dart';
import 'package:sitemark/domain/original_photo_state.dart';
import 'package:sitemark/features/capture/capture_image_preview.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/motion.dart';

/// Shared capture list item used by both the project detail and the global
/// all-records surfaces.
///
/// Layout: 96x96 [CaptureImagePreview] on the left, a flexible metadata column
/// in the middle, and a status icon/label pinned top-right. [showProjectName]
/// toggles the project name row (only meaningful in the global list). The card
/// stays tappable even when the preview file is missing -- the preview renders a
/// placeholder instead.
///
/// When [selectionMode] is `true`, a [Checkbox] overlays the thumbnail without
/// shifting the preview or metadata, and card taps toggle selection (via
/// [onSelectedChanged]) instead of navigating. A long press outside selection
/// mode enters selection and selects the row ([HapticFeedback.mediumImpact]);
/// every selection toggle fires [HapticFeedback.selectionClick]. Busy rows
/// (`captured` or `rendering`) expose a disabled checkbox via
/// [selectable] = `false`. Below the metadata column a [FutureBuilder] resolves
/// the localized original-photo state label (retained/cleared/missing).
///
/// The status icon/label cross-fades between states ([AnimatedSwitcher]) and is
/// merged into a single semantics label; the thumbnail carries an image
/// semantics label and, for `ready` rows, a [Hero] tagged
/// `capture-photo-{id}` paired with the detail screen's large preview.
class CaptureRecordCard extends ConsumerStatefulWidget {
  const CaptureRecordCard({
    super.key,
    required this.summary,
    required this.onTap,
    this.showProjectName = false,
    this.selectionMode = false,
    this.selected = false,
    this.selectable = true,
    this.onSelectedChanged,
    this.searchTerms,
  });

  final CaptureSummary summary;
  final ValueChanged<String?> onTap;
  final bool showProjectName;
  final bool selectionMode;
  final bool selected;
  final bool selectable;
  final ValueChanged<bool>? onSelectedChanged;
  final List<String>? searchTerms;

  @override
  ConsumerState<CaptureRecordCard> createState() => _CaptureRecordCardState();
}

class _CaptureRecordCardState extends ConsumerState<CaptureRecordCard> {
  late Future<OriginalPhotoState> _originalState;
  String? _resolvedPreviewPath;
  late final FutureOr<bool> Function(String) _previewFileExists =
      _previewFileExistsForPath;

  @override
  void initState() {
    super.initState();
    _originalState = _readOriginalState();
  }

  @override
  void didUpdateWidget(covariant CaptureRecordCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_originalStateInputsChanged(oldWidget.summary.capture)) {
      _originalState = _readOriginalState();
    }
  }

  Future<OriginalPhotoState> _readOriginalState() {
    return ref
        .read(captureMediaServiceProvider)
        .originalState(widget.summary.capture);
  }

  Future<bool> _previewFileExistsForPath(String path) async {
    if (path == widget.summary.capture.originalPath) {
      return await _originalState == OriginalPhotoState.retained;
    }
    return File(path).exists();
  }

  bool _originalStateInputsChanged(CaptureRecord previous) {
    final current = widget.summary.capture;
    return previous.id != current.id ||
        previous.originalPath != current.originalPath ||
        previous.originalDeletedAt != current.originalDeletedAt;
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final capture = widget.summary.capture;
    final (label, icon, color) = _statusPresentation(capture.status, strings);
    final searchSnippet = _searchSnippet(capture, strings);
    final VoidCallback? cardTap = widget.selectionMode
        ? widget.selectable
              ? () {
                  HapticFeedback.selectionClick();
                  widget.onSelectedChanged?.call(!widget.selected);
                }
              : null
        : () => widget.onTap(_resolvedPreviewPath);
    final thumbnail = SizedBox(
      width: 96,
      height: 96,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CaptureImagePreview(
          capture: capture,
          outputPaths: ref.watch(captureOutputPathsProvider),
          thumbnail: true,
          fileExists: _previewFileExists,
          heroTag: capture.status == CaptureStatus.ready
              ? 'capture-photo-${capture.id}'
              : null,
          onImageResolved: (path) => _resolvedPreviewPath = path,
        ),
      ),
    );
    final preview = Semantics(
      image: true,
      label: strings.photoSemanticsLabel(
        capture.photoNumber ?? capture.workLocation,
      ),
      child: Stack(
        children: [
          thumbnail,
          if (widget.selectionMode)
            Positioned(
              key: const Key('capture-selection-overlay'),
              left: 4,
              top: 4,
              child: Material(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: .92),
                borderRadius: BorderRadius.circular(8),
                child: SizedBox.square(
                  dimension: 40,
                  child: Checkbox(
                    value: widget.selected,
                    onChanged: widget.selectable
                        ? (value) {
                            HapticFeedback.selectionClick();
                            widget.onSelectedChanged?.call(value ?? false);
                          }
                        : null,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                captureListDisplayName(
                  capturedAt: capture.capturedAt,
                  photoNumber: capture.photoNumber,
                  fallback: capture.workLocation,
                ),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Semantics(
              label: '${strings.statusSemanticsPrefix}: $label',
              child: ExcludeSemantics(
                child: AnimatedSwitcher(
                  duration: AppMotion.durationOf(context, AppMotion.short4),
                  child: Row(
                    key: ValueKey(capture.status),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 18, color: color),
                      const SizedBox(width: 4),
                      Text(label, style: TextStyle(color: color)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (widget.showProjectName) ...[
          Text(
            widget.summary.projectName,
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
        ],
        Text(
          '${capture.workLocation} · ${capture.workContent}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 2),
        Text(
          capture.photographer,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (searchSnippet != null) ...[
          const SizedBox(height: 2),
          Text(
            searchSnippet,
            key: const Key('capture-search-snippet'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
        if (capture.failureReason != null) ...[
          const SizedBox(height: 4),
          Text(
            strings.captureFailureGuidanceMessage(
              captureFailureGuidanceForList(
                CaptureFailureCode.fromStorage(capture.failureReason),
              ),
            ),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        FutureBuilder<OriginalPhotoState>(
          future: _originalState,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox.shrink();
            }
            final state = snapshot.data;
            if (state == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _originalStateLabel(state, strings),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            );
          },
        ),
      ],
    );
    final useStackedLayout = MediaQuery.textScalerOf(context).scale(14) >= 21;
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      color: widget.selected
          ? colors.secondaryContainer.withValues(alpha: .45)
          : null,
      shape: widget.selected
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: colors.primary, width: 2),
            )
          : null,
      child: InkWell(
        onTap: cardTap,
        onLongPress: !widget.selectionMode && widget.selectable
            ? () {
                HapticFeedback.mediumImpact();
                widget.onSelectedChanged?.call(true);
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: useStackedLayout
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [preview]),
                    const SizedBox(height: 8),
                    details,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    preview,
                    const SizedBox(width: 12),
                    Expanded(child: details),
                  ],
                ),
        ),
      ),
    );
  }

  String _originalStateLabel(OriginalPhotoState state, AppStrings strings) {
    return switch (state) {
      OriginalPhotoState.retained => strings.originalRetained,
      OriginalPhotoState.cleared => strings.originalCleared,
      OriginalPhotoState.missing => strings.originalMissing,
    };
  }

  String? _searchSnippet(CaptureRecord capture, AppStrings strings) {
    final terms = widget.searchTerms
        ?.map((term) => term.trim().toLowerCase())
        .where((term) => term.isNotEmpty)
        .toList(growable: false);
    if (terms == null || terms.isEmpty) return null;

    bool matches(String? value) {
      if (value == null || value.isEmpty) return false;
      final normalized = value.toLowerCase();
      return terms.any(normalized.contains);
    }

    if (matches(capture.notes)) {
      return strings.captureSearchNotes(capture.notes!);
    }
    if (matches(capture.address)) {
      return strings.captureSearchAddress(capture.address!);
    }
    if (matches(capture.photoNumber)) {
      return strings.captureSearchPhotoNumber(capture.photoNumber!);
    }
    return null;
  }

  (String, IconData, Color) _statusPresentation(
    CaptureStatus status,
    AppStrings strings,
  ) {
    return switch (status) {
      CaptureStatus.ready => (
        strings.ready,
        Icons.check_circle_outline,
        Colors.green,
      ),
      CaptureStatus.failed => (strings.failed, Icons.error_outline, Colors.red),
      CaptureStatus.pendingCamera => (
        strings.pendingCamera,
        Icons.photo_camera_outlined,
        Colors.orange,
      ),
      CaptureStatus.captured => (
        strings.waitingForProcessing,
        Icons.hourglass_top,
        Colors.orange,
      ),
      CaptureStatus.rendering => (
        strings.processing,
        Icons.auto_awesome_outlined,
        Colors.blue,
      ),
    };
  }
}
