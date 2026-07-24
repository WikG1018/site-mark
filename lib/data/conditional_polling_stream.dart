import 'dart:async';

Stream<T> watchWithConditionalPolling<T>({
  required Stream<T> source,
  required Future<T> Function() load,
  required bool Function(T value) shouldPoll,
  bool Function(T previous, T next)? equals,
  Duration pollInterval = const Duration(seconds: 1),
  /// When true, the polling timer is stopped and stays stopped until the
  /// callback returns false again. Used by [AppDatabase.setPollingPaused] to
  /// suspend background polling while the app is backgrounded (ITGSA fair
  /// running memory: a backgrounded app must not keep waking the DB).
  bool Function()? isPaused,
}) {
  if (pollInterval <= Duration.zero) {
    throw ArgumentError.value(pollInterval, 'pollInterval', 'Must be positive');
  }

  late final StreamController<T> controller;
  StreamSubscription<T>? sourceSubscription;
  Timer? timer;
  T? latest;
  var hasLatest = false;
  var pollRunning = false;
  var sourceVersion = 0;
  var active = false;
  late Future<void> Function() poll;

  bool same(T previous, T next) =>
      equals?.call(previous, next) ?? previous == next;

  bool globallyPaused() => isPaused != null && isPaused();

  void stopPolling() {
    timer?.cancel();
    timer = null;
  }

  void updatePolling(T value) {
    if (!active || !shouldPoll(value)) {
      stopPolling();
      return;
    }
    // Start the timer even if currently paused: when paused, the timer
    // fires but [poll] skips the actual load and re-checks the pause flag.
    // This way, when the pause is lifted (e.g. the app is foregrounded),
    // polling resumes immediately on the next tick without needing an
    // external "kick". The cost of a paused tick is a single bool check,
    // which is negligible compared to the drift query it would otherwise
    // run.
    timer ??= Timer.periodic(pollInterval, (_) => unawaited(poll()));
  }

  void accept(T value) {
    if (!active) return;
    final changed = !hasLatest || !same(latest as T, value);
    latest = value;
    hasLatest = true;
    updatePolling(value);
    if (changed && !controller.isClosed) {
      controller.add(value);
    }
  }

  poll = () async {
    if (!active || pollRunning || controller.isClosed) return;
    // Re-check the pause flag at fire time: the app may have been
    // backgrounded between scheduling and firing. The timer stays alive so
    // polling resumes automatically when the pause is lifted.
    if (globallyPaused()) {
      return;
    }
    pollRunning = true;
    final versionAtStart = sourceVersion;
    try {
      final result = await load();
      // Discard the result if a newer source event arrived while loading.
      if (sourceVersion == versionAtStart) {
        accept(result);
      }
    } catch (_) {
      // Keep the primary Drift stream alive and retry on the next interval.
    } finally {
      pollRunning = false;
    }
  };

  void onSourceValue(T value) {
    sourceVersion += 1;
    accept(value);
  }

  controller = StreamController<T>(
    onListen: () {
      active = true;
      sourceSubscription = source.listen(
        onSourceValue,
        onError: (Object error, StackTrace stackTrace) {
          controller.addError(error, stackTrace);
        },
        onDone: () {
          active = false;
          stopPolling();
          unawaited(controller.close());
        },
      );
    },
    onPause: () {
      active = false;
      sourceSubscription?.pause();
      stopPolling();
    },
    onResume: () {
      active = true;
      sourceSubscription?.resume();
      if (hasLatest) updatePolling(latest as T);
    },
    onCancel: () async {
      active = false;
      stopPolling();
      await sourceSubscription?.cancel();
    },
  );

  return controller.stream;
}
