import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sitemark/domain/release_check.dart';
import 'package:sitemark_system_api/sitemark_system_api.dart';

enum AppUpdatePhase {
  idle,
  downloading,
  verifying,
  ready,
  installing,
  permissionRequired,
  failed,
  cancelled,
}

enum AppUpdateFailure { network, integrity, storage, installation }

class UpdateCancellation {
  bool cancelled = false;
  VoidCallback? close;
  void cancel() {
    cancelled = true;
    close?.call();
  }

  void check() {
    if (cancelled) throw const _UpdateCancelled();
  }
}

class _UpdateCancelled implements Exception {
  const _UpdateCancelled();
}

class _IntegrityFailure implements Exception {
  const _IntegrityFailure();
}

class UpdateTransfer {
  const UpdateTransfer({
    required this.bytes,
    required this.contentLength,
    required this.close,
  });
  final Stream<List<int>> bytes;
  final int contentLength;
  final VoidCallback close;
}

typedef UpdateTransport =
    Future<UpdateTransfer> Function(Uri uri, UpdateCancellation cancellation);
typedef UpdateInstaller =
    Future<ApkInstallOutcome> Function(
      String path,
      String sha256,
      String version,
    );

final appUpdateControllerProvider = Provider<AppUpdateController>((ref) {
  final controller = AppUpdateController();
  ref.onDispose(controller.dispose);
  return controller;
});

/// Kept by the app-level provider, not by About's route. The process can be
/// suspended by Android; partial files are never offered to the installer.
class AppUpdateController extends ChangeNotifier {
  AppUpdateController({
    UpdateTransport? transport,
    Future<Directory> Function()? directory,
    UpdateInstaller? installer,
    Future<void> Function()? openPermissionSettings,
  }) : _transport = transport ?? openUpdateTransfer,
       _directory = directory ?? _updateDirectory,
       _installer = installer ?? AppUpdateApi().openInstaller,
       _openPermissionSettings =
           openPermissionSettings ??
           AppUpdateApi().openInstallPermissionSettings;

  final UpdateTransport _transport;
  final Future<Directory> Function() _directory;
  final UpdateInstaller _installer;
  final Future<void> Function() _openPermissionSettings;
  AppUpdatePhase phase = AppUpdatePhase.idle;
  AppUpdateFailure? failure;
  ReleaseDownload? download;
  int receivedBytes = 0;
  String? readyPath;
  UpdateCancellation? _cancellation;
  int _generation = 0;
  bool _disposed = false;
  Completer<void>? _finished;

  bool get busy =>
      phase == AppUpdatePhase.downloading ||
      phase == AppUpdatePhase.verifying ||
      phase == AppUpdatePhase.installing;
  double? get progress => download == null
      ? null
      : (receivedBytes / download!.sizeBytes).clamp(0, 1);
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start(ReleaseDownload asset, ReleaseCheckMode mode) async {
    if (busy || _disposed) return;
    final previous = _finished?.future;
    final finished = Completer<void>();
    _finished = finished;
    final generation = ++_generation;
    final cancellation = UpdateCancellation();
    _cancellation = cancellation;
    download = asset;
    readyPath = null;
    receivedBytes = 0;
    failure = null;
    phase = AppUpdatePhase.downloading;
    _notify();
    File? partial;
    try {
      // A cancelled stream must close its file before a retry can clean
      // partials. Generation checks alone do not protect filesystem writes.
      if (previous != null) await previous;
      cancellation.check();
      if (!RegExp(r'^v\d+\.\d+\.\d+$').hasMatch(asset.tag) ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(asset.sha256) ||
          asset.sizeBytes <= 0 ||
          asset.sizeBytes > 200 * 1024 * 1024) {
        throw const _IntegrityFailure();
      }
      final directory = await _directory();
      cancellation.check();
      await directory.create(recursive: true);
      // Only our interrupted downloads are removed. Photos and unrelated
      // cache files are outside this dedicated directory.
      await for (final file in directory.list(followLinks: false)) {
        if (file is File && file.path.endsWith('.part')) await file.delete();
      }
      cancellation.check();
      partial = File('${directory.path}/${asset.fileName}.$generation.part');
      final official = asset.officialUri;
      final mirror = Uri.parse('$apiMirrorPrefix/$official');
      final candidates = switch (mode) {
        ReleaseCheckMode.official => [official],
        ReleaseCheckMode.mirror => [mirror, official],
        ReleaseCheckMode.auto => [official, mirror],
      };
      Object? lastError;
      for (final uri in candidates) {
        cancellation.check();
        UpdateTransfer? transfer;
        IOSink? fileSink;
        try {
          transfer = await _transport(uri, cancellation);
          cancellation.check();
          if (transfer.contentLength >= 0 &&
              transfer.contentLength != asset.sizeBytes) {
            throw const _IntegrityFailure();
          }
          fileSink = partial.openWrite();
          // Attach the error listener immediately so storage failure cannot
          // escape while the HTTP stream is still waiting for its next chunk.
          Object? writeError;
          final sinkDone = fileSink.done.catchError((Object error) {
            writeError = error;
          });
          final digestResult = _DigestSink();
          final digest = crypto.sha256.startChunkedConversion(digestResult);
          receivedBytes = 0;
          final refresh = Stopwatch()..start();
          await for (final chunk in transfer.bytes) {
            cancellation.check();
            if (writeError != null) throw writeError!;
            receivedBytes += chunk.length;
            if (receivedBytes > asset.sizeBytes) {
              throw const _IntegrityFailure();
            }
            fileSink.add(chunk);
            digest.add(chunk);
            if (refresh.elapsedMilliseconds >= 100) {
              _notify();
              refresh.reset();
            }
          }
          await fileSink.flush();
          await fileSink.close();
          await sinkDone;
          fileSink = null;
          if (writeError != null) throw writeError!;
          cancellation.check();
          phase = AppUpdatePhase.verifying;
          _notify();
          digest.close();
          if (receivedBytes != asset.sizeBytes ||
              digestResult.value.toString() != asset.sha256) {
            throw const _IntegrityFailure();
          }
          final target = File('${directory.path}/${asset.fileName}');
          if (await target.exists()) await target.delete();
          cancellation.check();
          await partial.rename(target.path);
          // Keep just this verified update; never accumulate APKs from
          // earlier versions or touch any photo/export directory.
          await for (final old in directory.list(followLinks: false)) {
            if (old is File &&
                old.uri.pathSegments.last != asset.fileName &&
                RegExp(
                  r'sitemark-v\d+\.\d+\.\d+-(arm64|universal)\.apk$',
                ).hasMatch(old.path)) {
              try {
                await old.delete();
              } catch (_) {}
            }
          }
          cancellation.check();
          readyPath = target.path;
          phase = AppUpdatePhase.ready;
          _notify();
          return;
        } on _IntegrityFailure {
          rethrow;
        } on _UpdateCancelled {
          rethrow;
        } on FileSystemException {
          rethrow;
        } catch (error) {
          lastError = error;
        } finally {
          transfer?.close();
          if (fileSink != null) {
            try {
              await fileSink.close();
            } catch (_) {}
          }
        }
      }
      throw lastError ?? const SocketException('unavailable');
    } on _UpdateCancelled {
      // cancel() already exposes the final state; do not overwrite a new run.
    } catch (error) {
      if (generation == _generation && !_disposed) {
        failure = error is _IntegrityFailure
            ? AppUpdateFailure.integrity
            : error is FileSystemException
            ? AppUpdateFailure.storage
            : AppUpdateFailure.network;
        phase = AppUpdatePhase.failed;
        _notify();
      }
    } finally {
      if (partial != null) {
        try {
          if (await partial.exists()) await partial.delete();
        } catch (_) {}
      }
      if (generation == _generation) _cancellation = null;
      finished.complete();
      if (identical(_finished, finished)) _finished = null;
    }
  }

  void cancel() {
    if (phase != AppUpdatePhase.downloading &&
        phase != AppUpdatePhase.verifying) {
      return;
    }
    ++_generation;
    _cancellation?.cancel();
    phase = AppUpdatePhase.cancelled;
    _notify();
  }

  Future<void> install() async {
    final asset = download;
    final path = readyPath;
    if (_disposed || busy || asset == null || path == null) return;
    phase = AppUpdatePhase.installing;
    failure = null;
    _notify();
    try {
      final outcome = await _installer(
        path,
        asset.sha256,
        asset.tag.substring(1),
      );
      if (_disposed) return;
      phase = outcome == ApkInstallOutcome.permissionRequired
          ? AppUpdatePhase.permissionRequired
          : AppUpdatePhase.ready;
    } catch (_) {
      if (_disposed) return;
      phase = AppUpdatePhase.failed;
      failure = AppUpdateFailure.installation;
    }
    _notify();
  }

  Future<void> openPermissionSettings() async {
    try {
      await _openPermissionSettings();
    } catch (_) {
      failure = AppUpdateFailure.installation;
      phase = AppUpdatePhase.failed;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cancellation?.cancel();
    super.dispose();
  }
}

Future<Directory> _updateDirectory() async =>
    Directory('${(await getTemporaryDirectory()).path}/sitemark-updates');

class _DigestSink implements Sink<crypto.Digest> {
  crypto.Digest? value;
  @override
  void add(crypto.Digest data) {
    value = data;
  }

  @override
  void close() {}
}

bool isAllowedUpdateDownloadUri(Uri uri) =>
    uri.scheme == 'https' &&
    uri.userInfo.isEmpty &&
    (uri.port == 443) &&
    const {
      'github.com',
      'release-assets.githubusercontent.com',
      'objects.githubusercontent.com',
      'gh-proxy.com',
    }.contains(uri.host);

Future<UpdateTransfer> openUpdateTransfer(
  Uri uri,
  UpdateCancellation cancellation,
) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  cancellation.close = () => client.close(force: true);
  try {
    var current = uri;
    for (var redirects = 0; redirects <= 5; redirects++) {
      cancellation.check();
      if (!isAllowedUpdateDownloadUri(current)) {
        throw const HttpException('invalid_redirect');
      }
      final request = await client
          .getUrl(current)
          .timeout(const Duration(seconds: 20));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.userAgentHeader, releaseCheckUserAgent);
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.isRedirect) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null) throw const HttpException('missing_redirect');
        current = current.resolve(location);
        await response.drain<void>().timeout(const Duration(seconds: 20));
        continue;
      }
      if (response.statusCode != HttpStatus.ok) {
        throw const HttpException('download_unavailable');
      }
      return UpdateTransfer(
        bytes: response.timeout(const Duration(seconds: 30)),
        contentLength: response.contentLength,
        close: () => client.close(force: true),
      );
    }
    throw const HttpException('too_many_redirects');
  } catch (_) {
    client.close(force: true);
    rethrow;
  }
}
