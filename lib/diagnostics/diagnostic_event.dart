import 'dart:convert';

enum DiagnosticCategory {
  app,
  camera,
  processing,
  backup,
  restore,
  deletion,
  permission,
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
  });

  final DateTime timestamp;
  final DiagnosticCategory category;
  final DiagnosticOutcome outcome;
  final DiagnosticCode code;
  final int? durationMs;
  final int? count;
  final int? retryCount;

  Map<String, Object> toJson() => {
    'timestamp': timestamp.toUtc().toIso8601String(),
    'category': category.name,
    'outcome': outcome.name,
    'code': code.name,
    'duration_ms': ?durationMs,
    'count': ?count,
    'retry_count': ?retryCount,
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
      );
    } catch (_) {
      return null;
    }
  }
}
