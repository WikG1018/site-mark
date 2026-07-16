import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/workflow/app_startup_recovery.dart';

void main() {
  test(
    'recovers camera state before reconciling the processing queue',
    () async {
      final events = <String>[];
      final recovery = AppStartupRecovery(
        recoverCamera: () async => events.add('camera'),
        reconcileQueue: () async => events.add('queue'),
      );

      await recovery.run();

      expect(events, ['camera', 'queue']);
    },
  );
}
