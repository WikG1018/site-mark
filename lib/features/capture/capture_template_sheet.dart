import 'package:flutter/material.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/features/capture/capture_owned_route_controller.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/motion.dart';
import 'package:sitemark/shared/ui/adaptive_dialog.dart';
import 'package:sitemark/workflow/capture_template_service.dart';

@immutable
class CaptureRequiredFieldsSnapshot {
  const CaptureRequiredFieldsSnapshot({
    required this.workLocation,
    required this.workContent,
    required this.photographer,
  });

  final String workLocation;
  final String workContent;
  final String photographer;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CaptureRequiredFieldsSnapshot &&
          other.workLocation == workLocation &&
          other.workContent == workContent &&
          other.photographer == photographer;

  @override
  int get hashCode => Object.hash(workLocation, workContent, photographer);
}

class CaptureTemplateSheetController extends CaptureOwnedRouteController {}

Future<CaptureRequiredFieldsSnapshot?> showCaptureTemplateSheet({
  required BuildContext context,
  required String projectId,
  required CaptureRequiredFieldsSnapshot current,
  required CaptureTemplateService service,
  CaptureTemplateSheetController? controller,
}) {
  final future = showModalBottomSheet<CaptureRequiredFieldsSnapshot>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : null,
    builder: (context) {
      final route = ModalRoute.of(context);
      if (route != null) controller?.attach(route);
      return _CaptureTemplateSheet(
        projectId: projectId,
        current: current,
        service: service,
        routeController: controller,
      );
    },
  );
  return future.whenComplete(() => controller?.detach());
}

class _CaptureTemplateSheet extends StatefulWidget {
  const _CaptureTemplateSheet({
    required this.projectId,
    required this.current,
    required this.service,
    required this.routeController,
  });

  final String projectId;
  final CaptureRequiredFieldsSnapshot current;
  final CaptureTemplateService service;
  final CaptureTemplateSheetController? routeController;

  @override
  State<_CaptureTemplateSheet> createState() => _CaptureTemplateSheetState();
}

enum _TemplateEditorMode { create, rename }

class _CaptureTemplateSheetState extends State<_CaptureTemplateSheet> {
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final _contentController = TextEditingController();
  final _photographerController = TextEditingController();

  late Stream<List<CaptureTemplate>> _templates;
  _TemplateEditorMode? _editorMode;
  CaptureTemplate? _renaming;
  String? _error;
  bool _writing = false;
  var _deleteDialogSession = 0;
  CaptureOwnedRouteController? _deleteDialogController;

  @override
  void initState() {
    super.initState();
    widget.routeController?.addDismissListener(_dismissDeleteDialog);
    _reload();
  }

  void _reload() {
    _templates = widget.service.watch(widget.projectId);
  }

  @override
  void dispose() {
    widget.routeController?.removeDismissListener(_dismissDeleteDialog);
    _dismissDeleteDialog();
    _nameController.dispose();
    _locationController.dispose();
    _contentController.dispose();
    _photographerController.dispose();
    super.dispose();
  }

  void _dismissDeleteDialog() {
    _deleteDialogSession++;
    final controller = _deleteDialogController;
    _deleteDialogController = null;
    controller?.dismiss();
  }

  void _openCreate() {
    if (_writing) return;
    setState(() {
      _editorMode = _TemplateEditorMode.create;
      _renaming = null;
      _nameController.clear();
      _locationController.text = widget.current.workLocation;
      _contentController.text = widget.current.workContent;
      _photographerController.text = widget.current.photographer;
      _error = null;
    });
  }

  void _openRename(CaptureTemplate template) {
    if (_writing) return;
    setState(() {
      _editorMode = _TemplateEditorMode.rename;
      _renaming = template;
      _nameController.text = template.name;
      _error = null;
    });
  }

  void _closeEditor() {
    if (_writing) return;
    setState(() {
      _editorMode = null;
      _renaming = null;
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_writing) return;
    setState(() {
      _writing = true;
      _error = null;
    });
    try {
      if (_editorMode == _TemplateEditorMode.create) {
        await widget.service.create(
          projectId: widget.projectId,
          name: _nameController.text,
          workLocation: _locationController.text,
          workContent: _contentController.text,
          photographer: _photographerController.text,
        );
      } else {
        final template = _renaming;
        if (template == null) return;
        await widget.service.rename(
          projectId: widget.projectId,
          templateId: template.id,
          name: _nameController.text,
        );
      }
      if (!mounted) return;
      setState(() {
        _editorMode = null;
        _renaming = null;
      });
    } on CaptureTemplateException catch (error) {
      if (!mounted) return;
      setState(() => _error = _messageForFailure(error.failure));
    } catch (_) {
      if (!mounted) return;
      final strings = AppStrings.of(context);
      setState(() {
        _error = _editorMode == _TemplateEditorMode.rename
            ? strings.captureTemplateRenameFailed
            : strings.captureTemplateSaveFailed;
      });
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  Future<void> _confirmDelete(CaptureTemplate template) async {
    if (_writing || _deleteDialogController != null) return;
    final strings = AppStrings.of(context);
    final session = ++_deleteDialogSession;
    final routeController = CaptureOwnedRouteController();
    _deleteDialogController = routeController;
    bool? confirmed;
    try {
      confirmed = await showDialog<bool>(
        context: context,
        animationStyle: MediaQuery.disableAnimationsOf(context)
            ? AnimationStyle.noAnimation
            : null,
        builder: (dialogContext) {
          final route = ModalRoute.of(dialogContext);
          if (route != null) routeController.attach(route);
          return buildAdaptiveAlertDialog<bool>(
            dialogContext: dialogContext,
            title: Text(strings.captureTemplateDeleteTitle),
            content: Text(strings.captureTemplateDeleteNotice),
            actions: [
              AppDialogAction(label: strings.cancel, result: false),
              AppDialogAction(
                key: const Key('capture-template-delete-confirm'),
                label: strings.deleteAction,
                result: true,
                isDefault: true,
              ),
            ],
          );
        },
      );
    } finally {
      routeController.detach();
      if (identical(_deleteDialogController, routeController)) {
        _deleteDialogController = null;
      }
    }
    if (confirmed != true || !mounted || _deleteDialogSession != session) {
      return;
    }
    setState(() {
      _writing = true;
      _error = null;
    });
    try {
      await widget.service.delete(
        projectId: widget.projectId,
        templateId: template.id,
      );
    } on CaptureTemplateException catch (error) {
      if (!mounted) return;
      setState(() => _error = _messageForFailure(error.failure));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = strings.captureTemplateDeleteFailed);
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  String _messageForFailure(CaptureTemplateFailure failure) {
    final strings = AppStrings.of(context);
    return switch (failure) {
      CaptureTemplateFailure.invalidCharacter =>
        strings.captureTemplateInvalidCharacter,
      CaptureTemplateFailure.emptyName => strings.captureTemplateEmptyName,
      CaptureTemplateFailure.nameTooLong => strings.captureTemplateNameTooLong,
      CaptureTemplateFailure.emptyWorkLocation =>
        strings.captureTemplateEmptyWorkLocation,
      CaptureTemplateFailure.workLocationTooLong =>
        strings.captureTemplateWorkLocationTooLong,
      CaptureTemplateFailure.emptyWorkContent =>
        strings.captureTemplateEmptyWorkContent,
      CaptureTemplateFailure.workContentTooLong =>
        strings.captureTemplateWorkContentTooLong,
      CaptureTemplateFailure.emptyPhotographer =>
        strings.captureTemplateEmptyPhotographer,
      CaptureTemplateFailure.photographerTooLong =>
        strings.captureTemplatePhotographerTooLong,
      CaptureTemplateFailure.duplicateName =>
        strings.captureTemplateDuplicateName,
      CaptureTemplateFailure.projectLimitReached =>
        strings.captureTemplateLimitReached,
      CaptureTemplateFailure.notFound => strings.captureTemplateNotFound,
    };
  }

  void _apply(CaptureTemplate template) {
    if (_writing) return;
    Navigator.of(context).pop(
      CaptureRequiredFieldsSnapshot(
        workLocation: template.workLocation,
        workContent: template.workContent,
        photographer: template.photographer,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final duration = AppMotion.durationOf(context, AppMotion.short4);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    return PopScope(
      canPop: !_writing,
      child: AnimatedPadding(
        key: const Key('capture-template-keyboard-padding'),
        duration: duration,
        curve: AppMotion.standard,
        padding: EdgeInsets.only(bottom: viewInsets.bottom),
        child: FractionallySizedBox(
          heightFactor: 0.9,
          child: Material(
            key: const Key('capture-template-sheet'),
            color: Theme.of(context).colorScheme.surface,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          strings.captureTemplates,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      TextButton.icon(
                        key: const Key('capture-template-create'),
                        onPressed: _writing ? null : _openCreate,
                        icon: const Icon(Icons.add),
                        label: Text(strings.captureTemplateCreate),
                      ),
                    ],
                  ),
                ),
                AnimatedSize(
                  key: const Key('capture-template-editor-size'),
                  duration: duration,
                  curve: AppMotion.standard,
                  alignment: Alignment.topCenter,
                  child: _editorMode == null
                      ? const SizedBox.shrink()
                      : _TemplateEditor(
                          mode: _editorMode!,
                          nameController: _nameController,
                          locationController: _locationController,
                          contentController: _contentController,
                          photographerController: _photographerController,
                          error: _error,
                          writing: _writing,
                          onCancel: _closeEditor,
                          onSave: _save,
                        ),
                ),
                if (_editorMode == null && _error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Text(
                      _error!,
                      key: const Key('capture-template-write-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                Expanded(
                  child: StreamBuilder<List<CaptureTemplate>>(
                    stream: _templates,
                    builder: (context, snapshot) {
                      final child = snapshot.hasError
                          ? _TemplateLoadError(onRetry: () => setState(_reload))
                          : snapshot.hasData
                          ? _TemplateList(
                              templates: snapshot.data!,
                              enabled: !_writing,
                              onApply: _apply,
                              onRename: _openRename,
                              onDelete: _confirmDelete,
                            )
                          : const Center(child: CircularProgressIndicator());
                      return AnimatedSwitcher(
                        key: const Key('capture-template-switcher'),
                        duration: duration,
                        child: child,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TemplateEditor extends StatelessWidget {
  const _TemplateEditor({
    required this.mode,
    required this.nameController,
    required this.locationController,
    required this.contentController,
    required this.photographerController,
    required this.error,
    required this.writing,
    required this.onCancel,
    required this.onSave,
  });

  final _TemplateEditorMode mode;
  final TextEditingController nameController;
  final TextEditingController locationController;
  final TextEditingController contentController;
  final TextEditingController photographerController;
  final String? error;
  final bool writing;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final creating = mode == _TemplateEditorMode.create;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 360),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: creating
                  ? const Key('capture-template-name')
                  : const Key('capture-template-rename-name'),
              controller: nameController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: strings.captureTemplateName,
              ),
            ),
            if (creating) ...[
              const SizedBox(height: 8),
              TextField(
                key: const Key('capture-template-work-location'),
                controller: locationController,
                decoration: InputDecoration(labelText: strings.workLocation),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('capture-template-work-content'),
                controller: contentController,
                maxLines: 2,
                decoration: InputDecoration(labelText: strings.workContent),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('capture-template-photographer'),
                controller: photographerController,
                decoration: InputDecoration(labelText: strings.photographer),
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error!,
                key: const Key('capture-template-editor-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: writing ? null : onCancel,
                  child: Text(strings.cancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: creating
                      ? const Key('capture-template-save')
                      : const Key('capture-template-rename-save'),
                  onPressed: writing ? null : onSave,
                  child: Text(strings.save),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TemplateList extends StatelessWidget {
  const _TemplateList({
    required this.templates,
    required this.enabled,
    required this.onApply,
    required this.onRename,
    required this.onDelete,
  });

  final List<CaptureTemplate> templates;
  final bool enabled;
  final ValueChanged<CaptureTemplate> onApply;
  final ValueChanged<CaptureTemplate> onRename;
  final ValueChanged<CaptureTemplate> onDelete;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    if (templates.isEmpty) {
      return Center(
        key: const ValueKey('capture-template-empty'),
        child: Text(strings.captureTemplateEmpty),
      );
    }
    final ordered = [...templates]
      ..sort((left, right) {
        final updated = right.updatedAt.compareTo(left.updatedAt);
        return updated != 0 ? updated : left.name.compareTo(right.name);
      });
    return ListView.builder(
      key: const ValueKey('capture-template-list'),
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: ordered.length,
      itemBuilder: (context, index) {
        final template = ordered[index];
        return ListTile(
          key: Key('capture-template-${template.id}'),
          enabled: enabled,
          onTap: enabled ? () => onApply(template) : null,
          title: Text(template.name),
          subtitle: Text(
            '${template.workLocation} · ${template.workContent} · '
            '${template.photographer}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Wrap(
            spacing: 0,
            children: [
              IconButton(
                key: Key('capture-template-rename-${template.id}'),
                tooltip: strings.captureTemplateRename,
                onPressed: enabled ? () => onRename(template) : null,
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                key: Key('capture-template-delete-${template.id}'),
                tooltip: strings.deleteAction,
                onPressed: enabled ? () => onDelete(template) : null,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TemplateLoadError extends StatelessWidget {
  const _TemplateLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Center(
      key: const ValueKey('capture-template-load-error'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(strings.captureTemplateLoadFailed),
          const SizedBox(height: 8),
          TextButton(
            key: const Key('capture-template-retry'),
            onPressed: onRetry,
            child: Text(strings.retry),
          ),
        ],
      ),
    );
  }
}
