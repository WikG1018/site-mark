import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/workflow/capture_workflow.dart';

class CaptureFormScreen extends ConsumerStatefulWidget {
  const CaptureFormScreen({super.key, required this.projectId});

  final String projectId;

  @override
  ConsumerState<CaptureFormScreen> createState() => _CaptureFormScreenState();
}

class _CaptureFormScreenState extends ConsumerState<CaptureFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _locationController = TextEditingController();
  final _contentController = TextEditingController();
  final _photographerController = TextEditingController();
  final _notesController = TextEditingController();
  bool _working = false;

  @override
  void dispose() {
    _locationController.dispose();
    _contentController.dispose();
    _photographerController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _capture(Project project) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _working = true);
    final result = await ref
        .read(captureWorkflowProvider)
        .capture(
          CaptureDraft(
            projectId: project.id,
            projectName: project.name,
            workLocation: _locationController.text.trim(),
            workContent: _contentController.text.trim(),
            photographer: _photographerController.text.trim(),
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          ),
        );
    if (!mounted) return;
    if (result.outcome == CaptureWorkflowOutcome.failed) {
      setState(() => _working = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${AppStrings.of(context).captureFailed}: '
            '${result.errorMessage ?? ''}',
          ),
        ),
      );
      return;
    }
    context.go('/projects/${project.id}');
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return FutureBuilder<Project?>(
      future: ref.read(databaseProvider).projectById(widget.projectId),
      builder: (context, snapshot) {
        final project = snapshot.data;
        return Scaffold(
          appBar: AppBar(title: Text(strings.newCapture)),
          body: project == null
              ? const Center(child: CircularProgressIndicator())
              : SafeArea(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 620),
                      child: Form(
                        key: _formKey,
                        child: ListView(
                          padding: const EdgeInsets.all(24),
                          children: [
                            _RequiredField(
                              fieldKey: const Key('work-location'),
                              controller: _locationController,
                              label: strings.workLocation,
                              error: strings.requiredField,
                            ),
                            const SizedBox(height: 16),
                            _RequiredField(
                              fieldKey: const Key('work-content'),
                              controller: _contentController,
                              label: strings.workContent,
                              error: strings.requiredField,
                              maxLines: 2,
                            ),
                            const SizedBox(height: 16),
                            _RequiredField(
                              fieldKey: const Key('photographer'),
                              controller: _photographerController,
                              label: strings.photographer,
                              error: strings.requiredField,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _notesController,
                              maxLines: 3,
                              decoration: InputDecoration(
                                labelText: strings.notesOptional,
                                alignLabelWithHint: true,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.location_on_outlined),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(strings.captureLocationHint),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            FilledButton.icon(
                              onPressed: _working
                                  ? null
                                  : () => _capture(project),
                              icon: _working
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.photo_camera_outlined),
                              label: Text(strings.openSystemCamera),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

class _RequiredField extends StatelessWidget {
  const _RequiredField({
    required this.fieldKey,
    required this.controller,
    required this.label,
    required this.error,
    this.maxLines = 1,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final String error;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: fieldKey,
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label, alignLabelWithHint: true),
      validator: (value) =>
          value == null || value.trim().isEmpty ? error : null,
    );
  }
}
