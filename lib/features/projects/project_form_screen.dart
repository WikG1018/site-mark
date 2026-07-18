import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/domain/project_name.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:uuid/uuid.dart';

class ProjectFormScreen extends ConsumerStatefulWidget {
  const ProjectFormScreen({super.key});

  @override
  ConsumerState<ProjectFormScreen> createState() => _ProjectFormScreenState();
}

class _ProjectFormScreenState extends ConsumerState<ProjectFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _saving = false;
  String? _nameError;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _nameError = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final database = ref.read(databaseProvider);
    // Copy the current global watermark defaults so each new project starts
    // with the user's preferred template; existing projects are never
    // retroactively updated when these defaults change later. A one-shot read
    // is used (not the watch stream) so the future resolves on a single
    // microtask and the save button's spinner does not stall `pumpAndSettle`
    // in widget tests.
    final settings = await database.getAppSettings();
    try {
      await database.createProject(
        id: const Uuid().v4(),
        name: _nameController.text,
        description: _descriptionController.text.isEmpty
            ? null
            : _descriptionController.text,
        watermarkPosition: settings.defaultWatermarkPosition,
        watermarkOpacity: settings.defaultWatermarkOpacity,
        watermarkAccentColorArgb: settings.defaultWatermarkAccentColorArgb,
        watermarkFontScale: settings.defaultWatermarkFontScale,
      );
    } on ProjectNameConflictException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _nameError = error.kind == ProjectNameConflictKind.displayName
            ? AppStrings.of(context).projectNameAlreadyExists
            : AppStrings.of(context).projectFileNameConflict;
      });
      _formKey.currentState!.validate();
      return;
    }
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(strings.createProject)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  TextFormField(
                    key: const Key('project-name'),
                    controller: _nameController,
                    autofocus: true,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(labelText: strings.projectName),
                    onChanged: (_) {
                      if (_nameError != null) {
                        setState(() => _nameError = null);
                      }
                    },
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return strings.projectNameRequired;
                      }
                      return _nameError;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descriptionController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: strings.descriptionOptional,
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(strings.save),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
