import 'package:flutter/material.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/shared/ui/adaptive_sheet.dart';

enum CaptureDetailAction { edit, deleteOriginal, deleteRecord }

Future<CaptureDetailAction?> showCaptureDetailActionSheet(
  BuildContext context, {
  required bool canEdit,
  required bool canDeleteOriginal,
}) {
  final strings = AppStrings.of(context);
  return showAppActionSheet<CaptureDetailAction>(
    context: context,
    sheetKey: const Key('capture-detail-action-sheet'),
    actions: [
      if (canEdit)
        AppSheetAction(
          key: const Key('edit-record'),
          label: strings.editRecord,
          icon: Icons.edit_outlined,
          result: CaptureDetailAction.edit,
        ),
      if (canDeleteOriginal)
        AppSheetAction(
          key: const Key('delete-original'),
          label: strings.deleteOriginal,
          icon: Icons.cleaning_services_outlined,
          subtitle: strings.confirmClearOriginals(1),
          result: CaptureDetailAction.deleteOriginal,
        ),
      AppSheetAction(
        key: const Key('delete-record'),
        label: strings.deleteRecord,
        icon: Icons.delete_outline,
        subtitle: strings.deleteRecordPrompt,
        isDestructive: true,
        result: CaptureDetailAction.deleteRecord,
      ),
    ],
  );
}
