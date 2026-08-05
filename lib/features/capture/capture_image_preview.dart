import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/data/capture_query_repository.dart';
import 'package:sitemark/domain/capture_list_query.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/features/capture/capture_fullscreen_sequence.dart';
import 'package:sitemark/features/capture/capture_fullscreen_screen.dart';
import 'package:sitemark/features/capture/capture_photo_hero.dart';
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
    this.navigationContext,
    this.querySource,
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

  final CaptureNavigationContext? navigationContext;
  final CaptureQuerySource? querySource;

  @override
  State<CaptureImagePreview> createState() => _CaptureImagePreviewState();
}

class _CaptureImagePreviewState extends State<CaptureImagePreview> {
  late Future<_PreviewResolution> _resolution;
  _PreviewResolution? _handoffResolution;
  int _resolutionGeneration = 0;

  @override
  void initState() {
    super.initState();
    _handoffResolution = _handoffForPath(widget.initialImagePath);
    _resolution = _startResolution();
  }

  @override
  void didUpdateWidget(covariant CaptureImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final captureChanged = oldWidget.capture.id != widget.capture.id;
    final handoffChanged =
        oldWidget.initialImagePath != widget.initialImagePath;
    if (captureChanged) {
      _handoffResolution = _handoffForPath(widget.initialImagePath);
    } else if (handoffChanged && widget.initialImagePath != null) {
      _handoffResolution = _handoffForPath(widget.initialImagePath);
    }
    if (widget.capture.originalDeletedAt != null &&
        _handoffResolution?.path == widget.capture.originalPath) {
      _handoffResolution = null;
    }
    if (_resolutionInputsChanged(oldWidget) || handoffChanged) {
      _resolution = _startResolution();
    }
  }

  _PreviewResolution? _handoffForPath(String? path) {
    if (path == null ||
        (widget.capture.originalDeletedAt != null &&
            path == widget.capture.originalPath)) {
      return null;
    }
    return _PreviewResolution.image(path, status: null);
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
    return _resolveCapture(widget.capture, widget.source);
  }

  Future<_PreviewResolution> _resolveCapture(
    CaptureRecord capture,
    CapturePreviewSource source,
  ) async {
    switch (source) {
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
        final originalExists = capture.originalDeletedAt == null
            ? _existsOrFalse(capture.originalPath)
            : Future<bool>.value(false);
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

  Future<_PreviewResolution> _startResolution() {
    final generation = ++_resolutionGeneration;
    return _resolveAndReport(generation);
  }

  Future<_PreviewResolution> _resolveAndReport(int generation) async {
    final captureId = widget.capture.id;
    final resolution = await _resolve();
    if (mounted &&
        generation == _resolutionGeneration &&
        widget.capture.id == captureId) {
      if (resolution.kind == _PreviewResolutionKind.image) {
        _handoffResolution = resolution;
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
      builder: (context, snapshot) {
        final resolved = snapshot.data;
        final resolution = switch (snapshot.connectionState) {
          ConnectionState.done
              when resolved?.kind == _PreviewResolutionKind.image =>
            resolved,
          ConnectionState.done => _handoffResolution ?? resolved,
          _ => _handoffResolution,
        };
        if (resolution == null) {
          return AnimatedSwitcher(
            duration: widget.heroDestination
                ? Duration.zero
                : AppMotion.durationOf(context, AppMotion.short4),
            child: _placeholder(
              context,
              strings,
              label: _loadingLabel(strings),
            ),
          );
        }
        return AnimatedSwitcher(
          duration: widget.heroDestination
              ? Duration.zero
              : AppMotion.durationOf(context, AppMotion.short4),
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
        final heroEndpoint =
            widget.heroDestination ||
            (widget.thumbnail && widget.heroTag != null);
        final cacheWidth = heroEndpoint
            ? CapturePhotoHero.flightCacheWidth(context)
            : widget.thumbnail
            ? 192
            : _detailCacheWidth(context, constraints);
        final provider = ResizeImage.resizeIfNeeded(
          cacheWidth,
          widget.thumbnail && !heroEndpoint ? 192 : null,
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
                    duration: AppMotion.durationOf(context, AppMotion.short4),
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
          key: Key('capture-image-open-${widget.capture.id}'),
          behavior: HitTestBehavior.opaque,
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
    final source = widget.source;
    final currentCapture = widget.capture;
    final currentPhoto = CaptureFullscreenPhoto(
      id: currentCapture.id,
      initialPath: path,
      previewImage: previewImage,
      resolvePath: () async => path,
    );
    final navigationContext = widget.navigationContext;
    final querySource = widget.querySource;
    final CaptureFullscreenScreen page;
    if (navigationContext == null || querySource == null) {
      page = CaptureFullscreenScreen(photos: [currentPhoto]);
    } else {
      final cursors = <String, CapturePageCursor>{
        currentCapture.id: navigationContext.cursor,
      };
      final sequence = CaptureFullscreenSequence(
        current: currentPhoto,
        loader: (direction, anchorId) async {
          final cursor = cursors[anchorId];
          if (cursor == null) return const [];
          final summaries = await querySource.loadAdjacent(
            navigationContext.query,
            cursor,
            newer: direction == CaptureFullscreenDirection.newer,
            limit: 10,
          );
          final pendingPhotos = <Future<CaptureFullscreenPhoto>>[];
          for (final summary in summaries) {
            final capture = summary.capture;
            cursors[capture.id] = _cursorFor(capture);
            pendingPhotos.add(() async {
              final resolution = await _resolveCapture(capture, source);
              final path = resolution.kind == _PreviewResolutionKind.image
                  ? resolution.path
                  : null;
              return CaptureFullscreenPhoto(
                id: capture.id,
                includeInSequence: path != null,
                initialPath: path,
                resolvePath: () async => path,
              );
            }());
          }
          return Future.wait(pendingPhotos);
        },
      );
      page = CaptureFullscreenScreen.sequence(sequence: sequence);
    }

    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: AppMotion.durationOf(context, AppMotion.long2),
        reverseTransitionDuration: AppMotion.durationOf(
          context,
          AppMotion.medium4,
        ),
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          if (MediaQuery.disableAnimationsOf(context)) return child;
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

  CapturePageCursor _cursorFor(CaptureRecord capture) =>
      (sortTime: capture.capturedAt ?? capture.createdAt, id: capture.id);

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
