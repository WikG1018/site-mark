import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/l10n/app_strings.dart';
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
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('请等待照片处理完成'),
          content: Text(
            '有 ${snapshot.processingCount} 张照片仍在处理中。为避免备份遗漏，请处理完成后再试。',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }
    var allowFailedOmissions = false;
    if (snapshot.failedCount > 0) {
      allowFailedOmissions =
          await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('存在处理失败的照片'),
              content: Text(
                '有 ${snapshot.failedCount} 张失败记录不会进入备份。建议先返回项目重新处理；'
                '也可以明确选择仅备份已完成记录。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('返回处理'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('仅备份已完成记录'),
                ),
              ],
            ),
          ) ??
          false;
      if (!allowFailedOmissions || !mounted) return;
    }
    final includeOriginals = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.includePrivateOriginals),
        content: Text(strings.includePrivateOriginalsConsequence),
        actions: [
          TextButton(
            key: const Key('exclude-private-originals'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.excludePrivateOriginals),
          ),
          FilledButton(
            key: const Key('include-private-originals'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(strings.includePrivateOriginals),
          ),
        ],
      ),
    );
    if (includeOriginals == null || !mounted) return;

    setState(() => _submitting = true);
    final initialTotal = _selectedIds.length == 1 ? 1 : _selectedIds.length + 1;
    final progress = ValueNotifier<(int, int)>((0, initialTotal));
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: ValueListenableBuilder<(int, int)>(
            valueListenable: progress,
            builder: (context, value, _) => Row(
              children: [
                const CircularProgressIndicator(),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_describeBackupError(strings, failure))),
      );
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          failure == null ? strings.backupShared : strings.backupShareFailed,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final database = ref.watch(databaseProvider);
    return Scaffold(
      appBar: AppBar(title: Text(strings.backupProjects)),
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
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  '空白项目也可以备份，项目说明和水印设置会保留。',
                  style: TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(height: 4),
              for (final project in projects)
                Card(
                  child: CheckboxListTile(
                    value: _selectedIds.contains(project.id),
                    title: Text(project.name),
                    subtitle: project.description == null
                        ? null
                        : Text(project.description!),
                    onChanged: _submitting
                        ? null
                        : (selected) => setState(() {
                            if (selected ?? false) {
                              _selectedIds.add(project.id);
                            } else {
                              _selectedIds.remove(project.id);
                            }
                          }),
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
}

String _describeBackupError(AppStrings strings, Object error) {
  if (_looksLikeInsufficientStorage(error)) {
    return strings.backupStorageInsufficient;
  }
  return strings.backupFailedFriendly;
}

bool _looksLikeInsufficientStorage(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('no space') ||
      text.contains('disk full') ||
      text.contains('enospc');
}
