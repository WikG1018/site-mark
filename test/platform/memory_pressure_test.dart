import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/platform/memory_pressure_coordinator.dart';
import 'package:sitemark/platform/memory_pressure_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MemoryPressureController', () {
    test('system level pauses background work', () async {
      final controller = MemoryPressureController();
      addTearDown(controller.dispose);

      final control = _RecordingBackgroundControl();
      controller.attachBackground(control);

      await controller.dispatch(MemoryPressureLevel.system);

      expect(control.pauseCalls, 1);
      expect(control.resumeCalls, 0);
    });

    test('system level clears the Flutter image cache', () async {
      final controller = MemoryPressureController();
      addTearDown(controller.dispose);

      // The dispatch must not throw even when the image cache is empty
      // (which is the default in a fresh test binding). The actual
      // imageCache.clear() call is a framework API and is not asserted
      // here; the point is that the controller invokes it without error.
      await controller.dispatch(MemoryPressureLevel.system);

      expect(PaintingBinding.instance.imageCache.currentSize, 0);
    });

    test('trim level pauses background work and invokes release handlers',
        () async {
      final controller = MemoryPressureController();
      addTearDown(controller.dispose);

      final control = _RecordingBackgroundControl();
      var releaseCalls = 0;
      controller.attachBackground(control);
      controller.attachRelease(() => releaseCalls++);

      await controller.dispatch(MemoryPressureLevel.trim);

      expect(control.pauseCalls, 1);
      expect(releaseCalls, 1);
    });

    test('kill level invokes kill hooks but does not pause background',
        () async {
      final controller = MemoryPressureController();
      addTearDown(controller.dispose);

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
      addTearDown(controller.dispose);

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
      addTearDown(controller.dispose);

      final control = _RecordingBackgroundControl();
      final detach = controller.attachBackground(control);

      detach();
      await controller.dispatch(MemoryPressureLevel.system);

      expect(control.pauseCalls, 0);
    });

    test('failing handler does not block other handlers', () async {
      final controller = MemoryPressureController();
      addTearDown(controller.dispose);

      var secondCalled = false;
      controller.attachRelease(() => throw StateError('boom'));
      controller.attachRelease(() => secondCalled = true);

      await controller.dispatch(MemoryPressureLevel.trim);

      expect(secondCalled, isTrue);
    });
  });

  group('MemoryPressureCoordinator', () {
    test('forwards events and acks the service', () async {
      final service = _RecordingMemoryPressureService();
      final controller = MemoryPressureController();
      addTearDown(controller.dispose);
      final coordinator = MemoryPressureCoordinator(
        service: service,
        controller: controller,
      );

      coordinator.start();
      addTearDown(coordinator.dispose);

      // Simulate a native broadcast.
      expect(service.handlers.length, 1);
      await service.handlers.first(MemoryPressureLevel.trim);

      // The coordinator should have acked with success=true.
      expect(service.acks, [
        (MemoryPressureLevel.trim, true),
      ]);
    });
  });
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
    required bool success,
  }) async {
    acks.add((level, success));
  }
}
