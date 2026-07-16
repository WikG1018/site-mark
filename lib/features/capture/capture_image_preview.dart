import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/platform/platform_services.dart';

/// Reusable capture image preview.
///
/// Resolves the on-disk source for [capture] in this order:
///
/// - [CaptureStatus.ready]: the rendered watermark photo when it exists,
///   otherwise the private original.
/// - [CaptureStatus.captured], [CaptureStatus.rendering],
///   [CaptureStatus.failed]: the private original when it exists.
/// - missing file: a Material placeholder with the status/error label.
///
/// When [thumbnail] is `false` (the detail surface) tapping the image opens a
/// full-screen [Dialog] with an [InteractiveViewer] (1x–4x). The async rendered
/// path is resolved with a [FutureBuilder]; [fileExists] is overridable so
/// widget tests can simulate on-disk state without touching the filesystem.
class CaptureImagePreview extends StatelessWidget {
  const CaptureImagePreview({
    super.key,
    required this.capture,
    required this.outputPaths,
    this.thumbnail = false,
    this.onOpen,
    this.fileExists,
  });

  final CaptureRecord capture;
  final CaptureOutputPaths outputPaths;
  final bool thumbnail;
  final VoidCallback? onOpen;

  /// Predicate used to verify whether a resolved path exists on disk. Defaults
  /// to [File.existsSync] in production; tests inject a fake to control which
  /// branch the widget takes.
  final bool Function(String path)? fileExists;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final bool Function(String path) exists =
        fileExists ?? (path) => File(path).existsSync();
    final originalExists = exists(capture.originalPath);

    if (capture.status == CaptureStatus.ready) {
      return FutureBuilder<String>(
        future: outputPaths.renderedPhotoPath(capture.id),
        builder: (context, snapshot) {
          final renderedPath = snapshot.data;
          if (renderedPath != null && exists(renderedPath)) {
            return _image(
              context,
              path: renderedPath,
              key: 'rendered-preview-${capture.id}',
              overlay: null,
            );
          }
          if (originalExists) {
            return _image(
              context,
              path: capture.originalPath,
              key: 'original-preview-${capture.id}',
              overlay: null,
            );
          }
          return _placeholder(context, strings, label: strings.failed);
        },
      );
    }

    // captured, rendering, failed: prefer the original when present.
    if (originalExists) {
      final overlay = _statusOverlayLabel(capture.status, strings);
      return _image(
        context,
        path: capture.originalPath,
        key: 'original-preview-${capture.id}',
        overlay: overlay,
      );
    }
    return _placeholder(
      context,
      strings,
      label: _statusOverlayLabel(capture.status, strings) ?? strings.failed,
    );
  }

  /// In-progress and failed previews overlay a status label so the user can
  /// see why the rendered image is not yet available. `ready` and missing-file
  /// previews render no overlay (the image speaks for itself, or the placeholder
  /// already carries the label).
  String? _statusOverlayLabel(CaptureStatus status, AppStrings strings) {
    switch (status) {
      case CaptureStatus.captured:
      case CaptureStatus.rendering:
        return strings.processing;
      case CaptureStatus.failed:
        return strings.failed;
      case CaptureStatus.pendingCamera:
        return strings.pendingCamera;
      case CaptureStatus.ready:
        return null;
    }
  }

  Widget _image(
    BuildContext context, {
    required String path,
    required String key,
    required String? overlay,
  }) {
    final image = Image.file(
      File(path),
      fit: thumbnail ? BoxFit.cover : BoxFit.contain,
      cacheWidth: thumbnail ? 192 : null,
      cacheHeight: thumbnail ? 192 : null,
      errorBuilder: (context, error, _) => _placeholder(
        context,
        AppStrings.of(context),
        label: AppStrings.of(context).failed,
      ),
    );

    final content = overlay == null
        ? image
        : Stack(
            fit: thumbnail ? StackFit.expand : StackFit.passthrough,
            children: [
              Positioned.fill(child: image),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  color: Colors.black54,
                  child: Text(
                    overlay,
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          );

    if (thumbnail) {
      return KeyedSubtree(key: Key(key), child: content);
    }
    return GestureDetector(
      onTap: onOpen ?? () => _openFullscreen(context, path),
      child: KeyedSubtree(key: Key(key), child: content),
    );
  }

  void _openFullscreen(BuildContext context, String path) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: true,
        pageBuilder: (context, animation, secondaryAnimation) {
          return Dialog(
            insetPadding: EdgeInsets.zero,
            child: Scaffold(
              appBar: AppBar(
                automaticallyImplyLeading: false,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              body: SafeArea(
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: Image.file(
                      File(path),
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, _) => Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          size: 64,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _placeholder(
    BuildContext context,
    AppStrings strings, {
    required String label,
  }) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.broken_image_outlined,
            size: thumbnail ? 28 : 48,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
