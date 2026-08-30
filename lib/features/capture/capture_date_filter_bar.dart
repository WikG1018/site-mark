import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sitemark/domain/capture_filter.dart';
import 'package:sitemark/domain/capture_list_query.dart';
import 'package:sitemark/features/capture/compact_filter_menu.dart';
import 'package:sitemark/l10n/app_strings.dart';

/// Cascading year → month → day filter for capture lists.
///
/// Consumes repository-derived [options]. Selecting a year
/// resets month and day; selecting a month resets day; clearing a year resets
/// the entire selection. Disabled month/day controls show the "all" label
/// until their parent is selected.
///
/// The three controls share one [Row] of equal [Expanded] children so they fit
/// on a single line at 360dp. Below 360dp the bar degrades to a single filter
/// [IconButton] that hosts the same three cascading choices inside a
/// `showModalBottomSheet`. The [padding] defaults to a small horizontal inset;
/// callers that embed this bar inside their own [Row] (e.g. the all-records
/// screen beside a project menu) pass [EdgeInsets.zero].
class CaptureDateFilterBar extends StatefulWidget {
  const CaptureDateFilterBar({
    super.key,
    required this.filter,
    required this.options,
    required this.onChanged,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
  });

  final CaptureFilter filter;
  final CaptureDateOptions options;
  final ValueChanged<CaptureFilter> onChanged;
  final EdgeInsetsGeometry padding;

  @override
  State<CaptureDateFilterBar> createState() => _CaptureDateFilterBarState();
}

class _CaptureDateFilterBarState extends State<CaptureDateFilterBar> {
  late final ValueNotifier<CaptureDateOptions> _options = ValueNotifier(
    widget.options,
  );

  @override
  void didUpdateWidget(covariant CaptureDateFilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.options, widget.options)) {
      final options = widget.options;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(widget.options, options)) {
          _options.value = options;
        }
      });
    }
  }

  @override
  void dispose() {
    _options.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    if (MediaQuery.sizeOf(context).width < 360) {
      return Padding(
        padding: widget.padding,
        child: Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            key: const Key('filter-sheet-trigger'),
            icon: const Icon(Icons.filter_list_outlined),
            tooltip: strings.filterAction,
            onPressed: () => _openFilterSheet(context),
          ),
        ),
      );
    }

    return Padding(
      padding: widget.padding,
      child: Row(
        children: [
          Expanded(
            child: _menu(
              key: const Key('filter-year'),
              value: widget.filter.year,
              options: widget.options.years,
              allLabel: strings.allYears,
              labelFor: (value) => value.toString(),
              enabled: true,
              onChanged: (value) =>
                  widget.onChanged(widget.filter.selectYear(value)),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _menu(
              key: const Key('filter-month'),
              value: widget.filter.month,
              options: widget.options.months,
              allLabel: strings.allMonths,
              labelFor: (value) => '$value${strings.monthSuffix}',
              enabled: widget.filter.year != null,
              onChanged: (value) =>
                  widget.onChanged(widget.filter.selectMonth(value)),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _menu(
              key: const Key('filter-day'),
              value: widget.filter.day,
              options: widget.options.days,
              allLabel: strings.allDays,
              labelFor: (value) => '$value${strings.daySuffix}',
              enabled:
                  widget.filter.year != null && widget.filter.month != null,
              onChanged: (value) =>
                  widget.onChanged(widget.filter.selectDay(value)),
            ),
          ),
        ],
      ),
    );
  }

  void _openFilterSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => _NarrowFilterSheet(
        filter: widget.filter,
        options: _options,
        onChanged: widget.onChanged,
      ),
    );
  }

  Widget _menu({
    required Key key,
    required int? value,
    required List<int> options,
    required String allLabel,
    required String Function(int value) labelFor,
    required bool enabled,
    required ValueChanged<int?> onChanged,
  }) {
    final entries = <(int?, String)>[(null, allLabel)];
    for (final option in options) {
      entries.add((option, labelFor(option)));
    }
    final label = value == null ? allLabel : labelFor(value);
    return CompactFilterMenu<int?>(
      key: key,
      label: label,
      selectedValue: value,
      entries: entries,
      enabled: enabled,
      onSelected: onChanged,
    );
  }
}

/// Bottom-sheet body for the sub-360dp layout: mirrors the wide bar's three
/// cascading menus as full-width [DropdownMenu]s. Holds a local copy of the
/// filter so the month/day option lists react to in-sheet selections while
/// forwarding every change to the parent.
class _NarrowFilterSheet extends StatefulWidget {
  const _NarrowFilterSheet({
    required this.filter,
    required this.options,
    required this.onChanged,
  });

  final CaptureFilter filter;
  final ValueListenable<CaptureDateOptions> options;
  final ValueChanged<CaptureFilter> onChanged;

  @override
  State<_NarrowFilterSheet> createState() => _NarrowFilterSheetState();
}

class _NarrowFilterSheetState extends State<_NarrowFilterSheet> {
  late CaptureFilter _filter = widget.filter;

  void _update(CaptureFilter next) {
    setState(() => _filter = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return ValueListenableBuilder<CaptureDateOptions>(
      valueListenable: widget.options,
      builder: (context, options, _) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _dropdown(
                key: ValueKey('sheet-year-${_filter.year}'),
                value: _filter.year,
                options: options.years,
                allLabel: strings.allYears,
                labelFor: (value) => value.toString(),
                enabled: true,
                onChanged: (value) => _update(_filter.selectYear(value)),
              ),
              const SizedBox(height: 12),
              _dropdown(
                key: ValueKey('sheet-month-${_filter.month}'),
                value: _filter.month,
                options: options.months,
                allLabel: strings.allMonths,
                labelFor: (value) => '$value${strings.monthSuffix}',
                enabled: _filter.year != null,
                onChanged: (value) => _update(_filter.selectMonth(value)),
              ),
              const SizedBox(height: 12),
              _dropdown(
                key: ValueKey('sheet-day-${_filter.day}'),
                value: _filter.day,
                options: options.days,
                allLabel: strings.allDays,
                labelFor: (value) => '$value${strings.daySuffix}',
                enabled: _filter.year != null && _filter.month != null,
                onChanged: (value) => _update(_filter.selectDay(value)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Full-width trigger mirroring the wide bar's [CompactFilterMenu] so the
  /// narrow sheet stays visually identical to the inline filter row.
  Widget _dropdown({
    required Key key,
    required int? value,
    required List<int> options,
    required String allLabel,
    required String Function(int value) labelFor,
    required bool enabled,
    required ValueChanged<int?> onChanged,
  }) {
    final entries = <(int?, String)>[(null, allLabel)];
    for (final option in options) {
      entries.add((option, labelFor(option)));
    }
    return CompactFilterMenu<int?>(
      key: key,
      label: value == null ? allLabel : labelFor(value),
      selectedValue: value,
      entries: entries,
      enabled: enabled,
      onSelected: onChanged,
    );
  }
}
