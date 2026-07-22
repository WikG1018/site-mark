import 'package:flutter/material.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_filter.dart';
import 'package:sitemark/features/capture/compact_filter_menu.dart';
import 'package:sitemark/l10n/app_strings.dart';

/// Cascading year → month → day filter for capture lists.
///
/// Derives sorted distinct options from the supplied [summaries] using the
/// local capture date (`coalesce(capturedAt, createdAt)`). Selecting a year
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
class CaptureDateFilterBar extends StatelessWidget {
  const CaptureDateFilterBar({
    super.key,
    required this.filter,
    required this.summaries,
    required this.onChanged,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
  });

  final CaptureFilter filter;
  final List<CaptureSummary> summaries;
  final ValueChanged<CaptureFilter> onChanged;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final dates = summaries
        .map(
          (summary) => summary.capture.capturedAt ?? summary.capture.createdAt,
        )
        .toList();
    final options = _cascadeOptions(dates, filter);

    if (MediaQuery.sizeOf(context).width < 360) {
      return Padding(
        padding: padding,
        child: Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            key: const Key('filter-sheet-trigger'),
            icon: const Icon(Icons.filter_list_outlined),
            tooltip: strings.filterAction,
            onPressed: () => _openFilterSheet(context, dates),
          ),
        ),
      );
    }

    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: _menu(
              key: const Key('filter-year'),
              value: filter.year,
              options: options.years,
              allLabel: strings.allYears,
              labelFor: (value) => value.toString(),
              enabled: true,
              onChanged: (value) => onChanged(filter.selectYear(value)),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _menu(
              key: const Key('filter-month'),
              value: filter.month,
              options: options.months,
              allLabel: strings.allMonths,
              labelFor: (value) => '$value${strings.monthSuffix}',
              enabled: filter.year != null,
              onChanged: (value) => onChanged(filter.selectMonth(value)),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _menu(
              key: const Key('filter-day'),
              value: filter.day,
              options: options.days,
              allLabel: strings.allDays,
              labelFor: (value) => '$value${strings.daySuffix}',
              enabled: filter.year != null && filter.month != null,
              onChanged: (value) => onChanged(filter.selectDay(value)),
            ),
          ),
        ],
      ),
    );
  }

  void _openFilterSheet(BuildContext context, List<DateTime> dates) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => _NarrowFilterSheet(
        filter: filter,
        dates: dates,
        onChanged: onChanged,
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

List<int> _distinctSorted(Iterable<int> values) {
  final set = values.toSet();
  final list = set.toList()..sort();
  return list;
}

({List<int> years, List<int> months, List<int> days}) _cascadeOptions(
  List<DateTime> dates,
  CaptureFilter filter,
) {
  final years = _distinctSorted(dates.map((date) => date.year));
  final months = filter.year == null
      ? <int>[]
      : _distinctSorted(
          dates
              .where((date) => date.year == filter.year)
              .map((date) => date.month),
        );
  final days = (filter.year == null || filter.month == null)
      ? <int>[]
      : _distinctSorted(
          dates
              .where(
                (date) =>
                    date.year == filter.year && date.month == filter.month,
              )
              .map((date) => date.day),
        );
  return (years: years, months: months, days: days);
}

/// Bottom-sheet body for the sub-360dp layout: mirrors the wide bar's three
/// cascading menus as full-width [DropdownMenu]s. Holds a local copy of the
/// filter so the month/day option lists react to in-sheet selections while
/// forwarding every change to the parent.
class _NarrowFilterSheet extends StatefulWidget {
  const _NarrowFilterSheet({
    required this.filter,
    required this.dates,
    required this.onChanged,
  });

  final CaptureFilter filter;
  final List<DateTime> dates;
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
    final options = _cascadeOptions(widget.dates, _filter);
    return SafeArea(
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
    );
  }

  Widget _dropdown({
    required Key key,
    required int? value,
    required List<int> options,
    required String allLabel,
    required String Function(int value) labelFor,
    required bool enabled,
    required ValueChanged<int?> onChanged,
  }) {
    return DropdownMenu<int?>(
      key: key,
      initialSelection: value,
      enabled: enabled,
      expandedInsets: EdgeInsets.zero,
      label: Text(allLabel),
      dropdownMenuEntries: [
        DropdownMenuEntry<int?>(value: null, label: allLabel),
        for (final option in options)
          DropdownMenuEntry<int?>(value: option, label: labelFor(option)),
      ],
      onSelected: onChanged,
    );
  }
}
