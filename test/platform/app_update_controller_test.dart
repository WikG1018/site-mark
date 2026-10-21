import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/domain/release_check.dart';
import 'package:sitemark/platform/app_update_controller.dart';
import 'package:sitemark_system_api/sitemark_system_api.dart';

void main() {
  late Directory directory;
  final bytes = List.generate(256, (index) => index);
  late ReleaseDownload asset;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sitemark-update-test-');
    asset = ReleaseDownload(
      tag: 'v1.0.32',
      variant: ReleaseApkVariant.arm64,
      sizeBytes: bytes.length,
      sha256: sha256.convert(bytes).toString(),
    );
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  AppUpdateController controller({
    UpdateTransport? transport,
    UpdateInstaller? installer,
  }) => AppUpdateController(
    directory: () async => directory,
    transport:
        transport ??
        (_, _) async => UpdateTransfer(
          bytes: Stream.value(bytes),
          contentLength: bytes.length,
          close: () {},
        ),
    installer: installer ?? (_, _, _) async => ApkInstallOutcome.launched,
  );

  test(
    'download verifies exact bytes and passes identity to installer',
    () async {
      final calls = <String>[];
      final c = controller(
        installer: (path, digest, version) async {
          calls.add('$digest $version');
          expect(await File(path).readAsBytes(), bytes);
          return ApkInstallOutcome.launched;
        },
      );
      addTearDown(c.dispose);
      final old = File('${directory.path}/sitemark-v1.0.30-arm64.apk');
      await old.writeAsBytes([1]);
      await c.start(asset, ReleaseCheckMode.official);
      expect(c.phase, AppUpdatePhase.ready);
      expect(c.progress, 1);
      expect(await File(c.readyPath!).exists(), isTrue);
      expect(await old.exists(), isFalse);
      await c.install();
      expect(c.phase, AppUpdatePhase.ready);
      expect(calls, ['${asset.sha256} 1.0.32']);
      expect(
        directory.listSync().where((f) => f.path.endsWith('.part')),
        isEmpty,
      );
    },
  );

  test('truncated or altered bytes never become installable', () async {
    for (final bad in [bytes.sublist(0, 255), List.filled(256, 1)]) {
      final c = controller(
        transport: (_, _) async => UpdateTransfer(
          bytes: Stream.value(bad),
          contentLength: -1,
          close: () {},
        ),
      );
      await c.start(asset, ReleaseCheckMode.official);
      expect(c.phase, AppUpdatePhase.failed);
      expect(c.failure, AppUpdateFailure.integrity);
      expect(c.readyPath, isNull);
      expect(directory.listSync(), isEmpty);
      c.dispose();
    }
  });

  test('automatic mode falls back without sending any private data', () async {
    final calls = <Uri>[];
    final c = controller(
      transport: (uri, _) async {
        calls.add(uri);
        if (calls.length == 1) throw const SocketException('offline');
        return UpdateTransfer(
          bytes: Stream.value(bytes),
          contentLength: bytes.length,
          close: () {},
        );
      },
    );
    addTearDown(c.dispose);
    await c.start(asset, ReleaseCheckMode.auto);
    expect(c.phase, AppUpdatePhase.ready);
    expect(calls.map((uri) => uri.host), ['github.com', 'gh-proxy.com']);
  });

  test('official mode never uses a mirror', () async {
    var calls = 0;
    final c = controller(
      transport: (_, _) async {
        calls++;
        throw const SocketException('offline');
      },
    );
    addTearDown(c.dispose);
    await c.start(asset, ReleaseCheckMode.official);
    expect(c.failure, AppUpdateFailure.network);
    expect(calls, 1);
  });

  test('cancelled run cannot delete a successful immediate retry', () async {
    final started = Completer<void>();
    final stream = StreamController<List<int>>();
    var calls = 0;
    final c = controller(
      transport: (_, token) async {
        if (++calls == 1) {
          token.close = () {
            unawaited(stream.close());
          };
          started.complete();
          return UpdateTransfer(
            bytes: stream.stream,
            contentLength: bytes.length,
            close: () {},
          );
        }
        return UpdateTransfer(
          bytes: Stream.value(bytes),
          contentLength: bytes.length,
          close: () {},
        );
      },
    );
    addTearDown(c.dispose);
    final first = c.start(asset, ReleaseCheckMode.official);
    await started.future;
    // Allow the consumer to attach before closing the test stream.
    await Future<void>.delayed(Duration.zero);
    c.cancel();
    final retry = c.start(asset, ReleaseCheckMode.official);
    await Future.wait([first, retry]);
    expect(c.phase, AppUpdatePhase.ready);
    expect(await File(c.readyPath!).readAsBytes(), bytes);
  });

  test(
    'installer permission is explicit and denied installation keeps package',
    () async {
      final c = controller(
        installer: (_, _, _) async => ApkInstallOutcome.permissionRequired,
      );
      addTearDown(c.dispose);
      await c.start(asset, ReleaseCheckMode.official);
      await c.install();
      expect(c.phase, AppUpdatePhase.permissionRequired);
      expect(await File(c.readyPath!).exists(), isTrue);
    },
  );

  test('redirects cannot leave the fixed HTTPS download hosts', () {
    expect(
      isAllowedUpdateDownloadUri(
        Uri.parse(
          'https://release-assets.githubusercontent.com/path?signature=x',
        ),
      ),
      isTrue,
    );
    for (final bad in [
      'http://github.com/a',
      'https://github.com.evil.test/a',
      'https://user@github.com/a',
      'https://127.0.0.1/a',
      'https://gh-proxy.com:8443/a',
    ]) {
      expect(isAllowedUpdateDownloadUri(Uri.parse(bad)), isFalse);
    }
  });
}
