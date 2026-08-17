import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark_system_api/src/ohos/ohos_system_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('channel name is stable', () {
    expect(ohosSystemChannel.name, 'sitemark.system.ohos');
  });

  test('unimplemented methods throw stable capability code', () async {
    final api = OhosSystemApi();
    final calls = <Future<Object?>>[
      api.createCameraTarget('capture-1'),
      api.launchCamera('capture-1'),
      api.recoverCameraCapture(),
      api.finishCameraCapture('capture-1', false),
      api.getLocationPermissionState(),
      api.requestLocationPermission(),
      api.openApplicationSettings(),
      api.inspectImage('/tmp/a.jpg'),
      api.requestCurrentLocation(1000),
      api.publishJpeg('/tmp/a.jpg', 'IMG-0001', 'capture-1', null),
      api.recoverPublishJournals(),
      api.clearPublishJournal('capture-1', 'content://a'),
      api.saveArchive('/tmp/a.jpg', 'archive.jpg'),
      api.deletePublishedImage('content://a'),
    ];

    for (final call in calls) {
      await expectLater(
        call,
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'ohos_not_ready',
          ),
        ),
      );
    }
  });
}
