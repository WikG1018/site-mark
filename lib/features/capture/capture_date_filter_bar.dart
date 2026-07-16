import 'package:flutter/material.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_filter.dart';
import 'package:sitemark/l10n/app_strings.dart';

/// Cascading year → month → day filter for capture lists.
///
/// Derives sorted distinct options from the supplied [summaries] using the
/// local capture date (`coalesce(capturedAt, createdAt)`). Selecting a year
/// resets month and day; selecting a month resets day; clearing a year resets
/// the entire selection. Disabled month/day controls show the "all" label
/// until their parent is selected.
class CaptureDateFilterBar extends StatelessWidget {
  const CaptureDateFilterBar({
    super.key,
    required this.filter,
    required this.summaries,
    required this.onChanged,
  });

  final CaptureFilter filter;
  final List<CaptureSummary> summaries;
  final ValueChanged<CaptureFilter> onChanged;

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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _menu(
            key: const Key('filter-year'),
            value: filter.year,
            options: years,
            allLabel: strings.allYears,
            labelFor: (value) => value.toString(),
            enabled: true,
            onChanged: (value) => onChanged(filter.selectYear(value)),
          ),
          _menu(
            key: const Key('filter-month'),
            value: filter.month,
            options: months,
            allLabel: strings.allMonths,
            labelFor: (value) => '$value${strings.monthSuffix}',
            enabled: filter.year != null,
            onChanged: (value) => onChanged(filter.selectMonth(value)),
          ),
          _menu(
            key: const Key('filter-day'),
            value: filter.day,
            options: days,
            allLabel: strings.allDays,
            labelFor: (value) => '$value${strings.daySuffix}',
            enabled: filter.year != null && filter.month != null,
            onChanged: (value) => onChanged(filter.selectDay(value)),
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
    final entries = <DropdownMenuEntry<int?>>[];
    entries.add(DropdownMenuEntry<int?>(value: null, label: allLabel));
    for (final option in options) {
      entries.add(
        DropdownMenuEntry<int?>(value: option, label: labelFor(option)),
      );
    }
    return SizedBox(
      width: 140,
      child: DropdownMenu<int?>(
        key: key,
        enabled: enabled,
        initialSelection: value,
        expandedInsets: EdgeInsets.zero,
        menuHeight: 320,
        dropdownMenuEntries: entries,
        onSelected: (next) => onChanged(next),
      ),
    );
  }
}
