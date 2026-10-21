import 'dart:convert';

enum DiagnosticCategory {
  app,
  camera,
  processing,
  backup,
  restore,
  deletion,
  permission,
  nas,
}

enum DiagnosticOutcome { success, cancelled, blocked, failed }

enum DiagnosticCode {
  none,
  noCompletedRecords,
  processingInProgress,
  failedRecordsOmitted,
  insufficientStorage,
  invalidArchive,
  permissionDenied,
  platformUnavailable,
  unexpected,
  originalMissing,
  originalModified,
  invalidImage,
  imageTooLarge,
  unsupportedImageFormat,
  localIo,
  invalidRenderRequest,
}

enum DiagnosticStage {
  evidence,
  originalHash,
  rendering,
  publishing,
  commit,
  worker,
}

enum DiagnosticImageFormat {
  jpeg,
  png,
  heif,
  avif,
  webp,
  gif,
  unknown,
  empty,
  missing,
  unreadable,
}

class DiagnosticEvent {
  const DiagnosticEvent({
    required this.timestamp,
    required this.category,
    required this.outcome,
    this.code = DiagnosticCode.none,
    this.durationMs,
    this.count,
    this.retryCount,
    this.stage,
    this.sourceFormat,
    this.sourceSizeBytes,
  });

  final DateTime timestamp;
  final DiagnosticCategory category;
  final DiagnosticOutcome outcome;
  final DiagnosticCode code;
  final int? durationMs;
  final int? count;
  final int? retryCount;
  final DiagnosticStage? stage;
  final DiagnosticImageFormat? sourceFormat;
  final int? sourceSizeBytes;

  Map<String, Object> toJson() => {
    'timestamp': timestamp.toUtc().toIso8601String(),
    'category': category.name,
    'outcome': outcome.name,
    'code': code.name,
    'duration_ms': ?durationMs,
    'count': ?count,
    'retry_count': ?retryCount,
    'stage': ?stage?.name,
    'source_format': ?sourceFormat?.name,
    'source_size_bytes': ?sourceSizeBytes,
  };

  String encode() => jsonEncode(toJson());

  static DiagnosticEvent? tryDecode(String line) {
    try {
      final value = jsonDecode(line) as Map<String, dynamic>;
      return DiagnosticEvent(
        timestamp: DateTime.parse(value['timestamp'] as String),
        category: DiagnosticCategory.values.byName(value['category'] as String),
        outcome: DiagnosticOutcome.values.byName(value['outcome'] as String),
        code: DiagnosticCode.values.byName(value['code'] as String),
        durationMs: value['duration_ms'] as int?,
        count: value['count'] as int?,
        retryCount: value['retry_count'] as int?,
        stage: value['stage'] == null
            ? null
            : DiagnosticStage.values.byName(value['stage'] as String),
        sourceFormat: value['source_format'] == null
            ? null
            : DiagnosticImageFormat.values.byName(
                value['source_format'] as String,
              ),
        sourceSizeBytes: value['source_size_bytes'] as int?,
      );
    } catch (_) {
      return null;
    }
  }
}
