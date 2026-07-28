import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/workflow/app_startup_recovery.dart';

void main() {
  test(
    'cleans interrupted imports, then recovers camera, locations, and queue',
    () async {
      final events = <String>[];
      final recovery = AppStartupRecovery(
        recoverCamera: () async => events.add('camera'),
        resolveLocations: () async => events.add('location'),
        reconcileQueue: () async => events.add('queue'),
        cleanupInterruptedImports: () async => events.add('imports'),
      );

      await recovery.run();

      expect(events, ['imports', 'camera', 'location', 'queue']);
    },
  );
}
