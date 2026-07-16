import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/workflow/capture_workflow.dart';

class CaptureEditScreen extends ConsumerStatefulWidget {
  const CaptureEditScreen({
    super.key,
    required this.projectId,
    required this.captureId,
  });

  final String projectId;
  final String captureId;

  @override
  ConsumerState<CaptureEditScreen> createState() => _CaptureEditScreenState();
}

class _CaptureEditScreenState extends ConsumerState<CaptureEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _location = TextEditingController();
  final _content = TextEditingController();
  final _photographer = TextEditingController();
  final _notes = TextEditingController();
  bool _initialized = false;
  bool _working = false;

  @override
  void dispose() {
    _location.dispose();
    _content.dispose();
    _photographer.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _initialize(CaptureRecord capture) {
    if (_initialized) return;
    _initialized = true;
    _location.text = capture.workLocation;
    _content.text = capture.workContent;
    _photographer.text = capture.photographer;
    _notes.text = capture.notes ?? '';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _working = true);
    try {
      await ref
          .read(captureWorkflowProvider)
          .regenerateCapture(
            captureId: widget.captureId,
            edits: CaptureEdits(
              workLocation: _location.text,
              workContent: _content.text,
              photographer: _photographer.text,
              notes: _notes.text.trim().isEmpty ? null : _notes.text,
            ),
          );
      if (mounted) {
        context.go(
          '/projects/${widget.projectId}/captures/${widget.captureId}',
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _working = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${AppStrings.of(context).regenerationFailed}: $error'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return FutureBuilder<CaptureRecord?>(
      future: ref.read(databaseProvider).captureById(widget.captureId),
      builder: (context, snapshot) {
        final capture = snapshot.data;
        if (capture != null) _initialize(capture);
        return Scaffold(
          appBar: AppBar(title: Text(strings.editRecord)),
          body: capture == null
              ? const Center(child: CircularProgressIndicator())
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      _EditField(
                        fieldKey: const Key('edit-work-location'),
                        controller: _location,
                        label: strings.workLocation,
                        error: strings.requiredField,
                      ),
                      const SizedBox(height: 16),
                      _EditField(
                        fieldKey: const Key('edit-work-content'),
                        controller: _content,
                        label: strings.workContent,
                        error: strings.requiredField,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 16),
                      _EditField(
                        fieldKey: const Key('edit-photographer'),
                        controller: _photographer,
                        label: strings.photographer,
                        error: strings.requiredField,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _notes,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: strings.notesOptional,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(strings.immutableEvidence),
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _working ? null : _save,
                        icon: _working
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.auto_awesome_outlined),
                        label: Text(strings.regenerateWatermark),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _EditField extends StatelessWidget {
  const _EditField({
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
      decoration: InputDecoration(labelText: label),
      validator: (value) =>
          value == null || value.trim().isEmpty ? error : null,
    );
  }
}
