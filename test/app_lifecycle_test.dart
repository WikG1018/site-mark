import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/main.dart';
import 'package:sitemark/platform/capture_form_draft_store.dart';
import 'package:sitemark/platform/memory_pressure_coordinator.dart';
import 'package:sitemark/platform/memory_pressure_service.dart';
import 'package:sitemark/platform/notification_service.dart';

/// Tests that [_SiteMarkAppState] correctly delegates lifecycle and
/// memory-pressure events to the [MemoryPressureController].
///
/// These tests verify the C1 fix (foreground `didHaveMemoryPressure` does
/// NOT pause polling) and the I1 fix (`inactive` does NOT release resources)
/// at the integration level, complementing the unit tests in
/// `memory_pressure_test.dart`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late _RecordingController controller;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    controller = _RecordingController();
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> disposeApp(WidgetTester tester) async {
    // Dispose the widget tree so provider-owned timers and stream
    // subscriptions are cancelled. This triggers drift's
    // StreamQueryStore.markAsClosed (stream_queries.dart:156), which
    // creates 0-duration Timers via Timer.run to defer stream-cache
    // cleanup.
    await tester.pumpWidget(const SizedBox.shrink());
    // Per drift's recommendation (see the comment in markAsClosed), call
    // database.close() to drain those pending timers. We start close()
    // — which synchronously sets _isShuttingDown = true so no further
    // timers are created — then pump to advance the FakeAsync clock so
    // the existing Timer.run callbacks fire and complete drift's
    // internal completers. Awaiting closeFuture then returns promptly.
    final closeFuture = database.close();
    await tester.pump(const Duration(milliseconds: 1));
    await closeFuture;
  }

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      MyApp(
        database: database,
        initialLocale: const Locale('zh'),
        completionNotificationService: _FakeCompletionNotificationService(),
        captureFormDraftStore: MemoryCaptureFormDraftStore(),
        memoryPressureController: controller,
        memoryPressureService: _NoopMemoryPressureService(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> setLifecycleState(
    WidgetTester tester,
    AppLifecycleState state,
  ) async {
    final bytes = const StringCodec().encodeMessage(
      'AppLifecycleState.${state.name}',
    );
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/lifecycle',
      bytes,
      (ByteData? data) {},
    );
    // Use pump with a duration (not bare pump()) so the FakeAsync clock
    // advances and 0-duration Timers created by drift's stream-store
    // cleanup during the lifecycle-triggered rebuild are flushed immediately.
    // Bare pump() does not advance the clock, so those timers accumulate
    // and eventually cause "_verifyInvariants: A Timer is still pending".
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> sendMemoryPressure(WidgetTester tester) async {
    // Directly invoke the binding's memory-pressure handler. Going through
    // the `flutter/memory` platform channel in a test environment is
    // unreliable across Flutter versions (the BasicMessageChannel handler
    // registration and `handlePlatformMessage` routing don't always
    // converge). The binding method notifies all observers including
    // `_SiteMarkAppState`, which is exactly what we want to verify.
    tester.binding.handleMemoryPressure();
    await tester.pump(const Duration(milliseconds: 1));
  }

  group('lifecycle → MemoryPressureController delegation', () {
    testWidgets('paused pauses and releases; resumed resumes', (tester) async {
      await pumpApp(tester);
      controller.reset();

      await setLifecycleState(tester, AppLifecycleState.paused);

      expect(controller.pauseCalls, 1);
      expect(controller.releaseCalls, 1);
      expect(controller.resumeCalls, 0);

      await setLifecycleState(tester, AppLifecycleState.resumed);

      expect(controller.resumeCalls, 1);
      // Pause/release must not be called again on resume.
      expect(controller.pauseCalls, 1);
      expect(controller.releaseCalls, 1);
      await disposeApp(tester);
    });

    testWidgets('hidden pairs pause and release like paused', (tester) async {
      await pumpApp(tester);
      controller.reset();

      await setLifecycleState(tester, AppLifecycleState.hidden);

      expect(controller.pauseCalls, 1);
      expect(controller.releaseCalls, 1);

      await setLifecycleState(tester, AppLifecycleState.resumed);

      expect(controller.resumeCalls, 1);
      await disposeApp(tester);
    });

    testWidgets('inactive does not pause, release, or resume (I1 fix)',
        (tester) async {
      await pumpApp(tester);
      controller.reset();

      await setLifecycleState(tester, AppLifecycleState.inactive);

      expect(controller.pauseCalls, 0);
      expect(controller.releaseCalls, 0);
      expect(controller.resumeCalls, 0);
      await disposeApp(tester);
    });

    testWidgets('didHaveMemoryPressure releases but does not pause (C1 fix)',
        (tester) async {
      await pumpApp(tester);
      controller.reset();

      await sendMemoryPressure(tester);

      expect(controller.releaseCalls, 1);
      expect(controller.pauseCalls, 0);
      await disposeApp(tester);
    });

    testWidgets('repeated paused does not double-pause', (tester) async {
      await pumpApp(tester);
      controller.reset();

      await setLifecycleState(tester, AppLifecycleState.paused);
      await setLifecycleState(tester, AppLifecycleState.paused);

      expect(controller.pauseCalls, 1);
      expect(controller.releaseCalls, 1);
      await disposeApp(tester);
    });
  });
}

/// [MemoryPressureController] subclass that records calls to the three
/// orthogonal operations so tests can assert the lifecycle delegation.
class _RecordingController extends MemoryPressureController {
  int pauseCalls = 0;
  int resumeCalls = 0;
  int releaseCalls = 0;

  void reset() {
    pauseCalls = 0;
    resumeCalls = 0;
    releaseCalls = 0;
  }

  @override
  void pauseBackgroundWork() {
    pauseCalls++;
    super.pauseBackgroundWork();
  }

  @override
  void releaseResources() {
    releaseCalls++;
    super.releaseResources();
  }

  @override
  void resumeBackgroundWork() {
    resumeCalls++;
    super.resumeBackgroundWork();
  }
}

class _FakeCompletionNotificationService
    implements CompletionNotificationService {
  @override
  Future<void> initialize(void Function(String deepLinkPath) onTapDeepLink) =>
      Future.value();

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> showCaptureReady({
    required String projectId,
    required String captureId,
    required String photoNumber,
  }) =>
      Future.value();

  @override
  Future<void> setEnabled(bool enabled) => Future.value();
}

class _NoopMemoryPressureService implements MemoryPressureService {
  @override
  Future<void> initialize() async {}

  @override
  VoidCallback addHandler(MemoryPressureHandler handler) {
    return () {};
  }

  @override
  Future<void> acknowledge(
    MemoryPressureLevel level, {
    int? eventId,
    required bool success,
  }) async {}
}
