import 'package:flutter/material.dart';
import 'package:sitemark/l10n/app_strings.dart';

enum CaptureDetailAction { edit, deleteOriginal, deleteRecord }

Future<CaptureDetailAction?> showCaptureDetailActionSheet(
  BuildContext context, {
  required bool canEdit,
  required bool canDeleteOriginal,
}) {
  return showModalBottomSheet<CaptureDetailAction>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => CaptureDetailActionList(
      key: const Key('capture-detail-action-sheet'),
      canEdit: canEdit,
      canDeleteOriginal: canDeleteOriginal,
      onSelected: (action) => Navigator.pop(sheetContext, action),
    ),
  );
}

/// Pure UI list: business availability is supplied by the detail screen.
class CaptureDetailActionList extends StatelessWidget {
  const CaptureDetailActionList({
    super.key,
    required this.canEdit,
    required this.canDeleteOriginal,
    required this.onSelected,
  });

  final bool canEdit;
  final bool canDeleteOriginal;
  final ValueChanged<CaptureDetailAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final error = Theme.of(context).colorScheme.error;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canEdit)
          ListTile(
            key: const Key('edit-record'),
            leading: const Icon(Icons.edit_outlined),
            title: Text(strings.editRecord),
            onTap: () => onSelected(CaptureDetailAction.edit),
          ),
        if (canDeleteOriginal)
          ListTile(
            key: const Key('delete-original'),
            leading: const Icon(Icons.cleaning_services_outlined),
            title: Text(strings.deleteOriginal),
            subtitle: Text(strings.confirmClearOriginals(1)),
            onTap: () => onSelected(CaptureDetailAction.deleteOriginal),
          ),
        ListTile(
          key: const Key('delete-record'),
          leading: Icon(Icons.delete_outline, color: error),
          title: Text(strings.deleteRecord, style: TextStyle(color: error)),
          subtitle: Text(strings.deleteRecordPrompt),
          onTap: () => onSelected(CaptureDetailAction.deleteRecord),
        ),
      ],
    );
  }
}
