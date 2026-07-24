import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/platform/memory_pressure_coordinator.dart';
import 'package:sitemark/platform/memory_pressure_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MemoryPressureController', () {
    test('system level does not pause background work', () async {
      final controller = MemoryPressureController();

      final control = _RecordingBackgroundControl();
      controller.attachBackground(control);

      await controller.dispatch(MemoryPressureLevel.system);

      // System/TRIM only releases resources; lifecycle owns pause/resume.
      expect(control.pauseCalls, 0);
      expect(control.resumeCalls, 0);
    });

    test('system level clears the Flutter image cache', () async {
      final controller = MemoryPressureController();

      // Seed the cache with a keep-alive image so the clear() call has a
      // visible effect. An empty cache would make the post-dispatch
      // assertion vacuously true.
      final image = await _createTestImage();
      addTearDown(image.dispose);
      final provider = _TestImageProvider(image);
      final stream = provider.resolve(ImageConfiguration.empty);
      final listener = ImageStreamListener((_, _) {});
      stream.addListener(listener);
      addTearDown(() => stream.removeListener(listener));
      await Future<void>.delayed(Duration.zero);
      // Transition the image from a live image (listener attached) to a
      // keep-alive cached image. Flutter's `ImageCache.clear()` evicts
      // cached images but does not remove live images that still have
      // active listeners.
      stream.removeListener(listener);
      expect(PaintingBinding.instance.imageCache.currentSize, 1);

      await controller.dispatch(MemoryPressureLevel.system);

      expect(PaintingBinding.instance.imageCache.currentSize, 0);
    });

    test('trim level invokes release handlers without pausing background work',
        () async {
      final controller = MemoryPressureController();

      final control = _RecordingBackgroundControl();
      var releaseCalls = 0;
      controller.attachBackground(control);
      controller.attachRelease(() => releaseCalls++);

      await controller.dispatch(MemoryPressureLevel.trim);

      // TRIM does NOT pause polling — lifecycle owns pause/resume. This
      // prevents a forged or real TRIM from stalling foreground polling.
      expect(control.pauseCalls, 0);
      expect(releaseCalls, 1);
    });

    test('kill level invokes kill hooks but does not pause background',
        () async {
      final controller = MemoryPressureController();

      final control = _RecordingBackgroundControl();
      final hook = _RecordingKillHook();
      controller.attachBackground(control);
      controller.attachKillHook(hook);

      await controller.dispatch(MemoryPressureLevel.kill);

      // Kill does not pause background work; it only persists state.
      expect(control.pauseCalls, 0);
      expect(hook.persistCalls, 1);
    });

    test('resumeBackgroundWork resumes all attached controls', () {
      final controller = MemoryPressureController();

      final control1 = _RecordingBackgroundControl();
      final control2 = _RecordingBackgroundControl();
      controller.attachBackground(control1);
      controller.attachBackground(control2);

      controller.resumeBackgroundWork();

      expect(control1.resumeCalls, 1);
      expect(control2.resumeCalls, 1);
    });

    test('detach stops receiving events', () async {
      final controller = MemoryPressureController();

      final control = _RecordingBackgroundControl();
      final detach = controller.attachBackground(control);

      detach();
      await controller.dispatch(MemoryPressureLevel.system);

      expect(control.pauseCalls, 0);
    });

    test('failing handler does not block other handlers', () async {
      final controller = MemoryPressureController();

      var secondCalled = false;
      controller.attachRelease(() => throw StateError('boom'));
      controller.attachRelease(() => secondCalled = true);

      await controller.dispatch(MemoryPressureLevel.trim);

      expect(secondCalled, isTrue);
    });

    // Tests for the separated operations (C1 fix: foreground pressure must
    // not pause polling, and backgrounding must pair pause + release).

    test('pauseBackgroundWork pauses controls without releasing caches',
        () async {
      final controller = MemoryPressureController();

      final control = _RecordingBackgroundControl();
      var releaseCalls = 0;
      controller.attachBackground(control);
      controller.attachRelease(() => releaseCalls++);

      controller.pauseBackgroundWork();

      expect(control.pauseCalls, 1);
      expect(releaseCalls, 0);
    });

    test('releaseResources clears caches without pausing controls', () async {
      final controller = MemoryPressureController();

      final control = _RecordingBackgroundControl();
      var releaseCalls = 0;
      controller.attachBackground(control);
      controller.attachRelease(() => releaseCalls++);

      controller.releaseResources();

      expect(control.pauseCalls, 0);
      expect(releaseCalls, 1);
    });

    test('kill hook detach stops receiving kill events', () async {
      final controller = MemoryPressureController();

      final hook = _RecordingKillHook();
      final detach = controller.attachKillHook(hook);

      detach();
      await controller.dispatch(MemoryPressureLevel.kill);

      expect(hook.persistCalls, 0);
    });
  });

  group('MemoryPressureCoordinator', () {
    test('forwards events and acks the service', () async {
      final service = _RecordingMemoryPressureService();
      final controller = MemoryPressureController();
      final coordinator = MemoryPressureCoordinator(
        service: service,
        controller: controller,
      );

      coordinator.start();
      addTearDown(coordinator.dispose);

      // Simulate a native broadcast.
      expect(service.handlers.length, 1);
      await service.handlers.first(MemoryPressureLevel.trim, null);

      // The coordinator should have acked with success=true.
      expect(service.acks, [
        (MemoryPressureLevel.trim, true),
      ]);
    });
  });
}

/// Creates a 1×1 [ui.Image] for seeding the image cache in tests.
Future<ui.Image> _createTestImage() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(
    const ui.Color(0xFFFFFFFF),
    ui.BlendMode.src,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(1, 1);
  picture.dispose();
  return image;
}

/// Minimal [ImageProvider] that synchronously returns a pre-decoded
/// [ui.Image], so tests can seed the image cache without real decoding.
class _TestImageProvider extends ImageProvider<_TestImageProvider> {
  _TestImageProvider(this.image);

  final ui.Image image;

  @override
  Future<_TestImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_TestImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    _TestImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(
      Future<ImageInfo>.value(ImageInfo(image: image)),
    );
  }
}

class _RecordingBackgroundControl implements BackgroundWorkControl {
  int pauseCalls = 0;
  int resumeCalls = 0;

  @override
  void pauseBackgroundWork() => pauseCalls++;

  @override
  void resumeBackgroundWork() => resumeCalls++;
}

class _RecordingKillHook implements KillBackupHook {
  int persistCalls = 0;

  @override
  Future<void> persistForKill() async {
    persistCalls++;
  }
}

class _RecordingMemoryPressureService implements MemoryPressureService {
  final List<MemoryPressureHandler> handlers = [];
  final List<(MemoryPressureLevel, bool)> acks = [];

  @override
  Future<void> initialize() async {}

  @override
  VoidCallback addHandler(MemoryPressureHandler handler) {
    handlers.add(handler);
    return () => handlers.remove(handler);
  }

  @override
  Future<void> acknowledge(
    MemoryPressureLevel level, {
    int? eventId,
    required bool success,
  }) async {
    acks.add((level, success));
  }
}
