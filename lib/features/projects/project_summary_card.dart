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
        _ProjectThumbnail(
          key: ValueKey(id),
          captureId: id,
          outputPaths: outputPaths,
          addTrailingGap: index != captureIds.length - 1,
        ),
    ],
  );
}

class _ProjectThumbnail extends StatefulWidget {
  const _ProjectThumbnail({
    super.key,
    required this.captureId,
    required this.outputPaths,
    required this.addTrailingGap,
  });

  final String captureId;
  final CaptureOutputPaths outputPaths;
  final bool addTrailingGap;

  @override
  State<_ProjectThumbnail> createState() => _ProjectThumbnailState();
}

class _ProjectThumbnailState extends State<_ProjectThumbnail> {
  late Future<File?> _file;

  @override
  void initState() {
    super.initState();
    _file = _resolveFile();
  }

  @override
  void didUpdateWidget(covariant _ProjectThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.captureId != widget.captureId ||
        !identical(oldWidget.outputPaths, widget.outputPaths)) {
      _file = _resolveFile();
    }
  }

  Future<File?> _resolveFile() async {
    final path = await widget.outputPaths.renderedPhotoPath(widget.captureId);
    if (path.isEmpty) return null;
    final file = File(path);
    return await file.exists() ? file : null;
  }

  @override
  Widget build(BuildContext context) => Expanded(
    child: Padding(
      padding: EdgeInsetsDirectional.only(end: widget.addTrailingGap ? 6 : 0),
      child: AspectRatio(
        aspectRatio: 1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: RepaintBoundary(
            child: FutureBuilder<File?>(
              key: ObjectKey(_file),
              future: _file,
              builder: (context, snapshot) {
                final file = snapshot.data;
                if (file == null) {
                  return _ThumbnailPlaceholder(
                    key: Key(
                      'project-thumbnail-placeholder-${widget.captureId}',
                    ),
                  );
                }
                return Image.file(
                  file,
                  key: Key('project-thumbnail-${widget.captureId}'),
                  fit: BoxFit.cover,
                  cacheWidth: 192,
                  gaplessPlayback: true,
                  excludeFromSemantics: true,
                  errorBuilder: (_, _, _) => _ThumbnailPlaceholder(
                    key: Key(
                      'project-thumbnail-placeholder-${widget.captureId}',
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    ),
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
  const _ThumbnailPlaceholder({super.key});

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest);
}
