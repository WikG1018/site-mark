import 'package:flutter/material.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_filter.dart';
import 'package:sitemark/l10n/app_strings.dart';

class CaptureActiveFilterChips extends StatelessWidget {
  const CaptureActiveFilterChips({
    super.key,
    required this.filter,
    required this.projects,
    required this.onChanged,
  });

  final CaptureFilter filter;
  final List<Project> projects;
  final ValueChanged<CaptureFilter> onChanged;

  List<Widget> _chips(BuildContext context) {
    final strings = AppStrings.of(context);
    final chips = <Widget>[];
    if (filter.projectId != null) {
      var label = strings.deletedProject;
      for (final project in projects) {
        if (project.id == filter.projectId) label = project.name;
      }
      chips.add(
        InputChip(
          key: const Key('active-filter-project'),
          label: Text(label),
          deleteIcon: const Icon(
            Icons.close,
            key: Key('remove-filter-project'),
          ),
          deleteButtonTooltipMessage: strings.removeProjectFilter,
          onDeleted: () => onChanged(const CaptureFilter()),
        ),
      );
    }
    if (filter.year != null) {
      chips.add(
        InputChip(
          key: const Key('active-filter-year'),
          label: Text('${filter.year}'),
          deleteIcon: const Icon(Icons.close, key: Key('remove-filter-year')),
          deleteButtonTooltipMessage: strings.removeYearFilter,
          onDeleted: () => onChanged(filter.selectYear(null)),
        ),
      );
    }
    if (filter.month != null) {
      chips.add(
        InputChip(
          key: const Key('active-filter-month'),
          label: Text(strings.monthFilterLabel(filter.month!)),
          deleteIcon: const Icon(Icons.close, key: Key('remove-filter-month')),
          deleteButtonTooltipMessage: strings.removeMonthFilter,
          onDeleted: () => onChanged(filter.selectMonth(null)),
        ),
      );
    }
    if (filter.day != null) {
      chips.add(
        InputChip(
          key: const Key('active-filter-day'),
          label: Text(strings.dayFilterLabel(filter.day!)),
          deleteIcon: const Icon(Icons.close, key: Key('remove-filter-day')),
          deleteButtonTooltipMessage: strings.removeDayFilter,
          onDeleted: () => onChanged(filter.selectDay(null)),
        ),
      );
    }
    return chips;
  }

  @override
  Widget build(BuildContext context) {
    final chips = _chips(context);
    if (chips.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      key: const Key('active-filter-chips'),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < chips.length; index++) ...[
            if (index > 0) const SizedBox(width: 8),
            chips[index],
          ],
        ],
      ),
    );
  }
}
