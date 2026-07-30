import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/features/capture/capture_photo_hero.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/features/capture/capture_fullscreen_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/motion.dart';
import 'package:sitemark/platform/platform_services.dart';

enum CapturePreviewSource { bestAvailable, watermarked, original }

class CaptureImagePreview extends StatefulWidget {
  const CaptureImagePreview({
    super.key,
    required this.capture,
    required this.outputPaths,
    this.thumbnail = false,
    this.onOpen,
    this.fileExists,
    this.source = CapturePreviewSource.bestAvailable,
    this.heroTag,
    this.heroDestination = false,
    this.initialImagePath,
    this.onImageResolved,
    this.siblingPaths,
    this.siblingIndex,
  });

  final CaptureRecord capture;
  final CaptureOutputPaths outputPaths;
  final bool thumbnail;
  final VoidCallback? onOpen;
  final FutureOr<bool> Function(String path)? fileExists;
  final CapturePreviewSource source;
  final String? heroTag;
  final bool heroDestination;
  final String? initialImagePath;
  final ValueChanged<String>? onImageResolved;

  /// Absolute image paths of adjacent captures. When non-null and non-empty,
  /// the fullscreen viewer will allow left/right swipe between them.
  final List<String>? siblingPaths;

  /// Index of the current capture inside [siblingPaths].
  final int? siblingIndex;

  @override
  State<CaptureImagePreview> createState() => _CaptureImagePreviewState();
}

class _CaptureImagePreviewState extends State<CaptureImagePreview> {
  late Future<_PreviewResolution> _resolution;
  _PreviewResolution? _initialResolution;
  bool _useInitialWhileWaiting = false;

  @override
  void initState() {
    super.initState();
    final initialImagePath = widget.initialImagePath;
    if (initialImagePath != null) {
      _initialResolution = _PreviewResolution.image(
        initialImagePath,
        status: null,
      );
      _useInitialWhileWaiting = true;
    }
    _resolution = _resolveAndReport();
  }

  @override
  void didUpdateWidget(covariant CaptureImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_resolutionInputsChanged(oldWidget)) {
      _useInitialWhileWaiting = false;
      _resolution = _resolveAndReport();
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
          } catch (_) {}
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

  Future<_PreviewResolution> _resolveAndReport() async {
    final captureId = widget.capture.id;
    final resolution = await _resolve();
    if (mounted && widget.capture.id == captureId) {
      _useInitialWhileWaiting = false;
      if (resolution.kind == _PreviewResolutionKind.image) {
        widget.onImageResolved?.call(resolution.path!);
      }
    }
    return resolution;
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final preview = FutureBuilder<_PreviewResolution>(
      future: _resolution,
      initialData: _initialResolution,
      builder: (context, snapshot) {
        final resolution = snapshot.data;
        if (resolution == null ||
            (snapshot.connectionState != ConnectionState.done &&
                !_useInitialWhileWaiting)) {
          return AnimatedSwitcher(
            duration: widget.heroDestination
                ? Duration.zero
                : AppMotion.medium2,
            child: _placeholder(
              context,
              strings,
              label: _loadingLabel(strings),
            ),
          );
        }
        return AnimatedSwitcher(
          duration: widget.heroDestination ? Duration.zero : AppMotion.medium2,
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
    if (widget.heroTag != null && !widget.thumbnail) {
      return Hero(tag: widget.heroTag!, child: preview);
    }
    return preview;
  }

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
    return LayoutBuilder(
      builder: (context, constraints) {
        final cacheWidth = widget.thumbnail
            ? 192
            : widget.heroDestination
            ? CapturePhotoHero.flightCacheWidth(context)
            : _detailCacheWidth(context, constraints);
        final provider = ResizeImage.resizeIfNeeded(
          cacheWidth,
          widget.thumbnail ? 192 : null,
          FileImage(File(path)),
        );
        final image = Image(
          image: provider,
          fit: widget.thumbnail ? BoxFit.cover : BoxFit.contain,
          gaplessPlayback: widget.heroTag != null || widget.heroDestination,
          frameBuilder:
              widget.heroDestination ||
                  (widget.thumbnail && widget.heroTag != null)
              ? null
              : (context, child, frame, wasSynchronouslyLoaded) {
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
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              );

        Widget preview = KeyedSubtree(key: Key(key), child: content);
        if (widget.heroTag != null && widget.thumbnail) {
          preview = CapturePhotoHero(
            tag: widget.heroTag!,
            path: path,
            child: preview,
          );
        }
        if (widget.thumbnail) return preview;
        return GestureDetector(
          onTap:
              widget.onOpen ??
              () => _openFullscreen(context, path, previewImage: provider),
          child: preview,
        );
      },
    );
  }

  int _detailCacheWidth(BuildContext context, BoxConstraints constraints) {
    final width = constraints.maxWidth.isFinite && constraints.maxWidth > 0
        ? constraints.maxWidth
        : MediaQuery.sizeOf(context).width;
    final physicalWidth = width * MediaQuery.devicePixelRatioOf(context);
    if (!physicalWidth.isFinite || physicalWidth <= 0) {
      return 1;
    }
    return physicalWidth.ceil().clamp(1, 2048);
  }

  void _openFullscreen(
    BuildContext context,
    String path, {
    required ImageProvider<Object> previewImage,
  }) {
    final siblings = widget.siblingPaths;
    final index = widget.siblingIndex;
    final Widget page;
    if (siblings != null &&
        siblings.isNotEmpty &&
        index != null &&
        index >= 0 &&
        index < siblings.length) {
      page = CaptureFullscreenScreen(
        paths: siblings,
        initialIndex: index,
        previewImages: {path: previewImage},
      );
    } else {
      page = CaptureFullscreenScreen.single(
        path: path,
        previewImage: previewImage,
      );
    }

    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: AppMotion.long2,
        reverseTransitionDuration: AppMotion.medium4,
        pageBuilder: (context, animation, secondaryAnimation) => page,
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
