import 'package:flutter/material.dart';
import 'package:sitemark/domain/project_lifecycle.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/shared/ui/adaptive_sheet.dart';

Future<ProjectLifecycleStatus?> showProjectStatusFilterSheet(
  BuildContext context, {
  required ProjectLifecycleStatus current,
}) {
  final strings = AppStrings.of(context);
  return showAppActionSheet<ProjectLifecycleStatus>(
    context: context,
    title: strings.projectStatusFilterTitle,
    actions: [
      for (final status in ProjectLifecycleStatus.values)
        AppSheetAction(
          key: Key('project-status-${status.name}'),
          label: switch (status) {
            ProjectLifecycleStatus.active => strings.projectStatusActive,
            ProjectLifecycleStatus.completed => strings.projectStatusCompleted,
            ProjectLifecycleStatus.archived => strings.projectStatusArchived,
          },
          checked: current == status,
          result: status,
        ),
    ],
  );
}
