import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/bootstrap.dart';

void main() {
  test(
    'foreground UI starts before native runtime initialization completes',
    () async {
      final firstFrame = Completer<void>();
      final runtime = Completer<void>();
      var uiStarted = false;
      var runtimeStarted = false;

      final bootstrap = bootstrapForeground(
        startUi: () => uiStarted = true,
        waitForFirstFrame: () => firstFrame.future,
        initializeRuntime: () {
          runtimeStarted = true;
          return runtime.future;
        },
      );

      expect(uiStarted, isTrue);
      expect(runtimeStarted, isFalse);

      firstFrame.complete();
      await Future<void>.delayed(Duration.zero);
      expect(runtimeStarted, isTrue);
      expect(runtime.isCompleted, isFalse);

      runtime.complete();
      await bootstrap;
    },
  );
}
