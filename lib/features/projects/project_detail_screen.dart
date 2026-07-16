import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_filter.dart';
import 'package:sitemark/features/capture/capture_date_filter_bar.dart';
import 'package:sitemark/features/capture/capture_record_card.dart';
import 'package:sitemark/l10n/app_strings.dart';

class ProjectDetailScreen extends ConsumerStatefulWidget {
  const ProjectDetailScreen({super.key, required this.projectId});

  final String projectId;

  @override
  ConsumerState<ProjectDetailScreen> createState() =>
      _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends ConsumerState<ProjectDetailScreen> {
  CaptureFilter? _filter;

  CaptureFilter _filterForProject() =>
      _filter?.selectProject(widget.projectId) ??
      CaptureFilter(projectId: widget.projectId);

  @override
  Widget build(BuildContext context) {
    final database = ref.watch(databaseProvider);
    final strings = AppStrings.of(context);
    final filter = _filterForProject();
    return FutureBuilder<Project?>(
      future: database.projectById(widget.projectId),
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
              : StreamBuilder<List<CaptureSummary>>(
                  stream: database.watchCaptureSummaries(filter),
                  builder: (context, captureSnapshot) {
                    if (!captureSnapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final captures = captureSnapshot.data!;
                    return StreamBuilder<List<CaptureSummary>>(
                      stream: database.watchCaptureSummaries(
                        CaptureFilter(projectId: widget.projectId),
                      ),
                      builder: (context, projectSummarySnapshot) {
                        final allProjectSummaries =
                            projectSummarySnapshot.data ?? const [];
                        final hasAnyRecord = allProjectSummaries.isNotEmpty;
                        return CustomScrollView(
                          slivers: [
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  20,
                                  16,
                                  8,
                                ),
                                child: _ProjectHeader(project: project),
                              ),
                            ),
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  12,
                                  20,
                                  4,
                                ),
                                child: Text(
                                  strings.captureRecords,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ),
                            ),
                            if (hasAnyRecord)
                              SliverToBoxAdapter(
                                child: CaptureDateFilterBar(
                                  filter: filter,
                                  summaries: allProjectSummaries,
                                  onChanged: (next) => setState(() {
                                    _filter = next;
                                  }),
                                ),
                              ),
                            if (!hasAnyRecord)
                              SliverFillRemaining(
                                hasScrollBody: false,
                                child: Center(
                                  child: Text(
                                    strings.noCaptures,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyLarge,
                                  ),
                                ),
                              )
                            else if (captures.isEmpty)
                              SliverFillRemaining(
                                hasScrollBody: false,
                                child: Center(
                                  child: Text(
                                    strings.filteredEmpty,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyLarge,
                                  ),
                                ),
                              )
                            else
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  96,
                                ),
                                sliver: SliverList.separated(
                                  itemCount: captures.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (context, index) =>
                                      CaptureRecordCard(
                                        summary: captures[index],
                                        onTap: () => context.go(
                                          '/projects/${widget.projectId}'
                                          '/captures/${captures[index].capture.id}',
                                        ),
                                      ),
                                ),
                              ),
                          ],
                        );
                      },
                    );
                  },
                ),
          floatingActionButton: project == null
              ? null
              : FloatingActionButton.extended(
                  onPressed: () =>
                      context.go('/projects/${widget.projectId}/capture'),
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
