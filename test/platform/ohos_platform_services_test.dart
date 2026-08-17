import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/platform/ohos_background_work_client.dart';
import 'package:sitemark/platform/ohos_platform_services.dart';
import 'package:sitemark/platform/platform_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('OhosPlatformServices implements PlatformServices', () {
    expect(OhosPlatformServices(), isA<PlatformServices>());
  });

  test('every method maps ohos_not_ready', () async {
    final services = OhosPlatformServices();
    final calls = <Future<Object?>>[
      services.createCameraTarget('capture-1'),
      services.launchCamera('capture-1'),
      services.recoverCameraCapture(),
      services.finishCameraCapture('capture-1', false),
      services.getLocationPermissionState(),
      services.requestLocationPermission(),
      services.openApplicationSettings(),
      services.inspectImage('/tmp/a.jpg'),
      services.requestCurrentLocation(1000),
      services.publishJpeg('/tmp/a.jpg', 'IMG-0001', 'capture-1', null),
      services.recoverPublishJournals(),
      services.clearPublishJournal('capture-1', 'content://a'),
      services.deletePublishedImage('content://a'),
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

  test('unimplemented background queue throws ohos_queue_not_ready', () {
    final client = UnimplementedOhosBackgroundWorkClient();
    expect(
      () => client.appendCapture(
        queueName: 'queue',
        taskName: 'task',
        captureId: 'capture-1',
        tag: 'tag',
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'ohos_queue_not_ready',
        ),
      ),
    );
  });
}
