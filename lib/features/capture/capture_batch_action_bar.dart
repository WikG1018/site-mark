import 'package:flutter/material.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/features/capture/capture_selection_controller.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/workflow/capture_media_service.dart';
import 'package:sitemark/workflow/project_export_service.dart';

/// Bottom action bar shown on capture list screens while in selection mode.
///
/// Hosts four equal-width actions: export selection, save to gallery
/// (republish), clear originals, and delete all. Export/republish are disabled
/// unless every selected row is `ready`; every action is disabled when the
/// selection is empty. Destructive actions (clear/delete) show a count-aware
/// confirmation dialog before running. Each action executes service work
/// sequentially across the selected IDs, surfaces a `completed/total` progress
/// line, and reports the aggregated success/skipped/failed counts in a
/// Snackbar when done.
class CaptureBatchActionBar extends StatefulWidget {
  const CaptureBatchActionBar({
    super.key,
    required this.controller,
    required this.mediaService,
    required this.exportService,
    required this.shareService,
    required this.summaries,
  });

  final CaptureSelectionController controller;
  final CaptureMediaService mediaService;
  final ProjectExportService exportService;
  final ShareFileService shareService;

  /// Currently visible [CaptureSummary] rows from the host screen's filtered
  /// list. Used to resolve each selected ID to its [CaptureStatus] synchronously
  /// so the bar can disable export/republish when any row is not `ready`.
  final List<CaptureSummary> summaries;

  @override
  State<CaptureBatchActionBar> createState() => _CaptureBatchActionBarState();
}

class _CaptureBatchActionBarState extends State<CaptureBatchActionBar> {
  bool _busy = false;
  int _completed = 0;
  int _total = 0;

  List<String> get _selectedIds => widget.controller.selectedIds.toList();

  bool _allReady(List<String> ids) {
    if (ids.isEmpty) return false;
    final byId = {for (final s in widget.summaries) s.capture.id: s.capture};
    for (final id in ids) {
      final capture = byId[id];
      if (capture == null) return false;
      if (capture.status != CaptureStatus.ready) return false;
    }
    return true;
  }

  Future<void> _runWithProgress(
    String snackbarTitle,
    Future<CaptureActionResult> Function(List<String> ids) op,
  ) async {
    final ids = _selectedIds;
    if (ids.isEmpty) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() {
      _busy = true;
      _completed = 0;
      _total = ids.length;
    });
    var succeeded = 0;
    var skipped = 0;
    var failed = 0;
    try {
      for (var i = 0; i < ids.length; i++) {
        final result = await op([ids[i]]);
        succeeded += result.succeededIds.length;
        skipped += result.skippedIds.length;
        failed += result.failures.length;
        if (!mounted) return;
        setState(() => _completed = i + 1);
      }
    } catch (error) {
      failed += ids.length;
      if (mounted) {
        _showResult(messenger, snackbarTitle, succeeded, skipped, failed);
      }
      return;
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _completed = 0;
          _total = 0;
        });
      }
    }
    if (mounted) {
      _showResult(messenger, snackbarTitle, succeeded, skipped, failed);
    }
  }

  void _showResult(
    ScaffoldMessengerState? messenger,
    String title,
    int succeeded,
    int skipped,
    int failed,
  ) {
    if (messenger == null) return;
    final strings = AppStrings.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '$title · ${strings.actionResult(succeeded, skipped, failed)}',
        ),
      ),
    );
  }

  Future<bool?> _confirm(String title, String message) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(AppStrings.of(context).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(AppStrings.of(context).done),
          ),
        ],
      ),
    );
  }

  Future<void> _export() async {
    final ids = _selectedIds;
    if (ids.isEmpty || !_allReady(ids)) return;
    final strings = AppStrings.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() {
      _busy = true;
      _completed = 0;
      _total = 1;
    });
    try {
      final result = await widget.exportService.exportSelection(
        captureIds: ids,
        includeOriginals: false,
      );
      await widget.shareService.shareFile(result.outputZipPath);
      if (mounted) {
        _showResult(messenger, strings.exportSelection, ids.length, 0, 0);
      }
    } catch (error) {
      if (mounted) {
        _showResult(messenger, strings.exportSelection, 0, 0, ids.length);
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _completed = 0;
          _total = 0;
        });
      }
    }
  }

  Future<void> _republish() async {
    final strings = AppStrings.of(context);
    await _runWithProgress(
      strings.saveToGallery,
      (ids) => widget.mediaService.republish(ids),
    );
  }

  Future<void> _clearOriginals() async {
    final ids = _selectedIds;
    if (ids.isEmpty) return;
    final strings = AppStrings.of(context);
    final confirmed = await _confirm(
      strings.clearOriginals,
      strings.confirmClearOriginals(ids.length),
    );
    if (confirmed != true) return;
    await _runWithProgress(
      strings.clearOriginals,
      (ids) => widget.mediaService.clearOriginals(ids),
    );
    // Exit selection mode so the cleared state is visible in the cards.
    widget.controller.exit();
  }

  Future<void> _deleteAll() async {
    final ids = _selectedIds;
    if (ids.isEmpty) return;
    final strings = AppStrings.of(context);
    final confirmed = await _confirm(
      strings.deleteAll,
      strings.confirmDeleteAll(ids.length),
    );
    if (confirmed != true) return;
    await _runWithProgress(
      strings.deleteAll,
      (ids) => widget.mediaService.deleteAll(ids),
    );
    widget.controller.exit();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final ids = _selectedIds;
        final empty = ids.isEmpty;
        final ready = _allReady(ids);
        final exporting = _busy && _total == 1;
        return BottomAppBar(
          key: const Key('batch-action-bar'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_busy)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          exporting
                              ? strings.exportSelection
                              : strings.actionProgress(_completed, _total),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.archive_outlined,
                      label: strings.exportSelection,
                      enabled: !empty && ready && !_busy,
                      onPressed: _export,
                    ),
                  ),
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.save_outlined,
                      label: strings.saveToGallery,
                      enabled: !empty && ready && !_busy,
                      onPressed: _republish,
                    ),
                  ),
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.cleaning_services_outlined,
                      label: strings.clearOriginals,
                      enabled: !empty && !_busy,
                      onPressed: _clearOriginals,
                    ),
                  ),
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.delete_outline,
                      label: strings.deleteAll,
                      enabled: !empty && !_busy,
                      onPressed: _deleteAll,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.filledTonal(
            onPressed: enabled ? onPressed : null,
            icon: Icon(icon),
            tooltip: label,
            visualDensity: VisualDensity.compact,
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}
