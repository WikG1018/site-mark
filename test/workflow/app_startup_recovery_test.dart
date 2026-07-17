import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/workflow/app_startup_recovery.dart';

void main() {
  test(
    'recovers camera, resolves locations, then reconciles the processing queue',
    () async {
      final events = <String>[];
      final recovery = AppStartupRecovery(
        recoverCamera: () async => events.add('camera'),
        resolveLocations: () async => events.add('location'),
        reconcileQueue: () async => events.add('queue'),
      );

      await recovery.run();

      expect(events, ['camera', 'location', 'queue']);
    },
  );
}
