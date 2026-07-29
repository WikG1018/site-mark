import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/features/projects/project_restore_flow.dart';
import 'package:sitemark/features/settings/settings_section_scaffold.dart';
import 'package:sitemark/l10n/app_strings.dart';

class BackupRestoreSectionScreen extends ConsumerStatefulWidget {
  const BackupRestoreSectionScreen({super.key, this.restoreDependencies});

  final ProjectRestoreFlowDependencies? restoreDependencies;

  @override
  ConsumerState<BackupRestoreSectionScreen> createState() =>
      _BackupRestoreSectionScreenState();
}

class _BackupRestoreSectionScreenState
    extends ConsumerState<BackupRestoreSectionScreen> {
  final _restoreLifetime = ProjectRestoreFlowLifetime();
  bool _restoring = false;

  @override
  void dispose() {
    _restoreLifetime.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    if (_restoring) return;
    setState(() => _restoring = true);
    try {
      await runProjectRestoreFlow(
        context,
        ref,
        dependencies: widget.restoreDependencies,
        lifetime: _restoreLifetime,
      );
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return SettingsSectionScaffold(
      title: strings.backupAndRestore,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(strings.backupExplanation),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              key: const Key('backup-projects'),
              leading: const Icon(Icons.archive_outlined),
              title: Text(strings.backupProjects),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/backup-restore/backup'),
            ),
          ),
          const SizedBox(height: 24),
          Text(strings.restoreExplanation),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              key: const Key('restore-projects'),
              leading: const Icon(Icons.unarchive_outlined),
              title: Text(strings.restoreProjects),
              trailing: const Icon(Icons.chevron_right),
              onTap: _restoring ? null : _restore,
            ),
          ),
        ],
      ),
    );
  }
}
