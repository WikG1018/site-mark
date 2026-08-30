import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/project_lifecycle.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/shared/ui/adaptive_toast.dart';
import 'package:sitemark/shared/ui/adaptive_selection_mark.dart';
import 'package:sitemark/shared/ui/adaptive_dialog.dart';
import 'package:sitemark/shared/ui/adaptive_page_scaffold.dart';
import 'package:sitemark/shared/ui/adaptive_progress.dart';
import 'package:sitemark/workflow/project_bundle_service.dart';
import 'package:sitemark/workflow/project_backup_preflight.dart';
import 'package:sitemark_system_api/sitemark_system_api.dart';

typedef ProjectBackupExport =
    Future<ProjectBackupResult> Function({
      required List<String> projectIds,
      required bool includeOriginals,
      void Function(int completed, int total)? onProgress,
      bool allowFailedOmissions,
    });

class ProjectBackupSelectionArguments {
  const ProjectBackupSelectionArguments({this.initialProjectIds = const {}});

  final Set<String> initialProjectIds;
}

class ProjectBackupSelectionScreen extends ConsumerStatefulWidget {
  const ProjectBackupSelectionScreen({
    super.key,
    this.exportProjects,
    this.saveArchive,
    this.shareFile,
    this.initialProjectIds = const {},
  });

  final ProjectBackupExport? exportProjects;
  final Future<ArchiveSaveOutcome> Function(String path)? saveArchive;
  final Future<void> Function(String path)? shareFile;
  final Set<String> initialProjectIds;

  @override
  ConsumerState<ProjectBackupSelectionScreen> createState() =>
      _ProjectBackupSelectionScreenState();
}

class _ProjectBackupSelectionScreenState
    extends ConsumerState<ProjectBackupSelectionScreen> {
  late final Set<String> _selectedIds;
  bool _submitting = false;
  bool _saving = false;
  bool _sharing = false;
  ProjectBackupResult? _lastBackup;

  @override
  void initState() {
    super.initState();
    _selectedIds = {...widget.initialProjectIds};
  }

  void _toggleAll(List<Project> projects) {
    setState(() {
      final ids = projects.map((project) => project.id).toSet();
      if (_selectedIds.containsAll(ids)) {
        _selectedIds.removeAll(ids);
      } else {
        _selectedIds.addAll(ids);
      }
    });
  }

  Future<void> _startBackup() async {
    if (_selectedIds.isEmpty || _submitting) return;
    final strings = AppStrings.of(context);
    final snapshot = await ProjectBackupPreflightService(
      ref.read(databaseProvider),
    ).inspect(_selectedIds.toList(growable: false));
    if (!mounted) return;
    if (snapshot.processingCount > 0) {
      await showAppDialog<void>(
        context: context,
        title: Text(strings.backupWaitForProcessingTitle),
        content: Text(
          strings.backupWaitForProcessingMessage(snapshot.processingCount),
        ),
        actions: [AppDialogAction(label: strings.gotIt, isDefault: true)],
      );
      return;
    }
    var allowFailedOmissions = false;
    if (snapshot.failedCount > 0) {
      allowFailedOmissions =
          await showAppDialog<bool>(
            context: context,
            title: Text(strings.backupFailedRecordsTitle),
            content: Text(
              strings.backupFailedRecordsMessage(snapshot.failedCount),
            ),
            actions: [
              AppDialogAction(
                label: strings.backupReturnToProcess,
                result: false,
              ),
              AppDialogAction(
                label: strings.backupCompletedRecordsOnly,
                result: true,
                isDefault: true,
              ),
            ],
          ) ??
          false;
      if (!allowFailedOmissions || !mounted) return;
    }
    final includeOriginals = await showAppDialog<bool>(
      context: context,
      title: Text(strings.includePrivateOriginals),
      content: Text(strings.includePrivateOriginalsConsequence),
      actions: [
        AppDialogAction(
          key: const Key('exclude-private-originals'),
          label: strings.excludePrivateOriginals,
          result: false,
        ),
        AppDialogAction(
          key: const Key('include-private-originals'),
          label: strings.includePrivateOriginals,
          result: true,
          isDefault: true,
        ),
      ],
    );
    if (includeOriginals == null || !mounted) return;

    setState(() => _submitting = true);
    final initialTotal = _selectedIds.length == 1 ? 1 : _selectedIds.length + 1;
    final progress = ValueNotifier<(int, int)>((0, initialTotal));
    // ignore: unawaited_futures
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: buildAdaptiveAlertDialog<void>(
          dialogContext: dialogContext,
          content: ValueListenableBuilder<(int, int)>(
            valueListenable: progress,
            builder: (context, value, _) => Row(
              children: [
                const AdaptiveProgressIndicator(),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(strings.backingUpProgress(value.$1, value.$2)),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    Object? failure;
    ProjectBackupResult? result;
    try {
      final export =
          widget.exportProjects ??
          ({
            required List<String> projectIds,
            required bool includeOriginals,
            void Function(int completed, int total)? onProgress,
            bool allowFailedOmissions = false,
          }) => ref
              .read(projectBackupServiceProvider)
              .exportProjects(
                projectIds: projectIds,
                includeOriginals: includeOriginals,
                onProgress: onProgress,
                allowFailedOmissions: allowFailedOmissions,
              );
      result = await export(
        projectIds: _selectedIds.toList(growable: false),
        includeOriginals: includeOriginals,
        onProgress: (completed, total) => progress.value = (completed, total),
        allowFailedOmissions: allowFailedOmissions,
      );
    } catch (error) {
      failure = error;
    }
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      setState(() {
        _submitting = false;
        if (result != null) _lastBackup = result;
      });
    }
    progress.dispose();
    if (!mounted) return;
    if (failure != null) {
      showAppToast(context, _describeBackupError(strings, failure));
      return;
    }
    await _saveBackup(result!);
  }

  Future<void> _saveBackup(ProjectBackupResult result) async {
    if (_saving) return;
    final strings = AppStrings.of(context);
    setState(() => _saving = true);
    ArchiveSaveOutcome? outcome;
    Object? failure;
    try {
      final save =
          widget.saveArchive ??
          (path) => ref.read(archiveSaveServiceProvider).saveArchive(path);
      outcome = await save(result.outputZipPath);
    } catch (error) {
      failure = error;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    final message = failure != null
        ? strings.backupSaveFailed
        : outcome == ArchiveSaveOutcome.saved
        ? result.omittedFailedCount == 0
              ? strings.backupSaved
              : strings.backupSavedWithOmissions(result.omittedFailedCount)
        : strings.backupGeneratedNotSaved;
    showAppToast(context, message);
  }

  Future<void> _shareBackup(ProjectBackupResult result) async {
    if (_sharing) return;
    final strings = AppStrings.of(context);
    setState(() => _sharing = true);
    Object? failure;
    try {
      final share =
          widget.shareFile ??
          (path) => ref.read(shareFileServiceProvider).shareFile(path);
      await share(result.outputZipPath);
    } catch (error) {
      failure = error;
    }
    if (!mounted) return;
    setState(() => _sharing = false);
    showAppToast(
      context,
      failure == null ? strings.backupShared : strings.backupShareFailed,
      replace: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final database = ref.watch(databaseProvider);
    return AdaptivePageScaffold.raw(
      title: strings.backupProjects,
      body: StreamBuilder<List<Project>>(
        stream: database.watchProjects(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const SizedBox.shrink();
          }
          final projects = snapshot.data!;
          _selectedIds.removeWhere(
            (id) => !projects.any((project) => project.id == id),
          );
          if (projects.isEmpty) {
            return Center(child: Text(strings.noProjectsToBackup));
          }
          final allSelected =
              projects.isNotEmpty &&
              projects.every((project) => _selectedIds.contains(project.id));
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      strings.selectedProjectCount(_selectedIds.length),
                    ),
                  ),
                  TextButton(
                    key: const Key('select-all-projects'),
                    onPressed: _submitting ? null : () => _toggleAll(projects),
                    child: Text(
                      allSelected ? strings.deselectAll : strings.selectAll,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  strings.backupEmptyProjectHint,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(height: 4),
              for (final project in projects)
                Card(
                  child: Builder(
                    builder: (tileContext) {
                      void toggle(bool selected) => setState(() {
                        if (selected) {
                          _selectedIds.add(project.id);
                        } else {
                          _selectedIds.remove(project.id);
                        }
                      });
                      final subtitle = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (project.description != null)
                            Text(project.description!),
                          const SizedBox(height: 4),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Chip(
                              key: Key(
                                'backup-status-${project.lifecycleStatus.name}',
                              ),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              label: Text(
                                _statusLabel(strings, project.lifecycleStatus),
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                              padding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      );
                      if (defaultTargetPlatform == TargetPlatform.iOS) {
                        // HIG: pick-many rows use a trailing round checkmark
                        // instead of a Material checkbox.
                        return ListTile(
                          title: Text(project.name),
                          subtitle: subtitle,
                          isThreeLine: project.description != null,
                          trailing: AdaptiveSelectionMark(
                            selected: _selectedIds.contains(project.id),
                            onChanged: _submitting ? null : toggle,
                          ),
                          onTap: _submitting
                              ? null
                              : () =>
                                    toggle(!_selectedIds.contains(project.id)),
                        );
                      }
                      return CheckboxListTile(
                        value: _selectedIds.contains(project.id),
                        title: Text(project.name),
                        subtitle: subtitle,
                        isThreeLine: project.description != null,
                        onChanged: _submitting
                            ? null
                            : (selected) {
                                toggle(selected ?? false);
                              },
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              key: const Key('backup-continue'),
              onPressed:
                  _selectedIds.isEmpty || _submitting || _saving || _sharing
                  ? null
                  : _startBackup,
              child: Text(strings.continueLabel),
            ),
            if (_lastBackup case final result?) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('backup-share'),
                      onPressed: _submitting || _saving || _sharing
                          ? null
                          : () => _shareBackup(result),
                      icon: const Icon(Icons.share_outlined),
                      label: Text(strings.shareBackup),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      key: const Key('backup-save-again'),
                      onPressed: _submitting || _saving || _sharing
                          ? null
                          : () => _saveBackup(result),
                      icon: const Icon(Icons.save_alt_outlined),
                      label: Text(strings.saveAgain),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _statusLabel(AppStrings strings, ProjectLifecycleStatus status) {
    return switch (status) {
      ProjectLifecycleStatus.active => strings.projectStatusActive,
      ProjectLifecycleStatus.completed => strings.projectStatusCompleted,
      ProjectLifecycleStatus.archived => strings.projectStatusArchived,
    };
  }
}

String _describeBackupError(AppStrings strings, Object error) {
  if (isInsufficientStorageFailure(error)) {
    return strings.backupStorageInsufficient;
  }
  if (error is ProjectBackupExportException) {
    return strings.backupProjectFailed(error.projectName);
  }
  return strings.backupFailedFriendly;
}
