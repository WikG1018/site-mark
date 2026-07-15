import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/l10n/app_strings.dart';

class ProjectDetailScreen extends ConsumerWidget {
  const ProjectDetailScreen({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final database = ref.watch(databaseProvider);
    final strings = AppStrings.of(context);
    return FutureBuilder<Project?>(
      future: database.projectById(projectId),
      builder: (context, projectSnapshot) {
        final project = projectSnapshot.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(project?.name ?? strings.appName),
            actions: [
              if (project != null)
                IconButton(
                  onPressed: () =>
                      context.go('/projects/${project.id}/settings'),
                  tooltip: strings.watermarkSettings,
                  icon: const Icon(Icons.tune_outlined),
                ),
              if (project != null)
                IconButton(
                  onPressed: () => _exportProject(context, ref, project.id),
                  tooltip: strings.exportProject,
                  icon: const Icon(Icons.archive_outlined),
                ),
            ],
          ),
          body: project == null
              ? const Center(child: CircularProgressIndicator())
              : StreamBuilder<List<CaptureRecord>>(
                  stream: database.watchCapturesForProject(projectId),
                  builder: (context, captureSnapshot) {
                    if (!captureSnapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final captures = captureSnapshot.data!;
                    return CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                            child: _ProjectHeader(project: project),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                            child: Text(
                              strings.captureRecords,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                        ),
                        if (captures.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(
                              child: Text(
                                strings.noCaptures,
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                            ),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                            sliver: SliverList.separated(
                              itemCount: captures.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) => _CaptureCard(
                                capture: captures[index],
                                strings: strings,
                                onTap: () => context.go(
                                  '/projects/$projectId/captures/${captures[index].id}',
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
          floatingActionButton: project == null
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => context.go('/projects/$projectId/capture'),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: Text(strings.capture),
                ),
        );
      },
    );
  }

  Future<void> _exportProject(
    BuildContext context,
    WidgetRef ref,
    String projectId,
  ) async {
    final strings = AppStrings.of(context);
    var includeOriginals = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(strings.exportProjectData),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: includeOriginals,
                title: Text(strings.includeOriginals),
                onChanged: (value) {
                  setDialogState(() => includeOriginals = value ?? false);
                },
              ),
              Text(strings.includeOriginalsHint),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(strings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(strings.generateAndShare),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final result = await ref
          .read(projectExportServiceProvider)
          .exportProject(
            projectId: projectId,
            includeOriginals: includeOriginals,
          );
      await ref.read(shareFileServiceProvider).shareFile(result.outputZipPath);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${strings.exportFailed}: $error')),
      );
    }
  }
}

class _ProjectHeader extends StatelessWidget {
  const _ProjectHeader({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(
              Icons.apartment_outlined,
              size: 42,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (project.description != null) ...[
                    const SizedBox(height: 4),
                    Text(project.description!),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CaptureCard extends StatelessWidget {
  const _CaptureCard({
    required this.capture,
    required this.strings,
    required this.onTap,
  });

  final CaptureRecord capture;
  final AppStrings strings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = switch (capture.status) {
      CaptureStatus.ready => (
        strings.ready,
        Icons.check_circle_outline,
        Colors.green,
      ),
      CaptureStatus.failed => (strings.failed, Icons.error_outline, Colors.red),
      CaptureStatus.pendingCamera => (
        strings.pendingCamera,
        Icons.photo_camera_outlined,
        Colors.orange,
      ),
      CaptureStatus.captured => (
        strings.processing,
        Icons.hourglass_top,
        Colors.orange,
      ),
      CaptureStatus.rendering => (
        strings.rendering,
        Icons.auto_awesome_outlined,
        Colors.blue,
      ),
    };
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      capture.photoNumber ?? capture.workLocation,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 6),
                  Text(label, style: TextStyle(color: color)),
                ],
              ),
              const SizedBox(height: 8),
              Text('${capture.workLocation} · ${capture.workContent}'),
              const SizedBox(height: 4),
              Text(
                capture.photographer,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (capture.failureReason != null) ...[
                const SizedBox(height: 8),
                Text(
                  capture.failureReason!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
