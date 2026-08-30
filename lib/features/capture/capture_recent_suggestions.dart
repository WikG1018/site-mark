import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sitemark/domain/capture_template_rules.dart';
import 'package:sitemark/features/capture/capture_owned_route_controller.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/shared/ui/adaptive_dialog.dart';
import 'package:sitemark/motion.dart';

typedef CaptureRecentSuggestionsLoader =
    Future<List<String>> Function({
      required String projectId,
      required CaptureSuggestionField field,
      required int limit,
    });

/// Focus-triggered, project-scoped suggestions for one required capture field.
///
/// The component owns only its target [controller]. It never reads or writes
/// another form field, which keeps selecting a historical value from changing
/// notes or either of the other required inputs.
class CaptureRecentSuggestions extends StatefulWidget {
  const CaptureRecentSuggestions({
    super.key,
    required this.projectId,
    required this.field,
    required this.controller,
    required this.focusNode,
    required this.load,
  });

  final String projectId;
  final CaptureSuggestionField field;
  final TextEditingController controller;
  final FocusNode focusNode;
  final CaptureRecentSuggestionsLoader load;

  @override
  State<CaptureRecentSuggestions> createState() =>
      _CaptureRecentSuggestionsState();
}

class _CaptureRecentSuggestionsState extends State<CaptureRecentSuggestions> {
  final Map<String, List<String>> _cache = {};
  List<String>? _suggestions;
  Object? _error;
  var _loading = false;
  var _request = 0;
  var _historySession = 0;
  CaptureOwnedRouteController? _historyController;

  String get _cacheKey => '${widget.projectId}\u0000${widget.field.name}';

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChanged);
    if (widget.focusNode.hasFocus) _onFocusChanged();
  }

  @override
  void didUpdateWidget(covariant CaptureRecentSuggestions oldWidget) {
    super.didUpdateWidget(oldWidget);
    final focusChanged = oldWidget.focusNode != widget.focusNode;
    final identityChanged =
        oldWidget.projectId != widget.projectId ||
        oldWidget.field != widget.field;
    final historyIdentityChanged =
        identityChanged ||
        focusChanged ||
        oldWidget.controller != widget.controller;
    if (historyIdentityChanged) _dismissHistory();
    if (focusChanged) {
      oldWidget.focusNode.removeListener(_onFocusChanged);
      widget.focusNode.addListener(_onFocusChanged);
    }
    if (identityChanged) {
      // Invalidate any request for the old project/field before exposing the
      // cached value (or loading) for the new identity.
      _request++;
      _suggestions = _cache[_cacheKey];
      _error = null;
      _loading = false;
    }
    if ((focusChanged || identityChanged) && widget.focusNode.hasFocus) {
      _loadIfNeeded();
    }
  }

  @override
  void dispose() {
    _dismissHistory();
    widget.focusNode.removeListener(_onFocusChanged);
    super.dispose();
  }

  void _onFocusChanged() {
    if (widget.focusNode.hasFocus) _loadIfNeeded();
    if (mounted) setState(() {});
  }

  void _loadIfNeeded() {
    if (_suggestions != null || _loading) return;
    _load();
  }

  Future<void> _load({bool retry = false}) async {
    if (!widget.focusNode.hasFocus) return;
    final key = _cacheKey;
    if (!retry && _cache.containsKey(key)) {
      setState(() {
        _suggestions = _cache[key];
        _error = null;
      });
      return;
    }
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await widget.load(
        projectId: widget.projectId,
        field: widget.field,
        limit: 20,
      );
      if (!mounted || request != _request || key != _cacheKey) return;
      final limited = values.take(20).toList(growable: false);
      setState(() {
        _cache[key] = limited;
        _suggestions = limited;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || request != _request || key != _cacheKey) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _select(String value) {
    widget.controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _dismissHistory() {
    _historySession++;
    final controller = _historyController;
    _historyController = null;
    controller?.dismiss();
  }

  Future<void> _showMore() async {
    if (_historyController != null) return;
    final values = _suggestions ?? const <String>[];
    final originProjectId = widget.projectId;
    final originField = widget.field;
    final originController = widget.controller;
    final originFocusNode = widget.focusNode;
    final session = ++_historySession;
    final routeController = CaptureOwnedRouteController();
    _historyController = routeController;
    String? selected;
    try {
      selected = await showDialog<String>(
        context: context,
        animationStyle: MediaQuery.disableAnimationsOf(context)
            ? AnimationStyle.noAnimation
            : null,
        builder: (dialogContext) {
          final route = ModalRoute.of(dialogContext);
          if (route != null) routeController.attach(route);
          return _SuggestionHistoryDialog(
            values: values,
            onSelected: (value) => Navigator.of(dialogContext).pop(value),
          );
        },
      );
    } finally {
      routeController.detach();
      if (identical(_historyController, routeController)) {
        _historyController = null;
      }
    }
    if (!mounted ||
        selected == null ||
        _historySession != session ||
        widget.projectId != originProjectId ||
        widget.field != originField ||
        widget.controller != originController ||
        widget.focusNode != originFocusNode) {
      return;
    }
    _select(selected);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final visible = widget.focusNode.hasFocus;
    final suggestions = _suggestions ?? const <String>[];
    final child = !visible
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _loading
                ? const SizedBox(
                    height: 24,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : _error != null
                ? Row(
                    children: [
                      Expanded(child: Text(strings.suggestionsLoadFailed)),
                      TextButton(
                        key: const Key('recent-suggestions-retry'),
                        onPressed: () => _load(retry: true),
                        child: Text(strings.retry),
                      ),
                    ],
                  )
                : suggestions.isEmpty
                ? Text(
                    strings.noRecentSuggestions,
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                : Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        strings.recentlyUsed,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      ...suggestions
                          .take(3)
                          .indexed
                          .map(
                            (entry) => ActionChip(
                              key: Key(
                                'recent-suggestion-${widget.field.name}-${entry.$1}',
                              ),
                              label: Text(entry.$2),
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _select(entry.$2),
                            ),
                          ),
                      if (suggestions.length > 3)
                        ActionChip(
                          key: const Key('recent-suggestions-more'),
                          label: Text(strings.more),
                          visualDensity: VisualDensity.compact,
                          onPressed: _showMore,
                        ),
                    ],
                  ),
          );
    final duration = AppMotion.durationOf(context, AppMotion.short4);
    if (duration == Duration.zero) {
      return KeyedSubtree(
        key: const Key('capture-recent-suggestions'),
        child: child,
      );
    }
    return AnimatedSize(
      key: const Key('capture-recent-suggestions'),
      duration: duration,
      curve: AppMotion.standard,
      alignment: Alignment.topCenter,
      child: child,
    );
  }
}

class _SuggestionHistoryDialog extends StatefulWidget {
  const _SuggestionHistoryDialog({
    required this.values,
    required this.onSelected,
  });

  final List<String> values;
  final ValueChanged<String> onSelected;

  @override
  State<_SuggestionHistoryDialog> createState() =>
      _SuggestionHistoryDialogState();
}

class _SuggestionHistoryDialogState extends State<_SuggestionHistoryDialog> {
  var _query = '';

  List<String> get _filtered => widget.values
      .where((value) => _asciiContains(value, _query))
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final values = _filtered;
    return buildAdaptiveAlertDialog<void>(
      dialogContext: context,
      title: Text(strings.searchHistory),
      content: SizedBox(
        width: defaultTargetPlatform == TargetPlatform.iOS ? 232 : 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('recent-suggestions-search'),
              autofocus: true,
              decoration: InputDecoration(
                labelText: strings.searchHistory,
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: values.isEmpty
                  ? Center(child: Text(strings.noRecentSuggestions))
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: values.length,
                      itemBuilder: (context, index) => ListTile(
                        title: Text(values[index]),
                        onTap: () => widget.onSelected(values[index]),
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [AppDialogAction(label: strings.cancel)],
    );
  }
}

bool _asciiContains(String value, String query) {
  final normalizedQuery = _asciiLower(query.trim());
  if (normalizedQuery.isEmpty) return true;
  return _asciiLower(value.trim()).contains(normalizedQuery);
}

String _asciiLower(String value) {
  return String.fromCharCodes(
    value.codeUnits.map(
      (codeUnit) =>
          codeUnit >= 0x41 && codeUnit <= 0x5a ? codeUnit + 0x20 : codeUnit,
    ),
  );
}
