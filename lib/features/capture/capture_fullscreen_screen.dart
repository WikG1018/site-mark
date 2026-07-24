import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/motion.dart';
import 'package:sitemark/platform/memory_pressure_coordinator.dart';

/// Full-screen immersive photo viewer pushed from the detail image preview.
///
/// The page sits on a pure black [Scaffold] and enters
/// [SystemUiMode.immersiveSticky] while visible (restoring
/// [SystemUiMode.edgeToEdge] on dispose). Gestures:
///
/// - single tap toggles the transparent chrome [AppBar] (an
///   [AnimatedOpacity] overlay) together with the system bars;
/// - double tap animates the [TransformationController] between 1x and 2x,
///   focusing the 2x zoom on the tapped point;
/// - while at 1x, a vertical drag moves the photo with the finger and shrinks
///   it proportionally; releasing past the dismiss threshold (or with enough
///   velocity) pops the route, otherwise the photo animates back;
/// - while zoomed past 1x the [InteractiveViewer] pans normally and the
///   drag-to-dismiss gesture is disabled.
///
/// The image area declares a live-region [Semantics] label and decodes the
/// photo at its full native resolution so zoom (up to 4x) preserves original
/// detail. Memory peaks are mitigated by the OS page cache and the fact that
/// the viewer is only reached from the detail screen for a single image.
class CaptureFullscreenScreen extends ConsumerStatefulWidget {
  const CaptureFullscreenScreen({super.key, required this.path});

  /// Absolute path of the on-disk photo to display.
  final String path;

  @override
  ConsumerState<CaptureFullscreenScreen> createState() =>
      _CaptureFullscreenScreenState();
}

class _CaptureFullscreenScreenState extends ConsumerState<CaptureFullscreenScreen>
    with TickerProviderStateMixin {
  static const double _dismissThreshold = 120;
  static const double _dismissVelocity = 700;
  static const double _dragShrinkFactor = 600;
  static const double _minDragScale = 0.7;

  final TransformationController _transformationController =
      TransformationController();
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
  VoidCallback? _releaseDetach;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _transformationController.addListener(_onTransformChanged);
    _scaleController.addListener(() {
      final animation = _scaleAnimation;
      if (animation != null) _transformationController.value = animation.value;
    });
    _dragController.addListener(() {
      final animation = _dragAnimation;
      if (animation != null) setState(() => _dragOffset = animation.value);
    });
    // ITGSA fair-memory: the fullscreen viewer holds the photo at its full
    // native resolution (so 4x zoom preserves detail). When a MEMORY_TRIM or
    // a framework memory-pressure callback arrives, pop the route so the
    // Bitmap is released immediately rather than waiting for the user to
    // dismiss. The viewer is only reachable from the detail screen, so
    // popping returns the user to a sensible place.
    final controller = ref.read(memoryPressureControllerProvider);
    _releaseDetach = controller.attachRelease(() {
      // Only pop if this route is still the topmost — the release handler
      // can fire while a different route (e.g. a system dialog or another
      // push) has replaced this one on the navigator stack.
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
    _transformationController.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final zoomed = _transformationController.value.getMaxScaleOnAxis() > 1.01;
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
    final current = _transformationController.value;
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
    _scaleAnimation = Matrix4Tween(begin: current, end: end).animate(
      CurvedAnimation(
        parent: _scaleController,
        curve: AppMotion.emphasizedDecelerate,
      ),
    );
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
          GestureDetector(
            onTap: _toggleChrome,
            onDoubleTapDown: (details) =>
                _doubleTapPosition = details.localPosition,
            onDoubleTap: _handleDoubleTap,
            onVerticalDragStart: _zoomed ? null : _onVerticalDragStart,
            onVerticalDragUpdate: _zoomed ? null : _onVerticalDragUpdate,
            onVerticalDragEnd: _zoomed ? null : _onVerticalDragEnd,
            child: Transform.translate(
              offset: Offset(0, _dragOffset),
              child: Transform.scale(
                scale: dragScale,
                child: InteractiveViewer(
                  transformationController: _transformationController,
                  panEnabled: _zoomed,
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: Semantics(
                      label: strings.fullscreenPhotoSemantics,
                      liveRegion: true,
                      child: Image.file(
                        File(widget.path),
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
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              opacity: _chromeVisible ? 1 : 0,
              duration: AppMotion.short4,
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
}
