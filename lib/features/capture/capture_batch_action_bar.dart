import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sitemark/features/capture/capture_selection_controller.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/shared/ui/floating_dock_layout.dart';
import 'package:sitemark/shared/ui/glass_surface.dart';
import 'package:sitemark/workflow/capture_media_service.dart';
import 'package:sitemark/workflow/project_export_service.dart';

/// Bottom action bar shown on capture list screens while in selection mode.
///
/// Hosts four equal-width actions: export selection, save to gallery
/// (republish), clear originals, and delete all. Export/republish are disabled
/// unless every selected row is `ready`; every action is disabled when the
/// selection is empty. Delete-all keeps a count-aware confirmation dialog with
/// a red confirm button; clear-originals runs on a 5-second delayed timer with
/// a Snackbar "undo" window instead of a dialog. Each action executes service
/// work sequentially across the selected IDs, surfaces a `completed/total`
/// progress line under a [LinearProgressIndicator], and reports the aggregated
/// success/skipped/failed counts in a Snackbar when done.
class CaptureBatchActionBar extends StatefulWidget {
  const CaptureBatchActionBar({
    super.key,
    required this.controller,
    required this.mediaService,
    required this.exportService,
    required this.shareService,
  });

  final CaptureSelectionController controller;
  final CaptureMediaService mediaService;
  final ProjectExportService exportService;
  final ShareFileService shareService;

  @override
  State<CaptureBatchActionBar> createState() => _CaptureBatchActionBarState();
}

class _CaptureBatchActionBarState extends State<CaptureBatchActionBar> {
  bool _busy = false;
  bool _exporting = false;
  int _completed = 0;
  int _total = 0;

  /// Pending clear-originals execution. Set while the 5-second undo window is
  /// open; cancelled by the Snackbar undo action or by [dispose].
  Timer? _clearOriginalsTimer;
  ScaffoldMessengerState? _clearOriginalsMessenger;

  @override
  void dispose() {
    if (_clearOriginalsTimer != null) {
      // Exiting selection cancels the pending run; withdraw the snackbar too
      // so it doesn't keep implying a cleanup that will never happen.
      _clearOriginalsMessenger?.hideCurrentSnackBar();
    }
    _clearOriginalsTimer?.cancel();
    super.dispose();
  }

  List<String> get _selectedIds => widget.controller.selectedIds.toList();

  Future<void> _runSnapshotWithProgress(
    String snackbarTitle,
    List<String> ids,
    Future<CaptureActionResult> Function(List<String> ids) op, {
    required ScaffoldMessengerState? messenger,
    required AppStrings strings,
    required CaptureSelectionController controller,
  }) async {
    final snapshot = List<String>.unmodifiable(ids);
    if (snapshot.isEmpty) return;
    if (mounted) {
      setState(() {
        _busy = true;
        _exporting = false;
        _completed = 0;
        _total = snapshot.length;
      });
    }
    var succeeded = 0;
    var skipped = 0;
    var failed = 0;
    try {
      for (var i = 0; i < snapshot.length; i++) {
        final result = await op([snapshot[i]]);
        succeeded += result.succeededIds.length;
        skipped += result.skippedIds.length;
        failed += result.failures.length;
        if (mounted) setState(() => _completed = i + 1);
      }
    } catch (error) {
      failed += snapshot.length;
      if (mounted) {
        _showResult(
          messenger,
          strings,
          controller,
          snackbarTitle,
          succeeded,
          skipped,
          failed,
        );
      }
      return;
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _exporting = false;
          _completed = 0;
          _total = 0;
        });
      }
    }
    if (mounted) {
      _showResult(
        messenger,
        strings,
        controller,
        snackbarTitle,
        succeeded,
        skipped,
        failed,
      );
    }
  }

  void _showResult(
    ScaffoldMessengerState? messenger,
    AppStrings strings,
    CaptureSelectionController controller,
    String title,
    int succeeded,
    int skipped,
    int failed,
  ) {
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '$title · ${strings.actionResult(succeeded, skipped, failed)}',
        ),
        action: SnackBarAction(
          label: strings.viewAction,
          onPressed: controller.exit,
        ),
      ),
    );
  }

  Future<bool?> _confirm(
    String title,
    String message, {
    required String cancelLabel,
    required String deleteLabel,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () {
              HapticFeedback.heavyImpact();
              Navigator.pop(dialogContext, true);
            },
            child: Text(deleteLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _export() async {
    final ids = _selectedIds;
    final controller = widget.controller;
    if (ids.isEmpty || !controller.allSelectedReady) return;
    final exportService = widget.exportService;
    final shareService = widget.shareService;
    final strings = AppStrings.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() {
      _busy = true;
      _exporting = true;
      _completed = 0;
      _total = 1;
    });
    try {
      final result = await exportService.exportSelection(
        captureIds: ids,
        includeOriginals: false,
      );
      await shareService.shareFile(result.outputZipPath);
      if (mounted) {
        _showResult(
          messenger,
          strings,
          controller,
          strings.exportSelection,
          ids.length,
          0,
          0,
        );
      }
    } catch (error) {
      if (mounted) {
        _showResult(
          messenger,
          strings,
          controller,
          strings.exportSelection,
          0,
          0,
          ids.length,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _exporting = false;
          _completed = 0;
          _total = 0;
        });
      }
    }
  }

  Future<void> _republish() async {
    final controller = widget.controller;
    if (!controller.allSelectedReady) return;
    final ids = _selectedIds;
    final mediaService = widget.mediaService;
    final strings = AppStrings.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    await _runSnapshotWithProgress(
      strings.saveToGallery,
      ids,
      mediaService.republish,
      messenger: messenger,
      strings: strings,
      controller: controller,
    );
  }

  /// Schedules the clear-originals run after a 5-second undo window instead of
  /// asking for confirmation up front. The Snackbar action cancels the pending
  /// timer; only expiry executes the deletion.
  void _clearOriginals() {
    final ids = _selectedIds;
    if (ids.isEmpty || _busy || _clearOriginalsTimer != null) return;
    final strings = AppStrings.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    _clearOriginalsMessenger = messenger;
    _clearOriginalsTimer = Timer(const Duration(seconds: 5), () {
      _clearOriginalsTimer = null;
      _executeClearOriginals(ids);
    });
    messenger?.showSnackBar(
      SnackBar(
        content: Text(strings.clearOriginalsScheduled(ids.length)),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: strings.undo,
          onPressed: () {
            _clearOriginalsTimer?.cancel();
            _clearOriginalsTimer = null;
          },
        ),
      ),
    );
  }

  Future<void> _executeClearOriginals(List<String> ids) async {
    if (!mounted) return;
    final controller = widget.controller;
    final mediaService = widget.mediaService;
    final strings = AppStrings.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    await _runSnapshotWithProgress(
      strings.clearOriginals,
      ids,
      mediaService.clearOriginals,
      messenger: messenger,
      strings: strings,
      controller: controller,
    );
    // Exit selection mode so the cleared state is visible in the cards.
    if (mounted) controller.exit();
  }

  Future<void> _deleteAll() async {
    final ids = _selectedIds;
    if (ids.isEmpty) return;
    final controller = widget.controller;
    final mediaService = widget.mediaService;
    final strings = AppStrings.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final confirmed = await _confirm(
      strings.deleteAll,
      strings.confirmDeleteAll(ids.length),
      cancelLabel: strings.cancel,
      deleteLabel: strings.deleteAction,
    );
    if (confirmed != true) return;
    await _runSnapshotWithProgress(
      strings.deleteAll,
      ids,
      mediaService.deleteAll,
      messenger: messenger,
      strings: strings,
      controller: controller,
    );
    if (mounted) controller.exit();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final ids = _selectedIds;
        final empty = ids.isEmpty;
        final ready = widget.controller.allSelectedReady;
        final selectedLabel = strings.selectedCount(ids.length);
        final useCountOnly = MediaQuery.textScalerOf(context).scale(14) > 22;
        return GlassSurface(
          key: const Key('batch-action-bar'),
          borderRadius: BorderRadius.circular(22),
          child: SizedBox(
            height: floatingDockHeight,
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 56,
                      child: _busy
                          ? _CompactProgress(
                              exporting: _exporting,
                              completed: _completed,
                              total: _total,
                            )
                          : Semantics(
                              label: selectedLabel,
                              child: Text(
                                useCountOnly ? '${ids.length}' : selectedLabel,
                                key: const Key('batch-selected-count'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ),
                    ),
                    const VerticalDivider(width: 6, indent: 14, endIndent: 14),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: _ActionButton(
                              actionKey: 'export',
                              icon: Icons.archive_outlined,
                              label: strings.exportSelection,
                              enabled: !empty && ready && !_busy,
                              onPressed: _export,
                            ),
                          ),
                          Expanded(
                            child: _ActionButton(
                              actionKey: 'gallery',
                              icon: Icons.save_outlined,
                              label: strings.saveToGallery,
                              enabled: !empty && ready && !_busy,
                              onPressed: _republish,
                            ),
                          ),
                          Expanded(
                            child: _ActionButton(
                              actionKey: 'originals',
                              icon: Icons.cleaning_services_outlined,
                              label: strings.clearOriginals,
                              enabled: !empty && !_busy,
                              onPressed: _clearOriginals,
                            ),
                          ),
                          Expanded(
                            child: _ActionButton(
                              actionKey: 'delete',
                              icon: Icons.delete_outline,
                              label: strings.deleteAll,
                              enabled: !empty && !_busy,
                              errorAction: true,
                              onPressed: _deleteAll,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CompactProgress extends StatelessWidget {
  const _CompactProgress({
    required this.exporting,
    required this.completed,
    required this.total,
  });

  final bool exporting;
  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final label = exporting
        ? strings.exportSelection
        : strings.actionProgress(completed, total);
    return Semantics(
      label: label,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          LinearProgressIndicator(
            minHeight: 2,
            value: total == 0 ? null : completed / total,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.actionKey,
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onPressed,
    this.errorAction = false,
  });

  final String actionKey;
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onPressed;
  final bool errorAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = !enabled
        ? scheme.onSurface.withValues(alpha: .38)
        : errorAction
        ? scheme.error
        : scheme.onSurfaceVariant;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        child: Material(
          key: Key('batch-action-$actionKey-surface'),
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            borderRadius: BorderRadius.circular(12),
            child: Center(
              child: ExcludeSemantics(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 21, color: foreground),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: foreground,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
