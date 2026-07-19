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
/// on a single line at 360dp. The [padding] defaults to a small horizontal
/// inset; callers that embed this bar inside their own [Row] (e.g. the
/// all-records screen beside a project menu) pass [EdgeInsets.zero].
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

    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: _menu(
              key: const Key('filter-year'),
              value: filter.year,
              options: years,
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
              options: months,
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
              options: days,
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

  List<int> _distinctSorted(Iterable<int> values) {
    final set = values.toSet();
    final list = set.toList()..sort();
    return list;
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
