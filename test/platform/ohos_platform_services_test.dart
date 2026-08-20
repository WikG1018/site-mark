import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/platform/notification_service.dart';
import 'package:sitemark/platform/ohos_background_work_client.dart';
import 'package:sitemark/platform/ohos_platform_services.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark_system_api/sitemark_system_api.dart';

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

  test('OhosArchiveSaveService maps missing plugin to ohos_not_ready', () async {
    final service = OhosArchiveSaveService();
    await expectLater(
      service.saveArchive('/tmp/exports/sitemark-backup-1.zip'),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'ohos_not_ready',
        ),
      ),
    );
  });

  test('OhosArchiveSaveService decodes saved and sends the zip basename', () async {
    const channel = MethodChannel('sitemark.system.ohos');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'saveArchive');
          final args = Map<String, Object?>.from(call.arguments as Map);
          expect(args['sourcePath'], '/tmp/exports/sitemark-backup-1.zip');
          expect(args['suggestedName'], 'sitemark-backup-1.zip');
          return 0;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final outcome = await OhosArchiveSaveService().saveArchive(
      '/tmp/exports/sitemark-backup-1.zip',
    );
    expect(outcome, ArchiveSaveOutcome.saved);
  });

  test('OhosArchiveSaveService decodes cancelled', () async {
    const channel = MethodChannel('sitemark.system.ohos');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => 1);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    expect(
      await OhosArchiveSaveService().saveArchive(
        '/tmp/exports/sitemark-backup-1.zip',
      ),
      ArchiveSaveOutcome.cancelled,
    );
  });

  test('OhosArchivePickService maps missing plugin to ohos_not_ready', () async {
    final service = OhosArchivePickService();
    await expectLater(
      service.pickArchive(),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'ohos_not_ready',
        ),
      ),
    );
  });

  test('OhosArchivePickService returns sandbox path from pickArchive', () async {
    const channel = MethodChannel('sitemark.system.ohos');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'pickArchive');
          expect(call.arguments, isNull);
          return '/data/storage/el2/base/files/imports/sitemark-restore-1.zip';
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    expect(
      await OhosArchivePickService().pickArchive(),
      '/data/storage/el2/base/files/imports/sitemark-restore-1.zip',
    );
  });

  test('OhosArchivePickService treats empty path as cancelled', () async {
    const channel = MethodChannel('sitemark.system.ohos');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => '');
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    expect(await OhosArchivePickService().pickArchive(), isNull);
  });

  test('OhosPlatformServices inspectImage decodes metadata map', () async {
    const channel = MethodChannel('sitemark.system.ohos');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'inspectImage');
          expect(call.arguments, {'path': '/tmp/a.jpg'});
          return <String, Object?>{
            'width': 4032,
            'height': 3024,
            'fileSizeBytes': 2048,
            'mimeType': 'image/jpeg',
            'latitude': 31.23,
            'longitude': 121.47,
          };
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final metadata = await OhosPlatformServices().inspectImage('/tmp/a.jpg');
    expect(metadata.width, 4032);
    expect(metadata.height, 3024);
    expect(metadata.fileSizeBytes, 2048);
    expect(metadata.mimeType, 'image/jpeg');
    expect(metadata.latitude, closeTo(31.23, 0.0001));
    expect(metadata.longitude, closeTo(121.47, 0.0001));
  });

  test('OhosPlatformServices inspectImage treats missing GPS as null', () async {
    const channel = MethodChannel('sitemark.system.ohos');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return <String, Object?>{
            'width': 100,
            'height': 80,
            'fileSizeBytes': 12,
            'mimeType': 'image/jpeg',
            'latitude': null,
            'longitude': null,
          };
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final metadata = await OhosPlatformServices().inspectImage('/tmp/a.jpg');
    expect(metadata.latitude, isNull);
    expect(metadata.longitude, isNull);
  });

  test('OhosShareFileService maps missing plugin to ohos_not_ready', () async {
    final service = OhosShareFileService();
    await expectLater(
      service.shareFile('/tmp/exports/sitemark-backup-1.zip'),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'ohos_not_ready',
        ),
      ),
    );
  });

  test('OhosShareFileService invokes shareFile with path', () async {
    const channel = MethodChannel('sitemark.system.ohos');
    String? method;
    Object? arguments;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          method = call.method;
          arguments = call.arguments;
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await OhosShareFileService().shareFile(
      '/tmp/exports/sitemark-backup-1.zip',
    );
    expect(method, 'shareFile');
    expect(arguments, {
      'path': '/tmp/exports/sitemark-backup-1.zip',
    });
  });

  test('requestEnableNotification uses the ohos channel', () async {
    late String method;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('sitemark.system.ohos'),
      (call) async {
        method = call.method;
        return true;
      },
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('sitemark.system.ohos'),
        null,
      );
    });

    expect(await OhosSystemApi().requestEnableNotification(), isTrue);
    expect(method, 'requestEnableNotification');
  });

  test('publishCaptureReady sends title, text, and deepLink', () async {
    late String method;
    late Object? arguments;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('sitemark.system.ohos'),
      (call) async {
        method = call.method;
        arguments = call.arguments;
        return null;
      },
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('sitemark.system.ohos'),
        null,
      );
    });

    await OhosSystemApi().publishCaptureReady(
      title: 'Capture ready',
      text: 'Photo 3 is ready',
      deepLink: '/projects/p1/captures/c1',
    );
    expect(method, 'publishCaptureReady');
    expect(arguments, {
      'title': 'Capture ready',
      'text': 'Photo 3 is ready',
      'deepLink': '/projects/p1/captures/c1',
    });
  });

  test('OhosCompletionNotificationService stays silent until enabled', () async {
    var published = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('sitemark.system.ohos'),
      (call) async {
        if (call.method == 'publishCaptureReady') {
          published = true;
        }
        return null;
      },
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('sitemark.system.ohos'),
        null,
      );
    });

    final service = OhosCompletionNotificationService();
    await service.showCaptureReady(
      projectId: 'p1',
      captureId: 'c1',
      photoNumber: '3',
    );
    expect(published, isFalse);

    await service.setEnabled(true);
    await service.showCaptureReady(
      projectId: 'p1',
      captureId: 'c1',
      photoNumber: '3',
    );
    expect(published, isTrue);
  });

  test('enabled capture-ready notice matches locale and deep link', () async {
    late Object? arguments;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('sitemark.system.ohos'),
      (call) async {
        arguments = call.arguments;
        return null;
      },
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('sitemark.system.ohos'),
        null,
      );
    });

    final service = OhosCompletionNotificationService();
    await service.setEnabled(true);
    await service.showCaptureReady(
      projectId: 'p1',
      captureId: 'c1',
      photoNumber: '3',
    );

    final zh = PlatformDispatcher.instance.locale.languageCode == 'zh';
    expect(arguments, {
      'title': zh ? '照片处理完成' : 'Photo ready',
      'text': zh
          ? '照片 3 已完成处理，点击查看'
          : 'Photo 3 is ready. Tap to view.',
      'deepLink': captureReadyDeepLink('p1', 'c1'),
    });
  });

  test('initialize delivers a pending tap from the host', () async {
    String? tapped;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('sitemark.system.ohos'),
      (call) async {
        expect(call.method, 'takePendingNotificationTap');
        return '/projects/p1/captures/c1';
      },
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('sitemark.system.ohos'),
        null,
      );
    });

    await OhosCompletionNotificationService().initialize((deepLink) {
      tapped = deepLink;
    });
    expect(tapped, '/projects/p1/captures/c1');
  });

  test('notificationTap from the host reaches initialize', () async {
    String? tapped;
    final service = OhosCompletionNotificationService();
    await service.initialize((deepLink) {
      tapped = deepLink;
    });

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      'sitemark.system.ohos',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('notificationTap', '/projects/p1/captures/c1'),
      ),
      (_) {},
    );

    expect(tapped, '/projects/p1/captures/c1');
  });

  test('OhosExternalLinkService maps missing plugin to ohos_not_ready', () async {
    final service = OhosExternalLinkService();
    await expectLater(
      service.open(Uri.parse('https://github.com/WikG1018/site-mark')),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'ohos_not_ready',
        ),
      ),
    );
  });

  test('OhosExternalLinkService invokes openLink with https url', () async {
    const channel = MethodChannel('sitemark.system.ohos');
    String? method;
    Object? arguments;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          method = call.method;
          arguments = call.arguments;
          return true;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    expect(
      await OhosExternalLinkService().open(
        Uri.parse('https://github.com/WikG1018/site-mark'),
      ),
      isTrue,
    );
    expect(method, 'openLink');
    expect(arguments, {
      'url': 'https://github.com/WikG1018/site-mark',
    });
  });

  test(
    'OhosExternalLinkService rejects non-http schemes without the channel',
    () async {
      var invoked = false;
      const channel = MethodChannel('sitemark.system.ohos');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            invoked = true;
            return true;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      expect(
        await OhosExternalLinkService().open(Uri.parse('mailto:a@b.c')),
        isFalse,
      );
      expect(invoked, isFalse);
    },
  );

  test('OhosPlatformServices launchCamera decodes captured sandbox path', () async {
    const channel = MethodChannel('sitemark.system.ohos');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'launchCamera');
          expect(call.arguments, {'captureId': 'capture-1'});
          return <String, Object?>{
            'outcome': 0,
            'outputPath': '/data/storage/el2/base/files/originals/capture-1.jpg',
            'errorMessage': null,
          };
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final result = await OhosPlatformServices().launchCamera('capture-1');
    expect(result.outcome, CameraOutcome.captured);
    expect(
      result.outputPath,
      '/data/storage/el2/base/files/originals/capture-1.jpg',
    );
    expect(result.errorMessage, isNull);
  });

  test('OhosPlatformServices launchCamera decodes cancelled', () async {
    const channel = MethodChannel('sitemark.system.ohos');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return <String, Object?>{
            'outcome': 1,
            'outputPath': '/data/storage/el2/base/files/originals/capture-1.jpg',
            'errorMessage': null,
          };
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final result = await OhosPlatformServices().launchCamera('capture-1');
    expect(result.outcome, CameraOutcome.cancelled);
  });
}
