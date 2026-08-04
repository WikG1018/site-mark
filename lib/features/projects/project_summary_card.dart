import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sitemark/domain/project_lifecycle.dart';
import 'package:sitemark/domain/project_summary.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/shared/ui/glass_surface.dart';

class ProjectSummaryCard extends StatelessWidget {
  const ProjectSummaryCard({
    super.key,
    required this.summary,
    required this.outputPaths,
    required this.onOpen,
  });

  final ProjectSummary summary;
  final CaptureOutputPaths outputPaths;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => GlassCard(
    onTap: onOpen,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                summary.project.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right),
          ],
        ),
        const SizedBox(height: 10),
        _ProjectSummaryMetadata(summary: summary),
        if (summary.recentCaptureIds.isNotEmpty) ...[
          const SizedBox(height: 12),
          ProjectRecentThumbnails(
            captureIds: summary.recentCaptureIds,
            outputPaths: outputPaths,
          ),
        ],
      ],
    ),
  );
}

class ProjectRecentThumbnails extends StatelessWidget {
  const ProjectRecentThumbnails({
    super.key,
    required this.captureIds,
    required this.outputPaths,
  });

  final List<String> captureIds;
  final CaptureOutputPaths outputPaths;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final (index, id) in captureIds.indexed)
        Expanded(
          child: Padding(
            padding: EdgeInsetsDirectional.only(
              end: index == captureIds.length - 1 ? 0 : 6,
            ),
            child: AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: RepaintBoundary(
                  child: FutureBuilder<String>(
                    future: outputPaths.renderedPhotoPath(id),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return const _ThumbnailPlaceholder();
                      }
                      return Image.file(
                        File(snapshot.data!),
                        key: Key('project-thumbnail-$id'),
                        fit: BoxFit.cover,
                        cacheWidth: 192,
                        gaplessPlayback: true,
                        errorBuilder: (_, _, _) =>
                            const _ThumbnailPlaceholder(),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class _ProjectSummaryMetadata extends StatelessWidget {
  const _ProjectSummaryMetadata({required this.summary});

  final ProjectSummary summary;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final project = summary.project;
    final lastCaptureLabel = summary.lastCaptureAt == null
        ? strings.noCaptureRecordsYet
        : strings.lastCaptureAtLabel(
            DateFormat.yMMMd(
              Localizations.localeOf(context).toString(),
            ).add_Hm().format(summary.lastCaptureAt!),
          );
    final statusLabel = switch (project.lifecycleStatus) {
      ProjectLifecycleStatus.active => strings.projectStatusActive,
      ProjectLifecycleStatus.completed => strings.projectStatusCompleted,
      ProjectLifecycleStatus.archived => strings.projectStatusArchived,
    };

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        _MetaChip(
          key: Key('project-status-badge-${project.lifecycleStatus.name}'),
          label: statusLabel,
        ),
        if (project.isPinned) _MetaChip(label: strings.projectPinnedBadge),
        _MetaChip(label: strings.projectPhotoCount(summary.captureCount)),
        _MetaChip(label: lastCaptureLabel),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}

class _ThumbnailPlaceholder extends StatelessWidget {
  const _ThumbnailPlaceholder();

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest);
}
