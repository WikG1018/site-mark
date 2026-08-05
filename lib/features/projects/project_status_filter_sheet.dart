import 'package:flutter/material.dart';
import 'package:sitemark/domain/project_lifecycle.dart';
import 'package:sitemark/l10n/app_strings.dart';

Future<ProjectLifecycleStatus?> showProjectStatusFilterSheet(
  BuildContext context, {
  required ProjectLifecycleStatus current,
}) {
  final strings = AppStrings.of(context);
  return showModalBottomSheet<ProjectLifecycleStatus>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                strings.projectStatusFilterTitle,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            ListTile(
              key: const Key('project-status-active'),
              selected: current == ProjectLifecycleStatus.active,
              title: Text(strings.projectStatusActive),
              trailing: current == ProjectLifecycleStatus.active
                  ? const Icon(Icons.check)
                  : null,
              onTap: () =>
                  Navigator.of(sheetContext).pop(ProjectLifecycleStatus.active),
            ),
            ListTile(
              key: const Key('project-status-completed'),
              selected: current == ProjectLifecycleStatus.completed,
              title: Text(strings.projectStatusCompleted),
              trailing: current == ProjectLifecycleStatus.completed
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.of(
                sheetContext,
              ).pop(ProjectLifecycleStatus.completed),
            ),
            ListTile(
              key: const Key('project-status-archived'),
              selected: current == ProjectLifecycleStatus.archived,
              title: Text(strings.projectStatusArchived),
              trailing: current == ProjectLifecycleStatus.archived
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.of(
                sheetContext,
              ).pop(ProjectLifecycleStatus.archived),
            ),
          ],
        ),
      );
    },
  );
}
