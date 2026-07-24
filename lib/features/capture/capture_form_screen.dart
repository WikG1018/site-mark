import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
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
  bool _working = false;

  /// Detaches the KILL-persistence hook registered in [initState]. Null
  /// until the hook is attached (or after [dispose]).
  VoidCallback? _killHookDetach;

  /// One-time initialization future that loads the project together with the
  /// most recent non-pending capture of that project, so the three carry-forward
  /// fields can be prefilled exactly once. Rebuilt only when [widget.projectId]
  /// changes; never recomputed on every [build].
  Future<_CaptureFormInit?>? _initFuture;

  /// Cached location-permission view state. Loaded once during initialization
  /// and refreshed whenever the app returns to the foreground so the
  /// explanation card reflects any permission change the user made in the
  /// system dialog or settings. `null` means the first load has not finished.
  LocationPermissionViewState? _permissionState;

  Future<_CaptureFormInit?> _loadInit() async {
    final database = ref.read(databaseProvider);
    final project = await database.projectById(widget.projectId);
    if (project == null) return null;

    // Check the KILL-persisted draft first. A KILL draft represents the
    // user's unsaved input from the last session that was interrupted by
    // the OEM memory killer. It takes priority over carry-forward because
    // it contains the user's most recent edits, including notes (which
    // carry-forward deliberately leaves blank). This applies regardless of
    // whether the project already has captured records.
    CaptureFormDraftSnapshot? snapshot;
    try {
      snapshot = await ref
          .read(captureFormDraftStoreProvider)
          .load(widget.projectId);
    } catch (_) {
      snapshot = null;
    }

    if (snapshot != null) {
      // Restore the user's unsaved draft from the last KILL event.
      _locationController.text = snapshot.workLocation;
      _contentController.text = snapshot.workContent;
      _photographerController.text = snapshot.photographer;
      _notesController.text = snapshot.notes;
    } else {
      // No KILL draft to restore; fall back to carry-forward fields from
      // the most recent captured record. Notes stay blank by design.
      final draft = await database.latestCapturedDraft(widget.projectId);
      if (draft != null) {
        _applyCarryForward(draft);
      }
      return _CaptureFormInit(project: project, draft: draft);
    }

    // A snapshot was restored; still load the latest draft so the caller
    // knows whether the project has history.
    final draft = await database.latestCapturedDraft(widget.projectId);
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initFuture ??= _loadInit();
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

  @override
  void dispose() {
    _killHookDetach?.call();
    WidgetsBinding.instance.removeObserver(this);
    _locationController.dispose();
    _contentController.dispose();
    _photographerController.dispose();
    _notesController.dispose();
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
    final strings = AppStrings.of(context);
    switch (result.outcome) {
      case CaptureWorkflowOutcome.queued:
        // The draft became a durable record; clear the KILL snapshot so the
        // next launch does not resurrect the just-submitted text. Best-effort:
        // a failure to clear must not block the capture confirmation flow.
        try {
          await ref.read(captureFormDraftStoreProvider).clear(widget.projectId);
        } catch (_) {
          // Ignore: the snapshot will be overwritten on the next KILL.
        }
        if (!mounted) return;
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
      case CaptureWorkflowOutcome.cancelled:
        // The camera was dismissed without a photo; stay on the form and
        // re-enable the button without surfacing a confirmation.
        setState(() => _working = false);
      case CaptureWorkflowOutcome.failed:
        setState(() => _working = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${strings.captureFailed}: ${result.errorMessage ?? ''}',
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
        final project = snapshot.data?.project;
        final permission = _permissionState;
        final prompt = permission != null && permission.showExplanation
            ? LocationPermissionPrompt(
                openSettings: permission.openSettings,
                onDismiss: _dismissPermissionPrompt,
                onEnable: _enableLocation,
              )
            : null;
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
                        child: _CaptureFormBody(
                          key: const Key('capture-form'),
                          locationController: _locationController,
                          contentController: _contentController,
                          photographerController: _photographerController,
                          notesController: _notesController,
                          strings: strings,
                          working: _working,
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
    required this.strings,
    required this.working,
    required this.onCapture,
    this.permissionPrompt,
  });

  final TextEditingController locationController;
  final TextEditingController contentController;
  final TextEditingController photographerController;
  final TextEditingController notesController;
  final AppStrings strings;
  final bool working;
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
        _RequiredField(
          fieldKey: const Key('work-location'),
          controller: locationController,
          label: strings.workLocation,
          error: strings.requiredField,
        ),
        const SizedBox(height: 16),
        _RequiredField(
          fieldKey: const Key('work-content'),
          controller: contentController,
          label: strings.workContent,
          error: strings.requiredField,
          maxLines: 2,
        ),
        const SizedBox(height: 16),
        _RequiredField(
          fieldKey: const Key('photographer'),
          controller: photographerController,
          label: strings.photographer,
          error: strings.requiredField,
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
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on_outlined),
                const SizedBox(width: 12),
                Expanded(child: Text(strings.captureLocationHint)),
              ],
            ),
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
      ],
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
