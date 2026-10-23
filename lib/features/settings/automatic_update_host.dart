import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sitemark/design_tokens.dart';
import 'package:sitemark/domain/release_check.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/navigation/scroll_chrome.dart';
import 'package:sitemark/platform/automatic_update_controller.dart';
import 'package:sitemark/shared/ui/floating_dock_layout.dart';
import 'package:sitemark/shared/ui/glass_surface.dart';

/// A scoped, non-modal notice above the Dock. It cannot survive navigation
/// into a form/camera/detail page or cover an external app on resume.
class AutomaticUpdateHost extends StatefulWidget {
  const AutomaticUpdateHost({
    super.key,
    required this.controller,
    required this.active,
    required this.onOpen,
    required this.child,
    this.avoidFloatingActionButton = false,
  });
  final AutomaticUpdateController controller;
  final bool active;
  final VoidCallback onOpen;
  final Widget child;
  final bool avoidFloatingActionButton;
  @override
  State<AutomaticUpdateHost> createState() => _AutomaticUpdateHostState();
}

class _AutomaticUpdateHostState extends State<AutomaticUpdateHost>
    with WidgetsBindingObserver {
  bool _foreground = true;
  bool _scheduled = false;
  ReleaseCheckOutcome? _notice;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _attach();
  }

  void _attach() {
    widget.controller.addListener(_schedule);
    widget.controller.setForeground(_foreground);
    // Independent of recovery/camera startup; never await HTTP on that path.
    unawaited(widget.controller.checkOnForeground());
  }

  @override
  void didUpdateWidget(covariant AutomaticUpdateHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_schedule);
      _attach();
    }
    _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    widget.controller.setForeground(_foreground);
    if (_foreground) unawaited(widget.controller.checkOnForeground());
    _schedule();
  }

  bool get _canShow {
    final chrome = ScrollChromeScope.maybeOf(context);
    return widget.active &&
        _foreground &&
        widget.controller.enabled &&
        chrome?.forced != true &&
        chrome?.visible != false &&
        MediaQuery.viewInsetsOf(context).bottom == 0 &&
        ModalRoute.of(context)?.isCurrent != false;
  }

  void _schedule() {
    if (!mounted || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      if (!_canShow) {
        if (_notice != null) _dismiss();
        return;
      }
      if (_notice != null) return;
      final available = widget.controller.pendingReminder;
      if (available == null) return;
      setState(() => _notice = available);
      unawaited(widget.controller.markReminded());
      if (!MediaQuery.accessibleNavigationOf(context)) {
        _dismissTimer = Timer(const Duration(seconds: 8), _dismiss);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _dismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    if (mounted && _notice != null) setState(() => _notice = null);
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    widget.controller.removeListener(_schedule);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Inherited chrome/keyboard/modal changes also defer or dismiss the notice.
    final canShow = _canShow;
    if ((canShow &&
            _notice == null &&
            widget.controller.pendingReminder != null) ||
        (!canShow && _notice != null)) {
      _schedule();
    }
    final strings = AppStrings.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_notice case final notice? when canShow)
          Positioned(
            left: 16,
            right: 16,
            bottom: floatingDockReservedSpaceOf(
              context,
              avoidFloatingActionButton: widget.avoidFloatingActionButton,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Semantics(
                  liveRegion: true,
                  child: Material(
                    type: MaterialType.transparency,
                    child: GlassSurface(
                      key: const Key('automatic-update-notice'),
                      borderRadius: const BorderRadius.all(AppRadius.xl),
                      opacity: .94,
                      child: Padding(
                        padding: const EdgeInsets.only(
                          left: 16,
                          top: 8,
                          bottom: 8,
                          right: 4,
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.system_update_outlined),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    strings.newVersionFound(
                                      notice.versionLabel ?? '',
                                    ),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                  TextButton(
                                    key: const Key('view-automatic-update'),
                                    onPressed: () {
                                      _dismiss();
                                      widget.onOpen();
                                    },
                                    child: Text(strings.viewUpdate),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              key: const Key('dismiss-automatic-update'),
                              tooltip: strings.dismissUpdateReminder,
                              onPressed: _dismiss,
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
