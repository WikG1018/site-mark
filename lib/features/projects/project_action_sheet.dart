import 'package:flutter/material.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/project_lifecycle.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/shared/ui/adaptive_sheet.dart';

enum ProjectAction {
  watermark,
  backup,
  rename,
  pin,
  unpin,
  complete,
  archive,
  reopen,
  delete,
}

typedef ProjectActionItem = ({
  ProjectAction action,
  Key key,
  IconData icon,
  String label,
});

List<ProjectActionItem> projectActionsFor(
  Project project,
  AppStrings strings,
) => [
  (
    action: ProjectAction.watermark,
    key: const Key('project-watermark-action'),
    icon: Icons.tune_outlined,
    label: strings.projectWatermarkSettings,
  ),
  (
    action: ProjectAction.backup,
    key: const Key('project-backup-action'),
    icon: Icons.archive_outlined,
    label: strings.backupProjects,
  ),
  (
    action: ProjectAction.rename,
    key: const Key('rename-project'),
    icon: Icons.edit_outlined,
    label: strings.renameProject,
  ),
  project.isPinned
      ? (
          action: ProjectAction.unpin,
          key: const Key('unpin-project'),
          icon: Icons.push_pin,
          label: strings.unpinProject,
        )
      : (
          action: ProjectAction.pin,
          key: const Key('pin-project'),
          icon: Icons.push_pin_outlined,
          label: strings.pinProject,
        ),
  ...switch (project.lifecycleStatus) {
    ProjectLifecycleStatus.active => [
      (
        action: ProjectAction.complete,
        key: const Key('complete-project'),
        icon: Icons.check_circle_outline,
        label: strings.markProjectCompleted,
      ),
      (
        action: ProjectAction.archive,
        key: const Key('archive-project'),
        icon: Icons.archive_outlined,
        label: strings.archiveProject,
      ),
    ],
    ProjectLifecycleStatus.completed => [
      (
        action: ProjectAction.reopen,
        key: const Key('reopen-project'),
        icon: Icons.replay_outlined,
        label: strings.reopenProject,
      ),
      (
        action: ProjectAction.archive,
        key: const Key('archive-project'),
        icon: Icons.archive_outlined,
        label: strings.archiveProject,
      ),
    ],
    ProjectLifecycleStatus.archived => [
      (
        action: ProjectAction.reopen,
        key: const Key('reopen-project'),
        icon: Icons.unarchive_outlined,
        label: strings.restoreProjectToActive,
      ),
    ],
  },
  (
    action: ProjectAction.delete,
    key: const Key('delete-project'),
    icon: Icons.delete_outline,
    label: strings.deleteProject,
  ),
];

Future<ProjectAction?> showProjectActionSheet(
  BuildContext context,
  Project project,
) {
  final strings = AppStrings.of(context);
  final actions = projectActionsFor(project, strings);
  return showAppActionSheet<ProjectAction>(
    context: context,
    sheetKey: const Key('project-action-sheet'),
    actions: [
      for (final item in actions)
        AppSheetAction(
          key: item.key,
          label: item.label,
          icon: item.icon,
          isDestructive: item.action == ProjectAction.delete,
          result: item.action,
        ),
    ],
  );
}
