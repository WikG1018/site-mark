import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/features/capture/capture_fullscreen_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/motion.dart';
import 'package:sitemark/platform/platform_services.dart';

/// Selects which on-disk source [CaptureImagePreview] renders.
///
/// - [CapturePreviewSource.bestAvailable]: keep the historical fallback
///   behaviour (rendered photo for `ready` rows when present, otherwise the
///   private original, otherwise a status placeholder).
/// - [CapturePreviewSource.watermarked]: resolve only the rendered watermark
///   photo via [CaptureOutputPaths.renderedPhotoPath]. When the file is missing
///   the preview shows a "watermarked not yet available" placeholder instead of
///   silently falling back to the original.
/// - [CapturePreviewSource.original]: resolve only the private original. When
///   the original has been cleared ([CaptureRecord.originalDeletedAt] non-null)
///   or is unexpectedly missing on disk, the preview shows the original-state
///   placeholder. It must never silently render the watermarked photo under the
///   "Original" tab.
enum CapturePreviewSource { bestAvailable, watermarked, original }

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
/// When [thumbnail] is `false` (the detail surface) tapping the image pushes
/// the full-screen [CaptureFullscreenScreen] route (pinch 1x–4x, double-tap
/// zoom, drag-down to dismiss). The async rendered path is resolved with a
/// [FutureBuilder]; [fileExists] is overridable so widget tests can simulate
/// on-disk state without touching the filesystem.
///
/// File existence is checked asynchronously via [File.exists] and the resolved
/// [_PreviewResolution] is cached per `State` instance, refreshed only when the
/// relevant inputs change. Decoded frames fade in via [Image.frameBuilder],
/// and same-slot content swaps (status overlay to final photo, placeholder to
/// image) cross-fade through an [AnimatedSwitcher] driven by the keyed subtrees
/// below.
///
/// Pass an explicit [source] to render only the watermarked or original photo
/// (used by the detail screen's segmented control). The default
/// [CapturePreviewSource.bestAvailable] keeps the historical fallback behaviour
/// used by list thumbnails.
class CaptureImagePreview extends StatefulWidget {
  const CaptureImagePreview({
    super.key,
    required this.capture,
    required this.outputPaths,
    this.thumbnail = false,
    this.onOpen,
    this.fileExists,
    this.source = CapturePreviewSource.bestAvailable,
  });

  final CaptureRecord capture;
  final CaptureOutputPaths outputPaths;
  final bool thumbnail;
  final VoidCallback? onOpen;

  /// Predicate used to verify whether a resolved path exists on disk. Defaults
  /// to the asynchronous [File.exists] in production; tests can inject either
  /// a synchronous or asynchronous fake to control which branch the widget
  /// takes.
  final FutureOr<bool> Function(String path)? fileExists;

  /// Selects which on-disk source to render. See [CapturePreviewSource].
  final CapturePreviewSource source;

  @override
  State<CaptureImagePreview> createState() => _CaptureImagePreviewState();
}

class _CaptureImagePreviewState extends State<CaptureImagePreview> {
  late Future<_PreviewResolution> _resolution;

  @override
  void initState() {
    super.initState();
    _resolution = _resolve();
  }

  @override
  void didUpdateWidget(covariant CaptureImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_resolutionInputsChanged(oldWidget)) {
      _resolution = _resolve();
    }
  }

  bool _resolutionInputsChanged(CaptureImagePreview previous) {
    final oldCapture = previous.capture;
    final capture = widget.capture;
    return oldCapture.id != capture.id ||
        oldCapture.originalPath != capture.originalPath ||
        oldCapture.status != capture.status ||
        oldCapture.originalDeletedAt != capture.originalDeletedAt ||
        previous.source != widget.source ||
        previous.outputPaths != widget.outputPaths ||
        previous.fileExists != widget.fileExists;
  }

  Future<bool> _exists(String path) async {
    return await (widget.fileExists ?? _defaultFileExists)(path);
  }

  Future<bool> _defaultFileExists(String path) => File(path).exists();

  Future<bool> _existsOrFalse(String path) async {
    try {
      return await _exists(path);
    } catch (_) {
      return false;
    }
  }

  Future<_PreviewResolution> _resolve() async {
    final capture = widget.capture;
    switch (widget.source) {
      case CapturePreviewSource.watermarked:
        try {
          final renderedPath = await widget.outputPaths.renderedPhotoPath(
            capture.id,
          );
          return await _existsOrFalse(renderedPath)
              ? _PreviewResolution.image(renderedPath, status: null)
              : const _PreviewResolution.watermarkedUnavailable();
        } catch (_) {
          return const _PreviewResolution.watermarkedUnavailable();
        }
      case CapturePreviewSource.original:
        if (capture.originalDeletedAt != null) {
          return const _PreviewResolution.originalCleared();
        }
        return await _existsOrFalse(capture.originalPath)
            ? _PreviewResolution.image(capture.originalPath, status: null)
            : const _PreviewResolution.originalMissing();
      case CapturePreviewSource.bestAvailable:
        final originalExists = _existsOrFalse(capture.originalPath);
        if (capture.status == CaptureStatus.ready) {
          try {
            final renderedPath = await widget.outputPaths.renderedPhotoPath(
              capture.id,
            );
            if (await _existsOrFalse(renderedPath)) {
              return _PreviewResolution.image(renderedPath, status: null);
            }
          } catch (_) {
            // A rendered result is optional for the best-available source.
          }
        }
        if (await originalExists) {
          return _PreviewResolution.image(
            capture.originalPath,
            status: capture.status,
          );
        }
        return _PreviewResolution.statusPlaceholder(capture.status);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return FutureBuilder<_PreviewResolution>(
      future: _resolution,
      builder: (context, snapshot) {
        final resolution = snapshot.data;
        if (snapshot.connectionState != ConnectionState.done ||
            resolution == null) {
          return AnimatedSwitcher(
            duration: AppMotion.medium2,
            child: _placeholder(
              context,
              strings,
              label: _loadingLabel(strings),
            ),
          );
        }
        return AnimatedSwitcher(
          duration: AppMotion.medium2,
          child: switch (resolution.kind) {
            _PreviewResolutionKind.image => _image(
              context,
              path: resolution.path!,
              key: resolution.path == widget.capture.originalPath
                  ? 'original-preview-${widget.capture.id}'
                  : 'rendered-preview-${widget.capture.id}',
              overlay: resolution.status == null
                  ? null
                  : _statusOverlayLabel(resolution.status!, strings),
            ),
            _PreviewResolutionKind.watermarkedUnavailable => _placeholder(
              context,
              strings,
              label: strings.watermarkedUnavailable,
            ),
            _PreviewResolutionKind.originalCleared => _placeholder(
              context,
              strings,
              label: strings.originalCleared,
            ),
            _PreviewResolutionKind.originalMissing => _placeholder(
              context,
              strings,
              label: strings.originalMissing,
            ),
            _PreviewResolutionKind.statusPlaceholder => _placeholder(
              context,
              strings,
              label:
                  _statusOverlayLabel(widget.capture.status, strings) ??
                  strings.failed,
            ),
          },
        );
      },
    );
  }

  /// Label shown while the existence check is in flight. Mirrors the most
  /// likely placeholder the resolution will land on so the cross-fade does not
  /// flash a different label first.
  String _loadingLabel(AppStrings strings) {
    return switch (widget.source) {
      CapturePreviewSource.watermarked => strings.watermarkedUnavailable,
      CapturePreviewSource.original =>
        widget.capture.originalDeletedAt != null
            ? strings.originalCleared
            : strings.originalMissing,
      CapturePreviewSource.bestAvailable =>
        _statusOverlayLabel(widget.capture.status, strings) == null
            ? strings.failed
            : _statusOverlayLabel(widget.capture.status, strings)!,
    };
  }

  /// In-progress and failed previews overlay a status label so the user can
  /// see why the rendered image is not yet available. `ready` and missing-file
  /// previews render no overlay (the image speaks for itself, or the placeholder
  /// already carries the label).
  String? _statusOverlayLabel(CaptureStatus status, AppStrings strings) {
    switch (status) {
      case CaptureStatus.captured:
        return strings.waitingForProcessing;
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
      fit: widget.thumbnail ? BoxFit.cover : BoxFit.contain,
      cacheWidth: widget.thumbnail ? 192 : _detailCacheWidth(context),
      cacheHeight: widget.thumbnail ? 192 : null,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: AppMotion.medium2,
          curve: AppMotion.standard,
          child: child,
        );
      },
      errorBuilder: (context, error, _) => _placeholder(
        context,
        AppStrings.of(context),
        label: AppStrings.of(context).failed,
      ),
    );

    final content = overlay == null
        ? image
        : Stack(
            fit: widget.thumbnail ? StackFit.expand : StackFit.passthrough,
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

    if (widget.thumbnail) {
      return KeyedSubtree(key: Key(key), child: content);
    }
    return GestureDetector(
      onTap: widget.onOpen ?? () => _openFullscreen(context, path),
      child: KeyedSubtree(key: Key(key), child: content),
    );
  }

  /// Detail-surface decode width cap, derived from the available horizontal
  /// space and the device pixel ratio. The full-screen viewer does NOT use
  /// this cap — it keeps the original resolution so 4x zoom stays sharp.
  int _detailCacheWidth(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final physicalWidth = width * MediaQuery.devicePixelRatioOf(context);
    if (!physicalWidth.isFinite || physicalWidth <= 0) {
      return 1;
    }
    return physicalWidth.ceil().clamp(1, 2048);
  }

  void _openFullscreen(BuildContext context, String path) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: AppMotion.long2,
        reverseTransitionDuration: AppMotion.medium4,
        pageBuilder: (context, animation, secondaryAnimation) =>
            CaptureFullscreenScreen(path: path),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: AppMotion.emphasizedDecelerate,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
              child: child,
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
            size: widget.thumbnail ? 28 : 48,
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

enum _PreviewResolutionKind {
  image,
  watermarkedUnavailable,
  originalCleared,
  originalMissing,
  statusPlaceholder,
}

class _PreviewResolution {
  const _PreviewResolution.image(this.path, {required this.status})
    : kind = _PreviewResolutionKind.image;
  const _PreviewResolution.watermarkedUnavailable()
    : kind = _PreviewResolutionKind.watermarkedUnavailable,
      path = null,
      status = null;
  const _PreviewResolution.originalCleared()
    : kind = _PreviewResolutionKind.originalCleared,
      path = null,
      status = null;
  const _PreviewResolution.originalMissing()
    : kind = _PreviewResolutionKind.originalMissing,
      path = null,
      status = null;
  const _PreviewResolution.statusPlaceholder(this.status)
    : kind = _PreviewResolutionKind.statusPlaceholder,
      path = null;

  final _PreviewResolutionKind kind;
  final String? path;
  final CaptureStatus? status;
}
