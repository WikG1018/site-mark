import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/domain/release_check.dart';
import 'package:sitemark/platform/automatic_update_controller.dart';
import 'package:sitemark/platform/github_release_client.dart';
import 'package:sitemark/platform/release_check_mode_store.dart';

const update = ReleaseCheckOutcome(
  status: ReleaseCheckStatus.updateAvailable,
  versionLabel: '1.0.34',
  tag: 'v1.0.34',
  source: ReleaseSource.official,
);

void main() {
  late _Store store;
  late _Lookup lookup;
  late DateTime now;
  AutomaticUpdateController create({Future<String?> Function()? version}) =>
      AutomaticUpdateController(
        store: store,
        lookup: lookup,
        modes: MemoryReleaseCheckModeStore(ReleaseCheckMode.mirror),
        version: version ?? () async => '1.0.33',
        clock: () => now,
      );
  setUp(() {
    store = _Store();
    lookup = _Lookup();
    now = DateTime.utc(2026, 10, 23);
  });

  test(
    'checks once per day across resume and restart, using selected source',
    () async {
      final first = create();
      await first.checkOnForeground();
      expect(first.pendingReminder, same(update));
      await first.checkOnForeground();
      final restarted = create();
      await restarted.checkOnForeground();
      expect(lookup.calls, 1);
      expect(lookup.mode, ReleaseCheckMode.mirror);
      now = now.add(const Duration(days: 1));
      await restarted.checkOnForeground();
      expect(lookup.calls, 2);
      first.dispose();
      restarted.dispose();
    },
  );

  test(
    'disabled checks never use network and preference survives restart',
    () async {
      final controller = create();
      expect(await controller.setEnabled(false), isTrue);
      await controller.checkOnForeground();
      final restarted = create();
      await restarted.checkOnForeground();
      expect(restarted.enabled, isFalse);
      expect(lookup.calls, 0);
      controller.dispose();
      restarted.dispose();
    },
  );

  test('offline failures stay quiet and are throttled too', () async {
    lookup.failure = true;
    final controller = create();
    await controller.checkOnForeground();
    await controller.checkOnForeground();
    expect(controller.pendingReminder, isNull);
    expect(lookup.calls, 1);
    controller.dispose();
  });

  test('overlapping resumes share a single in-flight check', () async {
    final completer = Completer<ReleaseCheckOutcome>();
    lookup.pending = completer.future;
    final controller = create();
    final first = controller.checkOnForeground();
    await Future<void>.delayed(Duration.zero);
    await controller.checkOnForeground();
    expect(lookup.calls, 1);
    completer.complete(update);
    await first;
    expect(controller.pendingReminder, same(update));
    controller.dispose();
  });

  test('disabling while checking discards the late result', () async {
    final completer = Completer<ReleaseCheckOutcome>();
    lookup.pending = completer.future;
    final controller = create();
    final checking = controller.checkOnForeground();
    await Future<void>.delayed(Duration.zero);
    await controller.setEnabled(false);
    completer.complete(update);
    await checking;
    expect(controller.pendingReminder, isNull);
    expect(store.state.enabled, isFalse);
    controller.dispose();
  });

  test('a reminder is shown only once per version per day', () async {
    final controller = create();
    await controller.checkOnForeground();
    await controller.markReminded();
    expect(controller.pendingReminder, isNull);
    now = now.add(const Duration(days: 1));
    await controller.checkOnForeground();
    expect(controller.pendingReminder, same(update));
    controller.dispose();
  });

  test('metadata and persistence failures do not trigger network', () async {
    final invalid = create(version: () async => null);
    await invalid.checkOnForeground();
    expect(lookup.calls, 0);
    invalid.dispose();
    store.failWrite = true;
    final controller = create();
    await controller.checkOnForeground();
    expect(lookup.calls, 0);
    expect(await controller.setEnabled(false), isFalse);
    controller.dispose();
  });

  test('disposed controller ignores a completed request', () async {
    final completer = Completer<ReleaseCheckOutcome>();
    lookup.pending = completer.future;
    final controller = create();
    final checking = controller.checkOnForeground();
    await Future<void>.delayed(Duration.zero);
    controller.dispose();
    completer.complete(update);
    await checking;
    expect(controller.outcome, isNull);
  });

  test('file preferences round trip and corrupt files fail closed', () async {
    final dir = await Directory.systemTemp.createTemp('sitemark-update-test-');
    addTearDown(() => dir.delete(recursive: true));
    final files = FileAutomaticUpdateStore(directory: () async => dir);
    expect((await files.read()).enabled, isTrue);
    await files.write(
      AutomaticUpdateState(
        enabled: false,
        lastCheck: now,
        remindedTag: 'v1.0.34',
        remindedAt: now,
      ),
    );
    final read = await files.read();
    expect(read.enabled, isFalse);
    expect(read.lastCheck, now);
    expect(read.remindedTag, 'v1.0.34');
    await File('${dir.path}/automatic_update.json').writeAsString('broken');
    await expectLater(files.read(), throwsFormatException);
    expect(
      await File('${dir.path}/automatic_update.json.tmp').exists(),
      isFalse,
    );
  });
}

class _Store implements AutomaticUpdateStore {
  AutomaticUpdateState state = const AutomaticUpdateState();
  bool failWrite = false;
  @override
  Future<AutomaticUpdateState> read() async => state;
  @override
  Future<void> write(AutomaticUpdateState next) async {
    if (failWrite) throw const FileSystemException('unavailable');
    state = next;
  }
}

class _Lookup implements ReleaseLookup {
  int calls = 0;
  bool failure = false;
  ReleaseCheckMode? mode;
  Future<ReleaseCheckOutcome>? pending;
  @override
  Future<ReleaseCheckOutcome> check({
    required String localVersion,
    required ReleaseCheckMode mode,
  }) async {
    calls++;
    this.mode = mode;
    if (failure) throw const SocketException('offline');
    return pending ?? update;
  }

  @override
  Future<Uri?> resolveReleasePage(ReleaseCheckOutcome outcome) async => null;
}
