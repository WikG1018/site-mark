import 'package:flutter/material.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/shared/ui/adaptive_segmented_button.dart';

enum CaptureDetailSection { fieldRecord, fileInfo }

/// Stateless section selector for the capture detail surface.
class CaptureDetailTabs extends StatelessWidget {
  const CaptureDetailTabs({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final CaptureDetailSection value;
  final ValueChanged<CaptureDetailSection> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return SizedBox(
      width: double.infinity,
      child: AdaptiveSegmentedButton<CaptureDetailSection>(
        segments: [
          ButtonSegment(
            value: CaptureDetailSection.fieldRecord,
            label: Semantics(
              key: const Key('detail-tab-field-record'),
              label: strings.fieldRecordTab,
              button: true,
              selected: value == CaptureDetailSection.fieldRecord,
              onTap: () => onChanged(CaptureDetailSection.fieldRecord),
              child: ExcludeSemantics(child: Text(strings.fieldRecordTab)),
            ),
          ),
          ButtonSegment(
            value: CaptureDetailSection.fileInfo,
            label: Semantics(
              key: const Key('detail-tab-file-info'),
              label: strings.fileInfoTab,
              button: true,
              selected: value == CaptureDetailSection.fileInfo,
              onTap: () => onChanged(CaptureDetailSection.fileInfo),
              child: ExcludeSemantics(child: Text(strings.fileInfoTab)),
            ),
          ),
        ],
        selected: {value},
        onSelectionChanged: (selection) {
          if (selection.isNotEmpty) onChanged(selection.single);
        },
      ),
    );
  }
}
