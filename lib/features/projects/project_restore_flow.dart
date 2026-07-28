import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/project_name.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/workflow/project_bundle_service.dart';
import 'package:sitemark/workflow/project_import_service.dart';

typedef PrepareProjectRestore =
    Future<PreparedProjectRestore> Function(String zipPath);
typedef RestorePreparedProjects =
    Future<List<ProjectImportResult>> Function({
      required PreparedProjectRestore prepared,
      required Map<String, String> projectNames,
      void Function(int completed, int total)? onProgress,
    });

class ProjectRestoreFlowDependencies {
  const ProjectRestoreFlowDependencies({
    required this.pickZip,
    required this.prepareRestore,
    required this.restorePrepared,
    required this.discardPrepared,
  });

  final Future<String?> Function() pickZip;
  final PrepareProjectRestore prepareRestore;
  final RestorePreparedProjects restorePrepared;
  final Future<void> Function(PreparedProjectRestore prepared) discardPrepared;
}

class ProjectRestoreFlowLifetime {
  _PreparedDiscardGuard? _guard;
  bool _disposed = false;

  void _track(_PreparedDiscardGuard guard) {
    _guard = guard;
    if (_disposed) {
      guard.discard();
    }
  }

  void _release(_PreparedDiscardGuard guard) {
    if (identical(_guard, guard)) _guard = null;
  }

  void dispose() {
    _disposed = true;
    _guard?.discard();
  }
}

Future<void> runProjectRestoreFlow(
  BuildContext context,
  WidgetRef ref, {
  ProjectRestoreFlowDependencies? dependencies,
  ProjectRestoreFlowLifetime? lifetime,
}) async {
  final strings = AppStrings.of(context);
  final shouldChoose = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(strings.restoreProjects),
      content: Text(strings.restoreExplanation),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(strings.cancel),
        ),
        FilledButton(
          key: const Key('choose-restore-zip'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(strings.chooseRestoreZip),
        ),
      ],
    ),
  );
  if (shouldChoose != true || !context.mounted) return;

  late final ProjectRestoreFlowDependencies deps;
  if (dependencies != null) {
    deps = dependencies;
  } else {
    final service = ref.read(projectBundleServiceProvider);
    deps = ProjectRestoreFlowDependencies(
      pickZip: _pickRestoreZip,
      prepareRestore: service.prepareRestore,
      restorePrepared: service.restorePrepared,
      discardPrepared: service.discardPrepared,
    );
  }
  String? zipPath;
  try {
    zipPath = await deps.pickZip();
  } catch (_) {
    if (context.mounted) {
      _showMessage(context, strings.restorePickerFailed);
    }
    return;
  }
  if (zipPath == null || !context.mounted) return;

  PreparedProjectRestore? prepared;
  _PreparedDiscardGuard? discardGuard;
  _showBlockingProgress(context, strings.restoreProjects);
  try {
    prepared = await deps.prepareRestore(zipPath);
    discardGuard = _PreparedDiscardGuard(prepared, deps.discardPrepared);
    lifetime?._track(discardGuard);
  } catch (error) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      _showMessage(
        context,
        describeProjectRestoreError(strings, error, preparing: true),
      );
    }
    return;
  }
  if (!context.mounted) {
    await discardGuard.discard();
    return;
  }
  Navigator.of(context, rootNavigator: true).pop();

  try {
    final existingProjects = await ref.read(databaseProvider).getProjects();
    if (!context.mounted) return;
    final initialNames = _suggestRestoreNames(
      prepared,
      existingProjects,
      strings,
    );
    final projectNames = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _RestorePreviewDialog(
        prepared: prepared!,
        initialNames: initialNames,
        existingProjects: existingProjects,
      ),
    );
    if (projectNames == null || !context.mounted) return;

    final totalPhotos = prepared.items.fold<int>(
      0,
      (sum, item) => sum + item.preview.photos.length,
    );
    final progress = ValueNotifier<(int, int)>((0, totalPhotos));
    _showRestoreProgress(context, progress, strings);
    Object? failure;
    List<ProjectImportResult>? results;
    try {
      results = await deps.restorePrepared(
        prepared: prepared,
        projectNames: projectNames,
        onProgress: (completed, total) => progress.value = (completed, total),
      );
      discardGuard.markSuccessful();
    } catch (error) {
      failure = error;
    }
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    progress.dispose();
    if (!context.mounted) return;
    if (results != null) {
      _showRestoreSuccess(context, strings);
    } else {
      _showMessage(
        context,
        describeProjectRestoreError(strings, failure!, preparing: false),
      );
    }
  } catch (error) {
    if (context.mounted) {
      _showMessage(
        context,
        describeProjectRestoreError(strings, error, preparing: false),
      );
    }
  } finally {
    await discardGuard.discard();
    lifetime?._release(discardGuard);
  }
}

Future<String?> _pickRestoreZip() async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['zip'],
  );
  return result?.files.single.path;
}

@visibleForTesting
String describeProjectRestoreError(
  AppStrings strings,
  Object error, {
  required bool preparing,
}) {
  if (error is ProjectBundleRestoreException) {
    return switch (error.failure) {
      ProjectBundleRestoreFailure.notSiteMarkBackup =>
        strings.backupNotSiteMark,
      ProjectBundleRestoreFailure.unsupportedVersion =>
        strings.backupUnsupportedVersion,
      ProjectBundleRestoreFailure.corrupted => strings.backupCorrupted,
      ProjectBundleRestoreFailure.selectionArchive =>
        strings.backupSelectionNotRestorable,
      ProjectBundleRestoreFailure.nameConflict =>
        strings.backupRestoreNameConflict,
      ProjectBundleRestoreFailure.insufficientStorage =>
        strings.backupStorageInsufficient,
      ProjectBundleRestoreFailure.rolledBack => strings.restoreFailedRollback,
      ProjectBundleRestoreFailure.general => strings.restoreFailedGeneral,
    };
  }
  if (error is ProjectNameConflictException) {
    return strings.backupRestoreNameConflict;
  }
  if (error is InvalidArchiveException) {
    return strings.backupCorrupted;
  }
  if (error is ImagePipelineException &&
      error.kind == ImagePipelineFailureKind.invalidData) {
    return strings.backupCorrupted;
  }
  return strings.restoreFailedGeneral;
}

Map<String, String> _suggestRestoreNames(
  PreparedProjectRestore prepared,
  List<Project> existingProjects,
  AppStrings strings,
) {
  final displayKeys = {
    for (final project in existingProjects)
      normalizedProjectNameKey(project.name),
  };
  final safeKeys = {
    for (final project in existingProjects)
      safeProjectFileNameKey(project.name),
  };
  final names = <String, String>{};
  for (final item in prepared.items) {
    final base = item.preview.projectName.trim().isEmpty
        ? strings.restoreProjects
        : item.preview.projectName.trim();
    for (var attempt = 0; attempt < 100; attempt++) {
      final suffix = switch (attempt) {
        0 => '',
        1 => '（${strings.restoreAction}）',
        _ => '（${strings.restoreAction} $attempt）',
      };
      final budget = 120 - suffix.length;
      final stem = base.length <= budget ? base : base.substring(0, budget);
      final candidate = '$stem$suffix';
      final displayKey = normalizedProjectNameKey(candidate);
      final safeKey = safeProjectFileNameKey(candidate);
      if (displayKeys.add(displayKey) && safeKeys.add(safeKey)) {
        names[item.sourceProjectId] = candidate;
        break;
      }
    }
  }
  return names;
}

void _showBlockingProgress(BuildContext context, String label) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(child: Text(label)),
          ],
        ),
      ),
    ),
  );
}

void _showRestoreProgress(
  BuildContext context,
  ValueNotifier<(int, int)> progress,
  AppStrings strings,
) {
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
                child: Text(strings.restoringProgress(value.$1, value.$2)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

void _showRestoreSuccess(BuildContext context, AppStrings strings) {
  final messenger = ScaffoldMessenger.of(context);
  GoRouter.maybeOf(context)?.go('/');
  messenger.showSnackBar(SnackBar(content: Text(strings.restoreComplete)));
}

class _PreparedDiscardGuard {
  _PreparedDiscardGuard(this.prepared, this._discard);

  final PreparedProjectRestore prepared;
  final Future<void> Function(PreparedProjectRestore prepared) _discard;
  bool _successful = false;
  bool _discarded = false;

  void markSuccessful() => _successful = true;

  Future<void> discard() async {
    if (_successful || _discarded) return;
    _discarded = true;
    try {
      await _discard(prepared);
    } catch (_) {
      // Best effort: this cleanup is also safe to retry during startup.
    }
  }
}

class _RestorePreviewDialog extends StatefulWidget {
  const _RestorePreviewDialog({
    required this.prepared,
    required this.initialNames,
    required this.existingProjects,
  });

  final PreparedProjectRestore prepared;
  final Map<String, String> initialNames;
  final List<Project> existingProjects;

  @override
  State<_RestorePreviewDialog> createState() => _RestorePreviewDialogState();
}

class _RestorePreviewDialogState extends State<_RestorePreviewDialog> {
  late final Map<String, TextEditingController> _controllers = {
    for (final item in widget.prepared.items)
      item.sourceProjectId: TextEditingController(
        text: widget.initialNames[item.sourceProjectId],
      ),
  };
  final Map<String, String?> _errors = {};

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _confirm() {
    final strings = AppStrings.of(context);
    final displayKeys = {
      for (final project in widget.existingProjects)
        normalizedProjectNameKey(project.name),
    };
    final safeKeys = {
      for (final project in widget.existingProjects)
        safeProjectFileNameKey(project.name),
    };
    final names = <String, String>{};
    final errors = <String, String?>{};
    for (final item in widget.prepared.items) {
      final sourceId = item.sourceProjectId;
      final name = _controllers[sourceId]!.text.trim();
      if (name.isEmpty || name.length > 120) {
        errors[sourceId] = strings.projectNameRequired;
        continue;
      }
      if (!displayKeys.add(normalizedProjectNameKey(name)) ||
          !safeKeys.add(safeProjectFileNameKey(name))) {
        errors[sourceId] = strings.importNameConflict;
        continue;
      }
      names[sourceId] = name;
    }
    if (errors.isNotEmpty) {
      setState(() {
        _errors
          ..clear()
          ..addAll(errors);
      });
      return;
    }
    Navigator.of(context).pop(names);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return AlertDialog(
      title: Text(strings.restorePreview),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final item in widget.prepared.items) ...[
                Text(
                  item.preview.projectName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(strings.importPhotoCount(item.preview.photos.length)),
                Text(
                  item.preview.includesOriginals
                      ? strings.importIncludesOriginals
                      : strings.importNoOriginals,
                ),
                const SizedBox(height: 4),
                if (item.preview.watermark case final watermark?) ...[
                  Text(strings.restoreUsesBackupWatermark),
                  Text(
                    strings.restoreWatermarkSummary(
                      _watermarkPositionLabel(strings, watermark.position),
                      (watermark.opacity * 100).round(),
                      (watermark.fontScale * 100).round(),
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ] else
                  Text(strings.restoreUsesDefaultWatermark),
                const SizedBox(height: 8),
                TextField(
                  key: Key('restore-name-${item.sourceProjectId}'),
                  controller: _controllers[item.sourceProjectId],
                  maxLength: 120,
                  decoration: InputDecoration(
                    labelText: strings.restoreName,
                    errorText: _errors[item.sourceProjectId],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text(strings.bundleRestoreRollback),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        FilledButton(
          key: const Key('restore-confirm'),
          onPressed: _confirm,
          child: Text(strings.restoreAction),
        ),
      ],
    );
  }
}

String _watermarkPositionLabel(AppStrings strings, String position) {
  return switch (position) {
    'bottomRight' => strings.bottomRight,
    _ => strings.bottomLeft,
  };
}
