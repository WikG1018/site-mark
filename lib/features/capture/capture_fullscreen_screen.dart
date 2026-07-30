import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/motion.dart';
import 'package:sitemark/platform/memory_pressure_coordinator.dart';

/// Lazily resolves one photo shown by [CaptureFullscreenScreen].
///
/// Keeping resolution lazy prevents opening the viewer from stat-ing and
/// decoding every photo in a large project up front. [initialPath] and
/// [previewImage] keep the tapped photo visible immediately.
final class CaptureFullscreenPhoto {
  CaptureFullscreenPhoto({
    required this.id,
    required this.resolvePath,
    this.initialPath,
    this.previewImage,
  });

  factory CaptureFullscreenPhoto.resolved({
    required String path,
    ImageProvider<Object>? previewImage,
  }) {
    return CaptureFullscreenPhoto(
      id: path,
      initialPath: path,
      previewImage: previewImage,
      resolvePath: () async => path,
    );
  }

  final String id;
  final Future<String?> Function() resolvePath;
  final String? initialPath;
  final ImageProvider<Object>? previewImage;
}

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
  CaptureFullscreenScreen({
    super.key,
    required this.photos,
    this.initialIndex = 0,
  }) : assert(photos.isNotEmpty, 'photos must not be empty'),
       assert(initialIndex >= 0 && initialIndex < photos.length);

  final List<CaptureFullscreenPhoto> photos;

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

  late final PageController _pageController;
  final Map<int, TransformationController> _transformationControllers = {};
  final Map<int, VoidCallback> _transformationListeners = {};
  final Map<int, Future<String?>> _pathFutures = {};
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
  int? _scaleTargetPage;
  VoidCallback? _releaseDetach;

  TransformationController _controllerFor(int index) {
    return _transformationControllers.putIfAbsent(index, () {
      final controller = TransformationController();
      void listener() => _onTransformChanged(index);
      _transformationListeners[index] = listener;
      controller.addListener(listener);
      return controller;
    });
  }

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _scaleController.addListener(() {
      final animation = _scaleAnimation;
      final targetPage = _scaleTargetPage;
      if (animation != null && targetPage != null) {
        _controllerFor(targetPage).value = animation.value;
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
  }

  @override
  void dispose() {
    _releaseDetach?.call();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _scaleController.dispose();
    _dragController.dispose();
    _pageController.dispose();
    for (final entry in _transformationControllers.entries) {
      final listener = _transformationListeners[entry.key];
      if (listener != null) entry.value.removeListener(listener);
      entry.value.dispose();
    }
    super.dispose();
  }

  void _onPageChanged(int index) {
    _scaleController.stop();
    _scaleAnimation = null;
    _scaleTargetPage = null;
    final zoomed = _controllerFor(index).value.getMaxScaleOnAxis() > 1.01;
    setState(() {
      _currentPage = index;
      _zoomed = zoomed;
      _dragOffset = 0;
    });
  }

  void _onTransformChanged(int index) {
    if (index != _currentPage) return;
    final zoomed = _controllerFor(index).value.getMaxScaleOnAxis() > 1.01;
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
    final targetPage = _currentPage;
    final current = _controllerFor(targetPage).value;
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
      _controllerFor(targetPage).value = end;
      return;
    }
    _scaleAnimation = Matrix4Tween(begin: current, end: end).animate(
      CurvedAnimation(
        parent: _scaleController,
        curve: AppMotion.emphasizedDecelerate,
      ),
    );
    _scaleTargetPage = targetPage;
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
            itemCount: widget.photos.length,
            onPageChanged: _onPageChanged,
            // Only allow horizontal swipe when not zoomed.
            physics: _zoomed
                ? const NeverScrollableScrollPhysics()
                : const PageScrollPhysics(),
            itemBuilder: (context, index) {
              final photo = widget.photos[index];
              final preview = photo.previewImage;
              final transformController = _controllerFor(index);

              return GestureDetector(
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
                              index,
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
              );
            },
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
}
