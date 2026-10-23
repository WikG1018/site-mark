import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sitemark/l10n/app_strings.dart';

/// One-shot display timestamp, deliberately separate from capture evidence.
class WatermarkTimeField extends StatelessWidget {
  const WatermarkTimeField({
    super.key,
    required this.value,
    required this.onChanged,
    this.originalTime,
    this.enabled = true,
  });
  final DateTime? value;
  final DateTime? originalTime;
  final ValueChanged<DateTime?> onChanged;
  final bool enabled;

  Future<void> _pick(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final initial = value ?? originalTime ?? DateTime.now();
    final first = DateTime(1900);
    final last = DateTime(2100, 12, 31);
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(first)
          ? first
          : initial.isAfter(last)
          ? last
          : initial,
      firstDate: first,
      lastDate: last,
      helpText: AppStrings.of(context).watermarkTime,
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !context.mounted) return;
    onChanged(
      DateTime(date.year, date.month, date.day, time.hour, time.minute),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          key: const Key('watermark-time-field'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule_outlined),
          title: Text(strings.watermarkTime),
          subtitle: Text(
            value == null
                ? strings.automaticPhotoTime
                : DateFormat('yyyy-MM-dd HH:mm').format(value!),
          ),
          trailing: const Icon(Icons.edit_calendar_outlined),
          enabled: enabled,
          onTap: enabled ? () => _pick(context) : null,
        ),
        if (value != null)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              key: const Key('reset-watermark-time'),
              onPressed: enabled ? () => onChanged(null) : null,
              child: Text(strings.restoreAutomaticTime),
            ),
          ),
        Text(
          strings.watermarkTimeHint,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
