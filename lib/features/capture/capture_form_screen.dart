import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_failure.dart';
import 'package:sitemark/domain/capture_template_rules.dart';
import 'package:sitemark/features/capture/capture_recent_suggestions.dart';
import 'package:sitemark/features/capture/capture_template_sheet.dart';
import 'package:sitemark/features/capture/location_permission_prompt.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/motion.dart';
import 'package:sitemark/platform/capture_form_draft_store.dart';
import 'package:sitemark/platform/memory_pressure_coordinator.dart';
import 'package:sitemark/workflow/capture_workflow.dart';
import 'package:sitemark/workflow/location_permission_service.dart';

class CaptureFormScreen extends ConsumerStatefulWidget {
  const CaptureFormScreen({super.key, required this.projectId});

  final String projectId;

  @override
  ConsumerState<CaptureFormScreen> createState() => _CaptureFormScreenState();
}

class _CaptureFormScreenState extends ConsumerState<CaptureFormScreen>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _locationController = TextEditingController();
  final _contentController = TextEditingController();
  final _photographerController = TextEditingController();
  final _notesController = TextEditingController();
  final _locationFocusNode = FocusNode();
  final _contentFocusNode = FocusNode();
  final _photographerFocusNode = FocusNode();
  bool _working = false;

  /// Detaches the KILL-persistence hook registered in [initState]. Null
  /// until the hook is attached (or after [dispose]).
  VoidCallback? _killHookDetach;

  /// One-time initialization future that loads the project together with the
  /// most recent non-pending capture of that project, so the three carry-forward
  /// fields can be prefilled exactly once. Rebuilt only when [widget.projectId]
  /// changes; never recomputed on every [build].
  Future<_CaptureFormInit?>? _initFuture;
  var _initGeneration = 0;
  var _captureOperation = 0;
  var _templateOperation = 0;
  var _templateSheetOpen = false;

  /// Cached location-permission view state. Loaded once during initialization
  /// and refreshed whenever the app returns to the foreground so the
  /// explanation card reflects any permission change the user made in the
  /// system dialog or settings. `null` means the first load has not finished.
  LocationPermissionViewState? _permissionState;

  bool _isCurrentInit(String projectId, int generation) =>
      mounted && widget.projectId == projectId && _initGeneration == generation;

  Future<_CaptureFormInit?> _loadInit(String projectId, int generation) async {
    final database = ref.read(databaseProvider);
    final project = await database.projectById(projectId);
    if (!_isCurrentInit(projectId, generation)) return null;
    if (project == null) return null;

    // Check the KILL-persisted draft first. A KILL draft represents the
    // user's unsaved input from the last session that was interrupted by
    // the OEM memory killer. It takes priority over carry-forward because
    // it contains the user's most recent edits, including notes (which
    // carry-forward deliberately leaves blank). This applies regardless of
    // whether the project already has captured records.
    CaptureFormDraftSnapshot? snapshot;
    try {
      snapshot = await ref.read(captureFormDraftStoreProvider).load(projectId);
    } catch (_) {
      snapshot = null;
    }
    if (!_isCurrentInit(projectId, generation)) return null;

    if (snapshot != null) {
      // Restore the user's unsaved draft from the last KILL event.
      _locationController.text = snapshot.workLocation;
      _contentController.text = snapshot.workContent;
      _photographerController.text = snapshot.photographer;
      _notesController.text = snapshot.notes;
    } else {
      // No KILL draft to restore; fall back to carry-forward fields from
      // the most recent captured record. Notes stay blank by design.
      final draft = await database.latestCapturedDraft(projectId);
      if (!_isCurrentInit(projectId, generation)) return null;
      if (draft != null) {
        _applyCarryForward(draft);
      }
      return _CaptureFormInit(project: project, draft: draft);
    }

    // A snapshot was restored; still load the latest draft so the caller
    // knows whether the project has history.
    final draft = await database.latestCapturedDraft(projectId);
    if (!_isCurrentInit(projectId, generation)) return null;
    return _CaptureFormInit(project: project, draft: draft);
  }

  Future<void> _loadPermission() async {
    final state = await ref.read(locationPermissionServiceProvider).load();
    if (!mounted) return;
    setState(() => _permissionState = state);
  }

  @override
  void initState() {
    super.initState();
    // Observe lifecycle so the permission card refreshes after the user
    // returns from the system permission dialog or settings page.
    WidgetsBinding.instance.addObserver(this);
    // ITGSA fair-memory: persist the in-progress form text before a
    // MEMORY_KILL so the user does not lose what they typed when the OEM
    // reclaims the process. The hook reads the controllers synchronously
    // (cheap) and writes the snapshot to disk asynchronously.
    _attachKillHook();
  }

  void _attachKillHook() {
    final store = ref.read(captureFormDraftStoreProvider);
    _killHookDetach = ref
        .read(memoryPressureControllerProvider)
        .attachKillHook(
          _CaptureFormKillHook(
            projectId: widget.projectId,
            locationController: _locationController,
            contentController: _contentController,
            photographerController: _photographerController,
            notesController: _notesController,
            store: store,
          ),
        );
  }

  @override
  void didUpdateWidget(covariant CaptureFormScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId == widget.projectId) return;
    _initGeneration++;
    _captureOperation++;
    _templateOperation++;
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    _locationController.clear();
    _contentController.clear();
    _photographerController.clear();
    _notesController.clear();
    _working = false;
    _killHookDetach?.call();
    _killHookDetach = null;
    _attachKillHook();
    _initFuture = _loadInit(widget.projectId, _initGeneration);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initFuture ??= _loadInit(widget.projectId, _initGeneration);
    // Kick off the first permission load alongside the project init. Guarded
    // by the null cache so repeated rebuilds do not re-trigger the load.
    if (_permissionState == null) {
      _loadPermission();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // The user may have toggled location permission while the app was paused;
    // refresh on resume so the card and capture-draft fallback stay in sync.
    if (state == AppLifecycleState.resumed) {
      _loadPermission();
    }
  }

  void _applyCarryForward(CaptureCarryForwardDraft? draft) {
    if (draft == null) return;
    _locationController.text = draft.workLocation;
    _contentController.text = draft.workContent;
    _photographerController.text = draft.photographer;
    // Notes are intentionally left blank so stale review notes never carry over.
  }

  Future<List<String>> _loadRecentSuggestions({
    required String projectId,
    required CaptureSuggestionField field,
    required int limit,
  }) {
    return ref
        .read(databaseProvider)
        .recentCaptureSuggestions(
          projectId: projectId,
          field: field,
          limit: limit,
        );
  }

  CaptureRequiredFieldsSnapshot _requiredFieldsSnapshot() {
    return CaptureRequiredFieldsSnapshot(
      workLocation: _locationController.text,
      workContent: _contentController.text,
      photographer: _photographerController.text,
    );
  }

  void _applyRequiredFields(CaptureRequiredFieldsSnapshot snapshot) {
    _locationController.text = snapshot.workLocation;
    _contentController.text = snapshot.workContent;
    _photographerController.text = snapshot.photographer;
  }

  Future<void> _openTemplates() async {
    if (_templateSheetOpen) return;
    final projectId = widget.projectId;
    final generation = _initGeneration;
    final operation = ++_templateOperation;
    final previous = _requiredFieldsSnapshot();
    _templateSheetOpen = true;
    CaptureRequiredFieldsSnapshot? selected;
    try {
      selected = await showCaptureTemplateSheet(
        context: context,
        projectId: projectId,
        current: previous,
        service: ref.read(captureTemplateServiceProvider),
      );
    } finally {
      _templateSheetOpen = false;
    }
    if (!mounted ||
        selected == null ||
        widget.projectId != projectId ||
        _initGeneration != generation ||
        _templateOperation != operation) {
      return;
    }
    _applyRequiredFields(selected);
    final strings = AppStrings.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(strings.captureTemplateApplied),
          action: SnackBarAction(
            label: strings.undo,
            onPressed: () {
              if (!mounted ||
                  widget.projectId != projectId ||
                  _initGeneration != generation ||
                  _templateOperation != operation) {
                return;
              }
              _applyRequiredFields(previous);
            },
          ),
        ),
      );
  }

  @override
  void dispose() {
    _killHookDetach?.call();
    WidgetsBinding.instance.removeObserver(this);
    _locationController.dispose();
    _contentController.dispose();
    _photographerController.dispose();
    _notesController.dispose();
    _locationFocusNode.dispose();
    _contentFocusNode.dispose();
    _photographerFocusNode.dispose();
    super.dispose();
  }

  Future<void> _dismissPermissionPrompt() async {
    await ref.read(locationPermissionServiceProvider).dismiss();
    if (!mounted) return;
    // Refresh from the source of truth so the persisted dismissal flag is
    // reflected; load() returns showExplanation=false for a dismissed card.
    await _loadPermission();
  }

  Future<void> _enableLocation() async {
    final service = ref.read(locationPermissionServiceProvider);
    final current = _permissionState;
    if (current == null) return;
    if (current.openSettings) {
      // The platform reports `permanentlyDenied`; route to system settings.
      // The resumed lifecycle callback refreshes state when the user returns.
      await service.openSettings();
      return;
    }
    final state = await service.request();
    if (!mounted) return;
    setState(() => _permissionState = state);
  }

  Future<void> _capture(Project project) async {
    if (!_formKey.currentState!.validate()) return;
    final projectId = project.id;
    final generation = _initGeneration;
    final operation = ++_captureOperation;
    bool isCurrent() =>
        mounted &&
        widget.projectId == projectId &&
        _initGeneration == generation &&
        _captureOperation == operation;
    setState(() => _working = true);
    final language = Localizations.localeOf(context).languageCode;
    final watermarkLocaleCode = language == 'en' ? 'en' : 'zh';
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
            watermarkLocaleCode: watermarkLocaleCode,
            // The capture button path must never trigger a runtime permission
            // request, so only attempt a location read when permission is
            // already granted.
            useLocationFallback: _permissionState?.locationEnabled ?? false,
          ),
        );
    if (!mounted) return;
    if (!isCurrent()) {
      if (result.outcome == CaptureWorkflowOutcome.queued ||
          result.outcome == CaptureWorkflowOutcome.delayed) {
        try {
          await ref.read(captureFormDraftStoreProvider).clear(projectId);
        } catch (_) {}
      }
      return;
    }
    final strings = AppStrings.of(context);
    switch (result.outcome) {
      case CaptureWorkflowOutcome.queued:
        // The draft became a durable record; clear the KILL snapshot so the
        // next launch does not resurrect the just-submitted text. Best-effort:
        // a failure to clear must not block the capture confirmation flow.
        try {
          await ref.read(captureFormDraftStoreProvider).clear(projectId);
        } catch (_) {
          // Ignore: the snapshot will be overwritten on the next KILL.
        }
        if (!mounted) return;
        if (!isCurrent()) return;
        // Stay on the form for consecutive shooting: clear only notes so the
        // retained location/content/photographer edits persist, re-enable the
        // button, and surface the background-queue confirmation. Replace any
        // in-flight snackbar so burst captures never queue a stack of them.
        _notesController.clear();
        setState(() => _working = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(strings.captureQueuedContinue),
              duration: const Duration(seconds: 2),
            ),
          );
      case CaptureWorkflowOutcome.delayed:
        try {
          await ref.read(captureFormDraftStoreProvider).clear(projectId);
        } catch (_) {
          // The durable capture is authoritative; a stale draft is harmless.
        }
        if (!mounted) return;
        if (!isCurrent()) return;
        _notesController.clear();
        setState(() => _working = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(strings.captureQueueDelayedContinue),
              duration: const Duration(seconds: 4),
            ),
          );
      case CaptureWorkflowOutcome.cancelled:
        // The camera was dismissed without a photo; stay on the form and
        // re-enable the button without surfacing a confirmation.
        setState(() => _working = false);
      case CaptureWorkflowOutcome.failed:
        setState(() => _working = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${strings.captureFailed}: '
              '${strings.captureFailureMessage(result.failureCode ?? CaptureFailureCode.unexpected)}',
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return FutureBuilder<_CaptureFormInit?>(
      future: _initFuture,
      builder: (context, snapshot) {
        final loadedProject = snapshot.data?.project;
        final project = loadedProject?.id == widget.projectId
            ? loadedProject
            : null;
        final permission = _permissionState;
        final prompt = permission != null && permission.showExplanation
            ? LocationPermissionPrompt(
                openSettings: permission.openSettings,
                onDismiss: _dismissPermissionPrompt,
                onEnable: _enableLocation,
              )
            : null;
        return Scaffold(
          appBar: AppBar(title: Text(strings.captureFormTitle)),
          body: project == null
              ? const Center(child: CircularProgressIndicator())
              : SafeArea(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 620),
                      child: Form(
                        key: _formKey,
                        child: _CaptureFormBody(
                          key: const Key('capture-form'),
                          locationController: _locationController,
                          contentController: _contentController,
                          photographerController: _photographerController,
                          notesController: _notesController,
                          locationFocusNode: _locationFocusNode,
                          contentFocusNode: _contentFocusNode,
                          photographerFocusNode: _photographerFocusNode,
                          projectId: widget.projectId,
                          loadSuggestions: _loadRecentSuggestions,
                          strings: strings,
                          working: _working,
                          onTemplates: _openTemplates,
                          onCapture: () => _capture(project),
                          permissionPrompt: prompt,
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

/// Bundle of the project and its most recent non-pending capture loaded once
/// during [CaptureFormScreen] initialization.
class _CaptureFormInit {
  const _CaptureFormInit({required this.project, this.draft});

  final Project project;
  final CaptureCarryForwardDraft? draft;
}

class _CaptureFormBody extends StatelessWidget {
  const _CaptureFormBody({
    super.key,
    required this.locationController,
    required this.contentController,
    required this.photographerController,
    required this.notesController,
    required this.locationFocusNode,
    required this.contentFocusNode,
    required this.photographerFocusNode,
    required this.projectId,
    required this.loadSuggestions,
    required this.strings,
    required this.working,
    required this.onTemplates,
    required this.onCapture,
    this.permissionPrompt,
  });

  final TextEditingController locationController;
  final TextEditingController contentController;
  final TextEditingController photographerController;
  final TextEditingController notesController;
  final FocusNode locationFocusNode;
  final FocusNode contentFocusNode;
  final FocusNode photographerFocusNode;
  final String projectId;
  final CaptureRecentSuggestionsLoader loadSuggestions;
  final AppStrings strings;
  final bool working;
  final VoidCallback onTemplates;
  final VoidCallback onCapture;

  /// Optional non-blocking location-permission card rendered at the top of the
  /// form when the host permission is not granted and the user has not
  /// dismissed the explanation.
  final Widget? permissionPrompt;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // Always-mounted animated slot: the prompt expands/fades in and
        // collapses out without the form fields jumping.
        LocationPermissionPromptArea(prompt: permissionPrompt),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: OutlinedButton.icon(
            key: const Key('capture-template-button'),
            onPressed: onTemplates,
            icon: const Icon(Icons.bookmarks_outlined, size: 18),
            label: Text(strings.captureTemplates),
          ),
        ),
        const SizedBox(height: 8),
        _RequiredField(
          fieldKey: const Key('work-location'),
          controller: locationController,
          focusNode: locationFocusNode,
          label: strings.workLocation,
          error: strings.requiredField,
          suggestions: CaptureRecentSuggestions(
            projectId: projectId,
            field: CaptureSuggestionField.workLocation,
            controller: locationController,
            focusNode: locationFocusNode,
            load: loadSuggestions,
          ),
        ),
        const SizedBox(height: 16),
        _RequiredField(
          fieldKey: const Key('work-content'),
          controller: contentController,
          focusNode: contentFocusNode,
          label: strings.workContent,
          error: strings.requiredField,
          maxLines: 2,
          suggestions: CaptureRecentSuggestions(
            projectId: projectId,
            field: CaptureSuggestionField.workContent,
            controller: contentController,
            focusNode: contentFocusNode,
            load: loadSuggestions,
          ),
        ),
        const SizedBox(height: 16),
        _RequiredField(
          fieldKey: const Key('photographer'),
          controller: photographerController,
          focusNode: photographerFocusNode,
          label: strings.photographer,
          error: strings.requiredField,
          suggestions: CaptureRecentSuggestions(
            projectId: projectId,
            field: CaptureSuggestionField.photographer,
            controller: photographerController,
            focusNode: photographerFocusNode,
            load: loadSuggestions,
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const Key('notes'),
          controller: notesController,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: strings.notesOptional,
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          key: const Key('capture-button'),
          onPressed: working
              ? null
              : () {
                  HapticFeedback.lightImpact();
                  onCapture();
                },
          // Cross-fade between the camera glyph and the busy spinner. Both
          // children sit inside the same fixed square so the icon slot width
          // never shifts while the button toggles its loading state.
          icon: AnimatedSwitcher(
            duration: AppMotion.short4,
            child: working
                ? const SizedBox.square(
                    key: ValueKey('capture-button-busy'),
                    dimension: 24,
                    child: Center(
                      child: SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : const SizedBox.square(
                    key: ValueKey('capture-button-idle'),
                    dimension: 24,
                    child: Icon(Icons.photo_camera_outlined),
                  ),
          ),
          label: Text(strings.openSystemCamera),
        ),
        const SizedBox(height: 12),
        Text(
          strings.captureWorkflowHint,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _RequiredField extends StatelessWidget {
  const _RequiredField({
    required this.fieldKey,
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.error,
    required this.suggestions,
    this.maxLines = 1,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final String error;
  final Widget suggestions;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          key: fieldKey,
          controller: controller,
          focusNode: focusNode,
          maxLines: maxLines,
          decoration: InputDecoration(
            labelText: label,
            alignLabelWithHint: true,
          ),
          validator: (value) =>
              value == null || value.trim().isEmpty ? error : null,
        ),
        suggestions,
      ],
    );
  }
}

/// [KillBackupHook] that persists the capture form's text fields to a
/// [CaptureFormDraftStore] when the OEM fair-memory mechanism sends a
/// MEMORY_KILL. Registered in [_CaptureFormScreenState.initState] and
/// detached in [State.dispose].
class _CaptureFormKillHook implements KillBackupHook {
  _CaptureFormKillHook({
    required this.projectId,
    required this.locationController,
    required this.contentController,
    required this.photographerController,
    required this.notesController,
    required this.store,
  });

  final String projectId;
  final TextEditingController locationController;
  final TextEditingController contentController;
  final TextEditingController photographerController;
  final TextEditingController notesController;
  final CaptureFormDraftStore store;

  @override
  Future<void> persistForKill() async {
    try {
      final location = locationController.text.trim();
      final content = contentController.text.trim();
      final photographer = photographerController.text.trim();
      final notes = notesController.text.trim();
      if (location.isEmpty &&
          content.isEmpty &&
          photographer.isEmpty &&
          notes.isEmpty) {
        // Nothing to restore; clear any stale snapshot so the next launch
        // does not resurrect a form the user already abandoned.
        await store.clear(projectId);
        return;
      }
      await store.save(
        CaptureFormDraftSnapshot(
          projectId: projectId,
          workLocation: location,
          workContent: content,
          photographer: photographer,
          notes: notes,
        ),
      );
    } catch (_) {
      // Best-effort: never let a KILL-backup IO failure propagate to the
      // memory-pressure dispatcher.
    }
  }
}
