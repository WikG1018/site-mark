import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sitemark/diagnostics/diagnostic_event.dart';
import 'package:sitemark/diagnostics/diagnostic_event_store.dart';
import 'package:sitemark/diagnostics/diagnostic_recorder.dart';
import 'package:sitemark/platform/platform_services.dart';

/// The serial capture worker owns a separate log so foreground diagnostics
/// cannot overwrite its events while rewriting their own bounded log.
DiagnosticEventStore captureProcessingDiagnosticStore(Directory support) =>
    DiagnosticEventStore(
      maxBytes: 1024 * 1024,
      directory: Directory(
        '${support.path}${Platform.pathSeparator}diagnostics'
        '${Platform.pathSeparator}processing',
      ),
    );

CaptureProcessingDiagnostics createCaptureProcessingDiagnostics() =>
    const CaptureProcessingDiagnostics.local();

class CaptureProcessingDiagnostics {
  const CaptureProcessingDiagnostics(this._recorder);

  /// Resolve platform storage only when recording, inside the guarded path.
  /// An unavailable plugin must not create an unhandled future on successful
  /// capture runs that never need to record a diagnostic.
  const CaptureProcessingDiagnostics.local() : _recorder = null;

  final DiagnosticRecorder? _recorder;

  Future<void> failed({
    required DiagnosticStage stage,
    required Object error,
    String? sourcePath,
    int? attempts,
    DiagnosticCode? code,
  }) async {
    // Never persist the exception, filename, image bytes or capture identity.
    // Only a fixed vocabulary and numeric file size leave this method.
    try {
      final source = sourcePath == null
          ? null
          : await _inspectSource(sourcePath);
      final recorder =
          _recorder ??
          DiagnosticRecorder(
            captureProcessingDiagnosticStore(
              await getApplicationSupportDirectory(),
            ),
          );
      await recorder.recordAndFlush(
        DiagnosticEvent(
          timestamp: DateTime.now().toUtc(),
          category: DiagnosticCategory.processing,
          outcome: DiagnosticOutcome.failed,
          code: code ?? _classify(error),
          stage: stage,
          retryCount: attempts == null ? null : attempts - 1,
          sourceFormat: source?.format,
          sourceSizeBytes: source?.size,
        ),
      );
    } catch (_) {
      // Diagnostics must not prevent marking the record failed or retrying it.
    }
  }

  DiagnosticCode _classify(Object error) {
    if (error is PathNotFoundException) return DiagnosticCode.originalMissing;
    if (error is ImagePipelineException) {
      switch (error.kind) {
        case ImagePipelineFailureKind.notFound:
          return DiagnosticCode.originalMissing;
        case ImagePipelineFailureKind.transientIo:
          return DiagnosticCode.localIo;
        case ImagePipelineFailureKind.invalidData:
          if (error.message.trimLeft().startsWith('validate render request:')) {
            return DiagnosticCode.invalidRenderRequest;
          }
          if (error.message.contains('megapixel limit') ||
              error.message.contains('edge limit')) {
            return DiagnosticCode.imageTooLarge;
          }
          if (error.message.contains('unsupported image format') ||
              error.message.contains('unable to detect image format')) {
            return DiagnosticCode.unsupportedImageFormat;
          }
          return DiagnosticCode.invalidImage;
      }
    }
    if (error is FileSystemException || error is OSError) {
      return DiagnosticCode.localIo;
    }
    if (error is PlatformException || error is MissingPluginException) {
      return DiagnosticCode.platformUnavailable;
    }
    return DiagnosticCode.unexpected;
  }

  Future<({DiagnosticImageFormat format, int? size})> _inspectSource(
    String path,
  ) async {
    RandomAccessFile? handle;
    try {
      handle = await File(path).open();
      final size = await handle.length();
      final header = await handle.read(12);
      return (format: _format(header), size: size);
    } on PathNotFoundException {
      return (format: DiagnosticImageFormat.missing, size: null);
    } catch (_) {
      return (format: DiagnosticImageFormat.unreadable, size: null);
    } finally {
      try {
        await handle?.close();
      } catch (_) {}
    }
  }

  DiagnosticImageFormat _format(List<int> header) {
    bool starts(List<int> prefix, [int offset = 0]) =>
        header.length >= offset + prefix.length &&
        List.generate(
          prefix.length,
          (i) => i,
        ).every((i) => header[offset + i] == prefix[i]);
    if (header.isEmpty) return DiagnosticImageFormat.empty;
    if (starts([0xff, 0xd8, 0xff])) return DiagnosticImageFormat.jpeg;
    if (starts([0x89, 0x50, 0x4e, 0x47, 13, 10, 26, 10])) {
      return DiagnosticImageFormat.png;
    }
    if (starts('GIF87a'.codeUnits) || starts('GIF89a'.codeUnits)) {
      return DiagnosticImageFormat.gif;
    }
    if (starts('RIFF'.codeUnits) && starts('WEBP'.codeUnits, 8)) {
      return DiagnosticImageFormat.webp;
    }
    if (starts('ftyp'.codeUnits, 4)) {
      if (['avif', 'avis'].any((brand) => starts(brand.codeUnits, 8))) {
        return DiagnosticImageFormat.avif;
      }
      if ([
        'heic',
        'heix',
        'hevc',
        'hevx',
        'mif1',
        'msf1',
      ].any((brand) => starts(brand.codeUnits, 8))) {
        return DiagnosticImageFormat.heif;
      }
    }
    return DiagnosticImageFormat.unknown;
  }
}
