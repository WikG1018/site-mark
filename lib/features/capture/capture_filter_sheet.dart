import 'package:flutter/material.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_filter.dart';
import 'package:sitemark/domain/capture_list_query.dart';
import 'package:sitemark/l10n/app_strings.dart';

typedef CaptureDateOptionsLoader =
    Future<CaptureDateOptions> Function(CaptureFilter draft);

Future<CaptureFilter?> showCaptureFilterSheet({
  required BuildContext context,
  required CaptureFilter initial,
  required List<Project> projects,
  required CaptureDateOptions options,
  required CaptureDateOptionsLoader optionsLoader,
}) {
  return showModalBottomSheet<CaptureFilter>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : null,
    builder: (_) => CaptureFilterSheet(
      initial: initial,
      projects: projects,
      options: options,
      optionsLoader: optionsLoader,
      disableAnimations: MediaQuery.disableAnimationsOf(context),
    ),
  );
}

class CaptureFilterSheet extends StatefulWidget {
  const CaptureFilterSheet({
    super.key,
    required this.initial,
    required this.projects,
    required this.options,
    required this.optionsLoader,
    this.disableAnimations = false,
  });

  final CaptureFilter initial;
  final List<Project> projects;
  final CaptureDateOptions options;
  final CaptureDateOptionsLoader optionsLoader;
  final bool disableAnimations;

  @override
  State<CaptureFilterSheet> createState() => _CaptureFilterSheetState();
}

class _CaptureFilterSheetState extends State<CaptureFilterSheet> {
  late CaptureFilter _draft = widget.initial;
  late CaptureDateOptions _options = widget.options;
  int _optionsGeneration = 0;

  void _update(CaptureFilter next) => setState(() => _draft = next);

  Future<void> _updateAndReload(CaptureFilter next) async {
    final generation = ++_optionsGeneration;
    setState(() {
      _draft = next;
      _options = const CaptureDateOptions();
    });
    try {
      final options = await widget.optionsLoader(next);
      if (!mounted || generation != _optionsGeneration) return;
      setState(() => _options = options);
    } catch (_) {
      if (!mounted || generation != _optionsGeneration) return;
      setState(() => _options = const CaptureDateOptions());
    }
  }

  @override
  void dispose() {
    _optionsGeneration++;
    super.dispose();
  }

  List<int> get _years {
    final values = {..._options.years, ?_draft.year}.toList()..sort();
    return values;
  }

  List<int> get _months {
    if (_draft.year == null) return const [];
    final values = {..._options.months, ?_draft.month}.toList()..sort();
    return values;
  }

  List<int> get _days {
    if (_draft.year == null || _draft.month == null) return const [];
    final values = {..._options.days, ?_draft.day}.toList()..sort();
    return values;
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                strings.filterRecords,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _section(
                      context,
                      animationKey: const Key('filter-project-opacity'),
                      label: strings.projects,
                      children: [
                        _choice<String?>(
                          key: const Key('filter-project-all'),
                          label: strings.allProjects,
                          value: null,
                          selected: _draft.projectId == null,
                          onSelected: (value) =>
                              _updateAndReload(CaptureFilter(projectId: value)),
                        ),
                        for (final project in widget.projects)
                          _choice<String?>(
                            key: Key('filter-project-${project.id}'),
                            label: project.name,
                            value: project.id,
                            selected: _draft.projectId == project.id,
                            onSelected: (value) => _updateAndReload(
                              CaptureFilter(projectId: value),
                            ),
                          ),
                      ],
                    ),
                    _section(
                      context,
                      animationKey: const Key('filter-year-opacity'),
                      label: strings.allYears,
                      enabled: _years.isNotEmpty,
                      children: [
                        _choice<int?>(
                          key: const Key('filter-year-all'),
                          label: strings.allYears,
                          value: null,
                          selected: _draft.year == null,
                          onSelected: (value) =>
                              _updateAndReload(_draft.selectYear(value)),
                        ),
                        for (final year in _years)
                          _choice<int?>(
                            key: Key('filter-year-$year'),
                            label: '$year',
                            value: year,
                            selected: _draft.year == year,
                            onSelected: (value) =>
                                _updateAndReload(_draft.selectYear(value)),
                          ),
                      ],
                    ),
                    _section(
                      context,
                      animationKey: const Key('filter-month-opacity'),
                      label: strings.allMonths,
                      enabled: _draft.year != null,
                      children: [
                        _choice<int?>(
                          key: const Key('filter-month-all'),
                          label: strings.allMonths,
                          value: null,
                          selected: _draft.month == null,
                          onSelected: (value) =>
                              _updateAndReload(_draft.selectMonth(value)),
                        ),
                        for (final month in _months)
                          _choice<int?>(
                            key: Key('filter-month-$month'),
                            label: '$month${strings.monthSuffix}',
                            value: month,
                            selected: _draft.month == month,
                            onSelected: (value) =>
                                _updateAndReload(_draft.selectMonth(value)),
                          ),
                      ],
                    ),
                    _section(
                      context,
                      animationKey: const Key('filter-day-opacity'),
                      label: strings.allDays,
                      enabled: _draft.year != null && _draft.month != null,
                      children: [
                        _choice<int?>(
                          key: const Key('filter-day-all'),
                          label: strings.allDays,
                          value: null,
                          selected: _draft.day == null,
                          onSelected: (value) =>
                              _update(_draft.selectDay(value)),
                        ),
                        for (final day in _days)
                          _choice<int?>(
                            key: Key('filter-day-$day'),
                            label: '$day${strings.daySuffix}',
                            value: day,
                            selected: _draft.day == day,
                            onSelected: (value) =>
                                _update(_draft.selectDay(value)),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      key: const Key('filter-reset'),
                      onPressed: () => _updateAndReload(const CaptureFilter()),
                      child: Text(strings.resetFilters),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('filter-cancel'),
                      onPressed: () => Navigator.pop(context),
                      child: Text(strings.cancel),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      key: const Key('filter-apply'),
                      onPressed: () => Navigator.pop(context, _draft),
                      child: Text(strings.applyFilters),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(
    BuildContext context, {
    required Key animationKey,
    required String label,
    required List<Widget> children,
    bool enabled = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Semantics(
        container: true,
        enabled: enabled,
        label: label,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 6),
              child: Text(label, style: Theme.of(context).textTheme.labelLarge),
            ),
            IgnorePointer(
              ignoring: !enabled,
              child: AnimatedOpacity(
                key: animationKey,
                duration:
                    widget.disableAnimations ||
                        MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 150),
                opacity: enabled ? 1 : 0.45,
                child: Wrap(spacing: 8, runSpacing: 4, children: children),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _choice<T>({
    required Key key,
    required String label,
    required T value,
    required bool selected,
    required ValueChanged<T> onSelected,
  }) {
    return ChoiceChip(
      key: key,
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(value),
    );
  }
}
