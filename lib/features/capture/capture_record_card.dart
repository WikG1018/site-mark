import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/features/capture/capture_image_preview.dart';
import 'package:sitemark/l10n/app_strings.dart';

/// Shared capture list item used by both the project detail and the global
/// all-records surfaces.
///
/// Layout: 96×96 [CaptureImagePreview] on the left, a flexible metadata column
/// in the middle, and a status icon/label pinned top-right. [showProjectName]
/// toggles the project name row (only meaningful in the global list). The card
/// stays tappable even when the preview file is missing — the preview renders a
/// placeholder instead.
class CaptureRecordCard extends ConsumerWidget {
  const CaptureRecordCard({
    super.key,
    required this.summary,
    required this.onTap,
    this.showProjectName = false,
  });

  final CaptureSummary summary;
  final VoidCallback onTap;
  final bool showProjectName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppStrings.of(context);
    final capture = summary.capture;
    final (label, icon, color) = _statusPresentation(capture.status, strings);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 96,
                height: 96,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CaptureImagePreview(
                    capture: capture,
                    outputPaths: ref.watch(captureOutputPathsProvider),
                    thumbnail: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            capture.photoNumber ?? capture.workLocation,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Icon(icon, size: 18, color: color),
                        const SizedBox(width: 4),
                        Text(label, style: TextStyle(color: color)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (showProjectName) ...[
                      Text(
                        summary.projectName,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                    ],
                    Text(
                      '${capture.workLocation} · ${capture.workContent}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      capture.photographer,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (capture.failureReason != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        capture.failureReason!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  (String, IconData, Color) _statusPresentation(
    CaptureStatus status,
    AppStrings strings,
  ) {
    return switch (status) {
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
  }
}
