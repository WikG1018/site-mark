import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/workflow/project_bundle_service.dart';

typedef ProjectBackupExport =
    Future<ProjectBackupResult> Function({
      required List<String> projectIds,
      required bool includeOriginals,
      void Function(int completed, int total)? onProgress,
    });

class ProjectBackupSelectionScreen extends ConsumerStatefulWidget {
  const ProjectBackupSelectionScreen({
    super.key,
    this.exportProjects,
    this.shareFile,
  });

  final ProjectBackupExport? exportProjects;
  final Future<void> Function(String path)? shareFile;

  @override
  ConsumerState<ProjectBackupSelectionScreen> createState() =>
      _ProjectBackupSelectionScreenState();
}

class _ProjectBackupSelectionScreenState
    extends ConsumerState<ProjectBackupSelectionScreen> {
  final Set<String> _selectedIds = {};
  bool _submitting = false;

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
    try {
      final export =
          widget.exportProjects ??
          ({
            required List<String> projectIds,
            required bool includeOriginals,
            void Function(int completed, int total)? onProgress,
          }) => ref
              .read(projectBackupServiceProvider)
              .exportProjects(
                projectIds: projectIds,
                includeOriginals: includeOriginals,
                onProgress: onProgress,
              );
      final result = await export(
        projectIds: _selectedIds.toList(growable: false),
        includeOriginals: includeOriginals,
        onProgress: (completed, total) => progress.value = (completed, total),
      );
      final share =
          widget.shareFile ??
          (path) => ref.read(shareFileServiceProvider).shareFile(path);
      await share(result.outputZipPath);
    } catch (error) {
      failure = error;
    }
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failure == null
                ? strings.backupComplete
                : _describeBackupError(strings, failure),
          ),
        ),
      );
      setState(() => _submitting = false);
    }
    progress.dispose();
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
        child: FilledButton(
          key: const Key('backup-continue'),
          onPressed: _selectedIds.isEmpty || _submitting ? null : _startBackup,
          child: Text(strings.continueLabel),
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
