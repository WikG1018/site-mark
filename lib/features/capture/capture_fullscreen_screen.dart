import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sitemark/features/capture/capture_fullscreen_sequence.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/motion.dart';
import 'package:sitemark/platform/memory_pressure_coordinator.dart';

export 'package:sitemark/features/capture/capture_fullscreen_sequence.dart'
    show CaptureFullscreenPhoto;

/// Full-screen immersive photo viewer pushed from the detail image preview.
///
/// Supports a list of image paths so the user can swipe left/right between
/// adjacent captures. When only a single path is supplied the behaviour is
/// identical to the previous single-image viewer.
///
/// The page sits on a pure black [Scaffold] and enters
/// [SystemUiMode.immersiveSticky] while visible (restoring
/// [SystemUiMode.edgeToEdge] on dispose). Gestures:
///
/// - single tap toggles the transparent chrome [AppBar];
/// - double tap animates the [TransformationController] between 1x and 2x;
/// - while at 1x, a vertical drag moves the photo and can dismiss the route;
/// - while zoomed past 1x the [InteractiveViewer] pans normally;
/// - horizontal swipe (PageView) is only active when the current page is at 1x.
class CaptureFullscreenScreen extends ConsumerStatefulWidget {
  // The bounds assertion reads the runtime list length, so this constructor
  // cannot be const even though the widget itself is immutable.
  // ignore: prefer_const_constructors_in_immutables
  CaptureFullscreenScreen({
    super.key,
    required List<CaptureFullscreenPhoto> photos,
    this.initialIndex = 0,
  }) : _photos = photos,
       sequence = null,
       assert(photos.isNotEmpty, 'photos must not be empty'),
       assert(initialIndex >= 0 && initialIndex < photos.length);

  const CaptureFullscreenScreen.sequence({super.key, required this.sequence})
    : _photos = const [],
      initialIndex = 0;

  final List<CaptureFullscreenPhoto> _photos;
  final CaptureFullscreenSequence? sequence;

  List<CaptureFullscreenPhoto> get photos => sequence?.photos ?? _photos;

  /// Index of the photo that should be shown first.
  final int initialIndex;

  factory CaptureFullscreenScreen.fromPaths({
    Key? key,
    required List<String> paths,
    int initialIndex = 0,
  }) {
    return CaptureFullscreenScreen(
      key: key,
      photos: paths
          .map((path) => CaptureFullscreenPhoto.resolved(path: path))
          .toList(growable: false),
      initialIndex: initialIndex,
    );
  }

  /// Convenience constructor kept for existing single-image call sites.
  factory CaptureFullscreenScreen.single({
    Key? key,
    required String path,
    ImageProvider<Object>? previewImage,
  }) {
    return CaptureFullscreenScreen(
      key: key,
      photos: [
        CaptureFullscreenPhoto.resolved(path: path, previewImage: previewImage),
      ],
      initialIndex: 0,
    );
  }

  @override
  ConsumerState<CaptureFullscreenScreen> createState() =>
      _CaptureFullscreenScreenState();
}

class _CaptureFullscreenScreenState
    extends ConsumerState<CaptureFullscreenScreen>
    with TickerProviderStateMixin {
  static const double _dismissThreshold = 120;
  static const double _dismissVelocity = 700;
  static const double _dragShrinkFactor = 600;
  static const double _minDragScale = 0.7;
  static const int _prefetchEdgeDistance = 2;

  late final PageController _pageController;
  final Map<String, TransformationController> _transformationControllers = {};
  final Map<String, VoidCallback> _transformationListeners = {};
  final Map<String, Future<String?>> _pathFutures = {};
  late final AnimationController _scaleController = AnimationController(
    vsync: this,
    duration: AppMotion.medium4,
  );
  late final AnimationController _dragController = AnimationController(
    vsync: this,
    duration: AppMotion.medium2,
  );
  Animation<Matrix4>? _scaleAnimation;
  Animation<double>? _dragAnimation;

  Offset? _doubleTapPosition;
  double _dragOffset = 0;
  bool _zoomed = false;
  bool _chromeVisible = false;
  int _currentPage = 0;
  String? _currentPhotoId;
  String? _scaleTargetPhotoId;
  late List<CaptureFullscreenPhoto> _photos;
  VoidCallback? _releaseDetach;

  TransformationController _controllerFor(String photoId) {
    return _transformationControllers.putIfAbsent(photoId, () {
      final controller = TransformationController();
      void listener() => _onTransformChanged(photoId);
      _transformationListeners[photoId] = listener;
      controller.addListener(listener);
      return controller;
    });
  }

  @override
  void initState() {
    super.initState();
    _photos = List.of(widget.photos);
    _currentPage = widget.initialIndex;
    _currentPhotoId = _photos[widget.initialIndex].id;
    _pageController = PageController(initialPage: widget.initialIndex);
    widget.sequence?.addListener(_onSequenceChanged);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _scaleController.addListener(() {
      final animation = _scaleAnimation;
      final targetPhotoId = _scaleTargetPhotoId;
      if (animation != null && targetPhotoId != null) {
        _controllerFor(targetPhotoId).value = animation.value;
      }
    });
    _dragController.addListener(() {
      final animation = _dragAnimation;
      if (animation != null) setState(() => _dragOffset = animation.value);
    });

    final controller = ref.read(memoryPressureControllerProvider);
    _releaseDetach = controller.attachRelease(() {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route?.isCurrent ?? false) {
        Navigator.of(context).maybePop();
      }
    });

    if (widget.sequence != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeLoadAdjacent(_currentPage);
      });
    }
  }

  @override
  void didUpdateWidget(covariant CaptureFullscreenScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sequence == widget.sequence) return;
    oldWidget.sequence?.removeListener(_onSequenceChanged);
    oldWidget.sequence?.dispose();
    widget.sequence?.addListener(_onSequenceChanged);
    _scaleController.stop();
    _scaleAnimation = null;
    _scaleTargetPhotoId = null;
    _photos = List<CaptureFullscreenPhoto>.of(widget.photos);
    _currentPage = widget.initialIndex;
    _currentPhotoId = _photos[widget.initialIndex].id;
    _zoomed = false;
    _dragOffset = 0;
    if (_pageController.hasClients) {
      _pageController.jumpToPage(widget.initialIndex);
    }
    if (widget.sequence != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeLoadAdjacent(_currentPage);
      });
    }
  }

  @override
  void dispose() {
    _releaseDetach?.call();
    widget.sequence?.removeListener(_onSequenceChanged);
    widget.sequence?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _scaleController.dispose();
    _dragController.dispose();
    _pageController.dispose();
    _disposePhotoControllers();
    super.dispose();
  }

  void _disposePhotoControllers() {
    for (final entry in _transformationControllers.entries) {
      final listener = _transformationListeners[entry.key];
      if (listener != null) entry.value.removeListener(listener);
      entry.value.dispose();
    }
    _transformationControllers.clear();
    _transformationListeners.clear();
  }

  void _onSequenceChanged() {
    if (!mounted) return;
    final sequence = widget.sequence;
    if (sequence == null) return;
    final nextPhotos = List<CaptureFullscreenPhoto>.of(sequence.photos);
    final oldFirstId = _photos.first.id;
    final prependCount = nextPhotos.indexWhere(
      (photo) => photo.id == oldFirstId,
    );
    final currentPhotoId = _currentPhotoId;
    final nextCurrentPage = currentPhotoId == null
        ? _currentPage
        : nextPhotos.indexWhere((photo) => photo.id == currentPhotoId);
    final hasPrepend = prependCount > 0;
    final canCorrectPixels = hasPrepend && _pageController.hasClients;
    final correctedPixels = canCorrectPixels
        ? _pageController.position.pixels +
              prependCount * _pageController.position.viewportDimension
        : null;

    // Replace the backing list and correct pixels synchronously before the
    // next build. This keeps a fractional swipe on the exact same visible
    // pixels and avoids building the old index with a newly prepended photo.
    _photos = nextPhotos;
    if (correctedPixels != null) {
      _pageController.position.correctPixels(correctedPixels);
    }
    setState(() {
      if (nextCurrentPage >= 0) _currentPage = nextCurrentPage;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeLoadAdjacent(_currentPage);
    });
  }

  void _maybeLoadAdjacent(int index) {
    final sequence = widget.sequence;
    if (sequence == null || _photos.isEmpty) return;
    if (index <= _prefetchEdgeDistance) {
      unawaited(sequence.loadNewer());
    }
    if (index >= _photos.length - 1 - _prefetchEdgeDistance) {
      unawaited(sequence.loadOlder());
    }
  }

  void _onPageChanged(int index) {
    if (index < 0 || index >= _photos.length) return;
    _scaleController.stop();
    _scaleAnimation = null;
    _scaleTargetPhotoId = null;
    final photoId = _photos[index].id;
    final zoomed = _controllerFor(photoId).value.getMaxScaleOnAxis() > 1.01;
    widget.sequence?.select(photoId);
    setState(() {
      _currentPage = index;
      _currentPhotoId = photoId;
      _zoomed = zoomed;
      _dragOffset = 0;
    });
    _maybeLoadAdjacent(index);
  }

  void _onTransformChanged(String photoId) {
    if (photoId != _currentPhotoId) return;
    final zoomed = _controllerFor(photoId).value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  void _toggleChrome() {
    setState(() => _chromeVisible = !_chromeVisible);
    if (_chromeVisible) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  void _handleDoubleTap() {
    final targetPhotoId = _currentPhotoId;
    if (targetPhotoId == null) return;
    final current = _controllerFor(targetPhotoId).value;
    final Matrix4 end;
    if (current.getMaxScaleOnAxis() > 1.01) {
      end = Matrix4.identity();
    } else {
      final size = context.size;
      final focal =
          _doubleTapPosition ??
          (size == null ? Offset.zero : size.center(Offset.zero));
      end = Matrix4.identity()
        ..translateByDouble(focal.dx, focal.dy, 0, 1)
        ..scaleByDouble(2.0, 2.0, 2.0, 1)
        ..translateByDouble(-focal.dx, -focal.dy, 0, 1);
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _controllerFor(targetPhotoId).value = end;
      return;
    }
    _scaleAnimation = Matrix4Tween(begin: current, end: end).animate(
      CurvedAnimation(
        parent: _scaleController,
        curve: AppMotion.emphasizedDecelerate,
      ),
    );
    _scaleTargetPhotoId = targetPhotoId;
    _scaleController.forward(from: 0);
  }

  void _onVerticalDragStart(DragStartDetails details) {
    _dragController.stop();
    _dragAnimation = null;
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    setState(() => _dragOffset += details.delta.dy);
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (_dragOffset.abs() > _dismissThreshold ||
        velocity.abs() > _dismissVelocity) {
      Navigator.of(context).pop();
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() => _dragOffset = 0);
      return;
    }
    _dragAnimation = Tween<double>(begin: _dragOffset, end: 0).animate(
      CurvedAnimation(
        parent: _dragController,
        curve: AppMotion.emphasizedDecelerate,
      ),
    );
    _dragController.forward(from: 0);
  }

  bool get _showNewerRetry {
    final sequence = widget.sequence;
    return sequence != null &&
        sequence.newerError != null &&
        _currentPage <= _prefetchEdgeDistance;
  }

  bool get _showOlderRetry {
    final sequence = widget.sequence;
    return sequence != null &&
        sequence.olderError != null &&
        _currentPage >= _photos.length - 1 - _prefetchEdgeDistance;
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final dragScale = (1 - _dragOffset.abs() / _dragShrinkFactor).clamp(
      _minDragScale,
      1.0,
    );
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: _photos.length,
            onPageChanged: _onPageChanged,
            // Only allow horizontal swipe when not zoomed.
            physics: _zoomed
                ? const NeverScrollableScrollPhysics()
                : const PageScrollPhysics(),
            itemBuilder: (context, index) {
              final photo = _photos[index];
              final preview = photo.previewImage;
              final transformController = _controllerFor(photo.id);

              return KeyedSubtree(
                key: Key('fullscreen-photo-id-${photo.id}'),
                child: GestureDetector(
                  key: Key('fullscreen-photo-$index'),
                  onTap: _toggleChrome,
                  onDoubleTapDown: (details) =>
                      _doubleTapPosition = details.localPosition,
                  onDoubleTap: index == _currentPage ? _handleDoubleTap : null,
                  onVerticalDragStart: (!_zoomed && index == _currentPage)
                      ? _onVerticalDragStart
                      : null,
                  onVerticalDragUpdate: (!_zoomed && index == _currentPage)
                      ? _onVerticalDragUpdate
                      : null,
                  onVerticalDragEnd: (!_zoomed && index == _currentPage)
                      ? _onVerticalDragEnd
                      : null,
                  child: Transform.translate(
                    offset: index == _currentPage
                        ? Offset(0, _dragOffset)
                        : Offset.zero,
                    child: Transform.scale(
                      scale: index == _currentPage ? dragScale : 1.0,
                      child: InteractiveViewer(
                        transformationController: transformController,
                        panEnabled: _zoomed && index == _currentPage,
                        minScale: 1,
                        maxScale: 4,
                        child: Center(
                          child: Semantics(
                            label: strings.fullscreenPhotoSemantics,
                            liveRegion: index == _currentPage,
                            child: FutureBuilder<String?>(
                              future: _pathFutures.putIfAbsent(
                                photo.id,
                                photo.resolvePath,
                              ),
                              initialData: photo.initialPath,
                              builder: (context, snapshot) {
                                final path = snapshot.data;
                                return Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    if (preview != null)
                                      Image(
                                        image: preview,
                                        fit: BoxFit.contain,
                                        gaplessPlayback: true,
                                      ),
                                    if (path != null)
                                      Image.file(
                                        File(path),
                                        fit: BoxFit.contain,
                                        gaplessPlayback: true,
                                        frameBuilder:
                                            (
                                              context,
                                              child,
                                              frame,
                                              wasSynchronouslyLoaded,
                                            ) {
                                              if (wasSynchronouslyLoaded) {
                                                return child;
                                              }
                                              return AnimatedOpacity(
                                                opacity: frame == null ? 0 : 1,
                                                duration: AppMotion.durationOf(
                                                  context,
                                                  AppMotion.short4,
                                                ),
                                                curve: AppMotion.standard,
                                                child: child,
                                              );
                                            },
                                        errorBuilder: (context, error, _) =>
                                            preview != null
                                            ? const SizedBox.shrink()
                                            : _missingPhoto(context),
                                      )
                                    else if (snapshot.connectionState ==
                                            ConnectionState.done &&
                                        preview == null)
                                      _missingPhoto(context),
                                  ],
                                );
                              },
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
          if (_showNewerRetry)
            _edgeRetry(
              key: const Key('fullscreen-newer-retry'),
              alignment: Alignment.centerLeft,
              icon: Icons.chevron_left,
              onPressed: widget.sequence!.retryNewer,
              tooltip: strings.loadMoreFailedRetry,
            ),
          if (_showOlderRetry)
            _edgeRetry(
              key: const Key('fullscreen-older-retry'),
              alignment: Alignment.centerRight,
              icon: Icons.chevron_right,
              onPressed: widget.sequence!.retryOlder,
              tooltip: strings.loadMoreFailedRetry,
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              key: const Key('fullscreen-chrome'),
              opacity: _chromeVisible ? 1 : 0,
              duration: AppMotion.durationOf(context, AppMotion.short4),
              child: IgnorePointer(
                ignoring: !_chromeVisible,
                child: SafeArea(
                  child: AppBar(
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    automaticallyImplyLeading: false,
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _missingPhoto(BuildContext context) {
    return Center(
      child: Icon(
        Icons.broken_image_outlined,
        size: 64,
        color: Theme.of(context).colorScheme.error,
      ),
    );
  }

  Widget _edgeRetry({
    required Key key,
    required Alignment alignment,
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
  }) {
    return Align(
      alignment: alignment,
      child: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: IconButton.filledTonal(
          key: key,
          onPressed: onPressed,
          tooltip: tooltip,
          icon: Icon(icon),
        ),
      ),
    );
  }
}
