import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/domain/project_name.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/src/rust/api/image_core.dart' as rust;
import 'package:sitemark/workflow/project_import_service.dart';

/// Picks a SiteMark backup ZIP, confirms the restore plan with the user, and
/// runs the import with live progress. Reports the outcome in a snackbar.
///
/// The project list refreshes itself via `watchProjects`, so a successful
/// restore simply appears in the list when this completes.
Future<void> runProjectImportFlow(BuildContext context, WidgetRef ref) async {
  final strings = AppStrings.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final service = ref.read(projectImportServiceProvider);

  final picked = await FilePicker.pickFiles(
    dialogTitle: strings.importDialogTitle,
    type: FileType.custom,
    allowedExtensions: const ['zip'],
  );
  final zipPath = picked?.files.single.path;
  if (zipPath == null || !context.mounted) return;

  // 1. Validate the archive before offering any restore plan.
  _showBlockingSpinner(context, strings.importDialogTitle);
  rust.ProjectArchivePreview preview;
  try {
    preview = await service.inspect(zipPath);
  } catch (error) {
    if (context.mounted) {
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(content: Text(describeImportError(strings, error))),
      );
    }
    return;
  }
  if (!context.mounted) return;
  Navigator.of(context).pop();

  // 2. Let the user confirm (and optionally rename) the restored project.
  final suggestedName = await service.suggestAvailableName(preview.projectName);
  if (!context.mounted) return;
  final chosenName = await showDialog<String>(
    context: context,
    builder: (dialogContext) => _ImportConfirmDialog(
      preview: preview,
      suggestedName: suggestedName,
      service: service,
    ),
  );
  if (chosenName == null || !context.mounted) return;

  // 3. Restore, reporting per-photo progress.
  final progress = ValueNotifier<(int, int)>((0, preview.photos.length));
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(strings.importDialogTitle),
        content: ValueListenableBuilder<(int, int)>(
          valueListenable: progress,
          builder: (context, value, _) => Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 16),
              Expanded(
                child: Text(strings.importingProgress(value.$1, value.$2)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  ProjectImportResult? result;
  Object? failure;
  try {
    result = await service.importProject(
      zipPath: zipPath,
      projectName: chosenName,
      onProgress: (completed, total) => progress.value = (completed, total),
    );
  } catch (error) {
    failure = error;
  }
  if (context.mounted) Navigator.of(context).pop();
  progress.dispose();
  if (!context.mounted) return;

  if (result != null) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          strings.importSuccess(result.projectName, result.photoCount),
        ),
      ),
    );
  } else {
    messenger.showSnackBar(
      SnackBar(content: Text(describeImportError(strings, failure!))),
    );
  }
}

/// Maps a restore failure to a user-facing message. Archive-format problems
/// (invalid data, selection exports) get dedicated copy; everything else is
/// a generic failure with the underlying message attached.
@visibleForTesting
String describeImportError(AppStrings strings, Object error) {
  if (error is InvalidArchiveException) {
    return strings.importInvalidArchive;
  }
  if (error is ImagePipelineException) {
    if (error.message.contains('selection archive')) {
      return strings.importSelectionUnsupported;
    }
    if (error.kind == ImagePipelineFailureKind.invalidData) {
      return strings.importInvalidArchive;
    }
    return '${strings.importFailed}: ${error.message}';
  }
  if (error is ProjectNameConflictException) {
    return strings.importNameConflict;
  }
  return '${strings.importFailed}: $error';
}

void _showBlockingSpinner(BuildContext context, String label) {
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

class _ImportConfirmDialog extends StatefulWidget {
  const _ImportConfirmDialog({
    required this.preview,
    required this.suggestedName,
    required this.service,
  });

  final rust.ProjectArchivePreview preview;
  final String suggestedName;
  final ProjectImportService service;

  @override
  State<_ImportConfirmDialog> createState() => _ImportConfirmDialogState();
}

class _ImportConfirmDialogState extends State<_ImportConfirmDialog> {
  late final TextEditingController _nameController;
  String? _nameError;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.suggestedName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final strings = AppStrings.of(context);
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = strings.projectNameRequired);
      return;
    }
    setState(() {
      _checking = true;
      _nameError = null;
    });
    final taken = await widget.service.projectNameTaken(name);
    if (!mounted) return;
    if (taken) {
      setState(() {
        _checking = false;
        _nameError = strings.importNameConflict;
      });
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final preview = widget.preview;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(strings.importDialogTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.importPhotoCount(preview.photos.length),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            preview.includesOriginals
                ? strings.importIncludesOriginals
                : strings.importNoOriginals,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            preview.watermark != null
                ? strings.importWatermarkRestored
                : strings.importWatermarkDefault,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('import-project-name'),
            controller: _nameController,
            autofocus: true,
            maxLength: 120,
            decoration: InputDecoration(
              labelText: strings.projectName,
              errorText: _nameError,
            ),
            onSubmitted: (_) => _confirm(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _checking ? null : () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        FilledButton(
          key: const Key('import-confirm'),
          onPressed: _checking ? null : _confirm,
          child: Text(strings.importAction),
        ),
      ],
    );
  }
}
