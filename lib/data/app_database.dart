import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:sitemark/data/conditional_polling_stream.dart';
import 'package:sitemark/domain/capture_filter.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/domain/photo_number.dart';
import 'package:sitemark/domain/project_name.dart';

part 'app_database.g.dart';

class CaptureStatusConverter extends TypeConverter<CaptureStatus, String> {
  const CaptureStatusConverter();

  @override
  CaptureStatus fromSql(String fromDb) => CaptureStatus.values.byName(fromDb);

  @override
  String toSql(CaptureStatus value) => value.name;
}

class Projects extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get description => text().nullable()();
  TextColumn get watermarkPosition =>
      text().withDefault(const Constant('bottomLeft'))();
  RealColumn get watermarkOpacity => real().withDefault(const Constant(0.78))();
  IntColumn get watermarkAccentColorArgb =>
      integer().withDefault(const Constant(0xff37c58b))();
  RealColumn get watermarkFontScale =>
      real().withDefault(const Constant(1.0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Application-wide settings stored as a singleton row with id `'global'`.
@DataClassName('AppSetting')
class AppSettings extends Table {
  TextColumn get id => text().withDefault(const Constant('global'))();
  TextColumn get themeMode => text().withDefault(const Constant('system'))();
  TextColumn get localeCode => text().nullable()();
  TextColumn get defaultWatermarkPosition =>
      text().withDefault(const Constant('bottomLeft'))();
  RealColumn get defaultWatermarkOpacity =>
      real().withDefault(const Constant(0.78))();
  IntColumn get defaultWatermarkAccentColorArgb =>
      integer().withDefault(const Constant(0xff37c58b))();
  RealColumn get defaultWatermarkFontScale =>
      real().withDefault(const Constant(1.0))();
  BoolColumn get locationPermissionPromptDismissed =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get useDynamicColor =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get completionNotificationsEnabled =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('CaptureRecord')
class CaptureRecords extends Table {
  @override
  String get tableName => 'captures';

  TextColumn get id => text()();
  TextColumn get projectId =>
      text().references(Projects, #id, onDelete: KeyAction.cascade)();
  TextColumn get photoNumber => text().nullable()();
  TextColumn get workLocation => text().withLength(min: 1, max: 160)();
  TextColumn get workContent => text().withLength(min: 1, max: 240)();
  TextColumn get photographer => text().withLength(min: 1, max: 80)();
  TextColumn get notes => text().nullable()();
  TextColumn get originalPath => text()();
  TextColumn get publishedUri => text().nullable()();
  TextColumn get originalSha256 => text().nullable()();
  TextColumn get status => text().map(const CaptureStatusConverter())();
  TextColumn get failureReason => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get capturedAt => dateTime().nullable()();
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  RealColumn get accuracyMeters => real().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get locationOutcome => text().nullable()();
  IntColumn get processingAttempts =>
      integer().withDefault(const Constant(0))();
  TextColumn get watermarkLocaleCode =>
      text().withDefault(const Constant('zh'))();
  TextColumn get locationResolution =>
      text().withDefault(const Constant('resolved'))();
  DateTimeColumn get originalDeletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [Projects, CaptureRecords, AppSettings])
class AppDatabase extends _$AppDatabase {
  static const _defaultExternalRefreshInterval = Duration(seconds: 1);

  final Duration externalRefreshInterval;

  AppDatabase({this.externalRefreshInterval = _defaultExternalRefreshInterval})
    : super(
        driftDatabase(
          name: 'sitemark',
          native: const DriftNativeOptions(shareAcrossIsolates: true),
        ),
      );

  AppDatabase.forTesting(
    super.executor, {
    this.externalRefreshInterval = _defaultExternalRefreshInterval,
  });

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      await _createCaptureIndexes();
    },
    onUpgrade: (migrator, from, to) async {
      // When migrating from v2 directly to v4+, migrator.createTable creates
      // `app_settings` with the *current* schema. The addColumn calls for that
      // table must therefore be skipped when the table was just created,
      // otherwise SQLite raises "duplicate column name".
      var appSettingsJustCreated = false;
      if (from < 2) {
        await migrator.addColumn(projects, projects.watermarkPosition);
        await migrator.addColumn(projects, projects.watermarkOpacity);
        await migrator.addColumn(projects, projects.watermarkAccentColorArgb);
      }
      if (from < 3) {
        await migrator.createTable(appSettings);
        await migrator.addColumn(
          captureRecords,
          captureRecords.processingAttempts,
        );
        appSettingsJustCreated = true;
      }
      if (from < 4) {
        await migrator.addColumn(projects, projects.watermarkFontScale);
        if (!appSettingsJustCreated) {
          await migrator.addColumn(
            appSettings,
            appSettings.defaultWatermarkFontScale,
          );
          await migrator.addColumn(
            appSettings,
            appSettings.locationPermissionPromptDismissed,
          );
        }
        await migrator.addColumn(
          captureRecords,
          captureRecords.watermarkLocaleCode,
        );
        await migrator.addColumn(
          captureRecords,
          captureRecords.locationResolution,
        );
        await migrator.addColumn(
          captureRecords,
          captureRecords.originalDeletedAt,
        );
      }
      if (from < 5 && !appSettingsJustCreated) {
        await migrator.addColumn(appSettings, appSettings.useDynamicColor);
        await migrator.addColumn(
          appSettings,
          appSettings.completionNotificationsEnabled,
        );
      }
      if (from < 6) {
        // Performance indexes from the smoothness branch. Uses
        // `CREATE INDEX IF NOT EXISTS` so users who already have the indexes
        // (e.g. from the perf branch) do not error out, and fresh installs
        // that jumped straight to v6 via `onCreate` are also covered.
        await _createCaptureIndexes();
        // The perf/smoothness branch shipped a v5 schema that created these
        // indexes but did NOT add the `use_dynamic_color` and
        // `completion_notifications_enabled` columns on `app_settings`. A user
        // on that branch therefore has `user_version = 5` without the two
        // columns, so the `from < 5` branch above is skipped and
        // `_ensureGlobalSettingsRow()` would crash with "no column named
        // use_dynamic_color". Detect the missing columns via
        // `PRAGMA table_info` and add them on demand so both v5 lineages
        // converge at v6.
        await _ensureDynamicColorColumns();
      }
      await _ensureGlobalSettingsRow();
    },
    beforeOpen: (details) async {
      await _ensureGlobalSettingsRow();
    },
  );

  /// Inserts the default `global` settings row if it does not already exist.
  ///
  /// Uses `INSERT OR IGNORE` semantics so existing settings (including those
  /// carried across a v2 -> v3 upgrade) are never overwritten.
  Future<void> _ensureGlobalSettingsRow() async {
    final now = DateTime.now();
    await into(appSettings).insert(
      AppSettingsCompanion.insert(
        id: const Value('global'),
        themeMode: const Value('system'),
        defaultWatermarkPosition: const Value('bottomLeft'),
        defaultWatermarkOpacity: const Value(0.78),
        defaultWatermarkAccentColorArgb: const Value(0xff37c58b),
        defaultWatermarkFontScale: const Value(1.0),
        locationPermissionPromptDismissed: const Value(false),
        useDynamicColor: const Value(false),
        completionNotificationsEnabled: const Value(false),
        updatedAt: now,
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }

  /// Creates the SQLite indexes that back the capture-list queries.
  ///
  /// All statements use `CREATE INDEX IF NOT EXISTS` so this is safe to call
  /// both from `onCreate` (fresh install) and the v6 migration step (upgrade
  /// from any prior version), and idempotent for users who already have the
  /// indexes from the perf branch.
  Future<void> _createCaptureIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS capture_records_status_idx ON captures (status)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS capture_records_sort_idx '
      'ON captures (COALESCE(captured_at, created_at) DESC)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS capture_records_project_sort_idx '
      'ON captures (project_id, COALESCE(captured_at, created_at) DESC)',
    );
  }

  /// Adds the `use_dynamic_color` and `completion_notifications_enabled`
  /// columns to `app_settings` if they are missing.
  ///
  /// This is called from the v6 migration step to converge users who arrive
  /// from the perf/smoothness branch's v5 schema (which has the capture
  /// indexes but not these two columns). Uses `PRAGMA table_info` so the
  /// operation is idempotent and never raises "duplicate column name". The
  /// `ALTER TABLE` statements mirror what `migrator.addColumn` would emit,
  /// but `migrator` is only in scope inside the `MigrationStrategy` callback,
  /// so we issue the DDL directly.
  Future<void> _ensureDynamicColorColumns() async {
    final columns = await customSelect(
      'PRAGMA table_info(app_settings)',
    ).get();
    final columnNames = columns.map((row) => row.read<String>('name')).toSet();
    if (!columnNames.contains('use_dynamic_color')) {
      await customStatement(
        'ALTER TABLE app_settings ADD COLUMN use_dynamic_color '
        'INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!columnNames.contains('completion_notifications_enabled')) {
      await customStatement(
        'ALTER TABLE app_settings ADD COLUMN '
        'completion_notifications_enabled INTEGER NOT NULL DEFAULT 0',
      );
    }
  }

  Future<Project> createProject({
    required String id,
    required String name,
    String? description,
    String? watermarkPosition,
    double? watermarkOpacity,
    int? watermarkAccentColorArgb,
    double? watermarkFontScale,
    DateTime? createdAt,
  }) async {
    final timestamp = createdAt ?? DateTime.now();
    final trimmedName = name.trim();
    return transaction(() async {
      final existingProjects = await select(projects).get();
      final displayKey = normalizedProjectNameKey(trimmedName);
      final safeKey = safeProjectFileNameKey(trimmedName);
      for (final existing in existingProjects) {
        if (normalizedProjectNameKey(existing.name) == displayKey) {
          throw const ProjectNameConflictException(
            ProjectNameConflictKind.displayName,
          );
        }
        if (safeProjectFileNameKey(existing.name) == safeKey) {
          throw const ProjectNameConflictException(
            ProjectNameConflictKind.safeFileName,
          );
        }
      }
      return into(projects).insertReturning(
        ProjectsCompanion.insert(
          id: id,
          name: trimmedName,
          description: Value(description?.trim()),
          watermarkPosition: watermarkPosition == null
              ? const Value.absent()
              : Value(watermarkPosition),
          watermarkOpacity: watermarkOpacity == null
              ? const Value.absent()
              : Value(watermarkOpacity),
          watermarkAccentColorArgb: watermarkAccentColorArgb == null
              ? const Value.absent()
              : Value(watermarkAccentColorArgb),
          watermarkFontScale: watermarkFontScale == null
              ? const Value.absent()
              : Value(_validatedFontScale(watermarkFontScale)),
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      );
    });
  }

  Stream<List<Project>> watchProjects() {
    return (select(
      projects,
    )..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])).watch();
  }

  /// One-shot read of all projects newest-first. Use this instead of
  /// `watchProjects().first` in widget tests, because the watch stream's
  /// stream-store timers do not fire under `FakeAsync` until frames are pumped.
  Future<List<Project>> getProjects() {
    return (select(
      projects,
    )..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])).get();
  }

  Future<CaptureRecord> createPendingCapture({
    required String id,
    required String projectId,
    required String originalPath,
    required String workLocation,
    required String workContent,
    required String photographer,
    required String watermarkLocaleCode,
    String? notes,
    DateTime? createdAt,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
    String? address,
    String? locationOutcome,
    String locationResolution = 'pending',
  }) {
    if (!{'zh', 'en'}.contains(watermarkLocaleCode)) {
      throw ArgumentError.value(watermarkLocaleCode, 'watermarkLocaleCode');
    }
    if (!{'pending', 'resolved', 'unavailable'}.contains(locationResolution)) {
      throw ArgumentError.value(locationResolution, 'locationResolution');
    }
    return into(captureRecords).insertReturning(
      CaptureRecordsCompanion.insert(
        id: id,
        projectId: projectId,
        workLocation: workLocation.trim(),
        workContent: workContent.trim(),
        photographer: photographer.trim(),
        notes: Value(notes?.trim()),
        originalPath: originalPath,
        status: CaptureStatus.pendingCamera,
        createdAt: createdAt ?? DateTime.now(),
        latitude: Value(latitude),
        longitude: Value(longitude),
        accuracyMeters: Value(accuracyMeters),
        address: Value(address),
        locationOutcome: Value(locationOutcome),
        watermarkLocaleCode: Value(watermarkLocaleCode),
        locationResolution: Value(locationResolution),
      ),
    );
  }

  Stream<List<CaptureRecord>> watchCapturesForProject(String projectId) {
    return (select(captureRecords)
          ..where((row) => row.projectId.equals(projectId))
          ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]))
        .watch();
  }

  Future<List<CaptureRecord>> capturesForProject(String projectId) {
    return (select(captureRecords)
          ..where((row) => row.projectId.equals(projectId))
          ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
        .get();
  }

  Future<Project?> projectById(String projectId) {
    return (select(
      projects,
    )..where((row) => row.id.equals(projectId))).getSingleOrNull();
  }

  Future<Project> updateProjectWatermarkSettings({
    required String projectId,
    required String position,
    required double opacity,
    required int accentColorArgb,
    required double fontScale,
  }) async {
    if (!{'bottomLeft', 'bottomRight'}.contains(position)) {
      throw ArgumentError.value(position, 'position');
    }
    if (opacity < 0.2 || opacity > 0.95) {
      throw ArgumentError.value(opacity, 'opacity');
    }
    _validatedFontScale(fontScale);
    await (update(projects)..where((row) => row.id.equals(projectId))).write(
      ProjectsCompanion(
        watermarkPosition: Value(position),
        watermarkOpacity: Value(opacity),
        watermarkAccentColorArgb: Value(accentColorArgb),
        watermarkFontScale: Value(fontScale),
        updatedAt: Value(DateTime.now()),
      ),
    );
    final project = await projectById(projectId);
    if (project == null) throw StateError('Project does not exist');
    return project;
  }

  Future<CaptureRecord?> captureById(String captureId) {
    return (select(
      captureRecords,
    )..where((row) => row.id.equals(captureId))).getSingleOrNull();
  }

  Future<int> deleteCapture(String captureId) {
    return (delete(
      captureRecords,
    )..where((row) => row.id.equals(captureId))).go();
  }

  Future<CaptureRecord> updateCaptureDescription({
    required String captureId,
    required String workLocation,
    required String workContent,
    required String photographer,
    String? notes,
  }) async {
    if ([
      workLocation,
      workContent,
      photographer,
    ].any((value) => value.trim().isEmpty)) {
      throw ArgumentError('Capture description fields must not be empty');
    }
    await (update(
      captureRecords,
    )..where((row) => row.id.equals(captureId))).write(
      CaptureRecordsCompanion(
        workLocation: Value(workLocation.trim()),
        workContent: Value(workContent.trim()),
        photographer: Value(photographer.trim()),
        notes: Value(notes?.trim()),
      ),
    );
    return (select(
      captureRecords,
    )..where((row) => row.id.equals(captureId))).getSingle();
  }

  Future<CaptureRecord> markCaptured({
    required String captureId,
    required DateTime capturedAt,
  }) {
    return transaction(() async {
      final current = await (select(
        captureRecords,
      )..where((row) => row.id.equals(captureId))).getSingle();
      if (!current.status.canTransitionTo(CaptureStatus.captured)) {
        throw StateError(
          'Cannot transition ${current.status.name} to captured',
        );
      }

      final project = await (select(
        projects,
      )..where((row) => row.id.equals(current.projectId))).getSingleOrNull();
      if (project == null) {
        throw StateError('Capture project does not exist');
      }

      final startOfDay = DateTime(
        capturedAt.year,
        capturedAt.month,
        capturedAt.day,
      );
      final endOfDay = startOfDay.add(const Duration(days: 1));
      final sameDay =
          await (select(captureRecords)..where(
                (row) =>
                    row.capturedAt.isBiggerOrEqualValue(startOfDay) &
                    row.capturedAt.isSmallerThanValue(endOfDay) &
                    row.photoNumber.isNotNull(),
              ))
              .get();
      final highestSequence = sameDay
          .map(
            (record) => int.tryParse(record.photoNumber!.split('-').last) ?? 0,
          )
          .fold(0, (highest, value) => value > highest ? value : highest);
      final number = formatPhotoNumber(
        projectName: project.name,
        capturedAt: capturedAt,
        sequence: highestSequence + 1,
      );

      await (update(
        captureRecords,
      )..where((row) => row.id.equals(captureId))).write(
        CaptureRecordsCompanion(
          status: const Value(CaptureStatus.captured),
          capturedAt: Value(capturedAt),
          photoNumber: Value(number),
        ),
      );

      return (select(
        captureRecords,
      )..where((row) => row.id.equals(captureId))).getSingle();
    });
  }

  Future<List<CaptureRecord>> pendingCameraCaptures() {
    return (select(captureRecords)
          ..where((row) => row.status.equals(CaptureStatus.pendingCamera.name))
          ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
        .get();
  }

  Future<CaptureRecord> markRendering({
    required String captureId,
    required String originalSha256,
  }) {
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(originalSha256)) {
      throw ArgumentError.value(
        originalSha256,
        'originalSha256',
        'Expected a 64-character SHA-256 digest',
      );
    }
    return _transitionCapture(
      captureId: captureId,
      target: CaptureStatus.rendering,
      companion: CaptureRecordsCompanion(
        status: const Value(CaptureStatus.rendering),
        originalSha256: Value(originalSha256.toLowerCase()),
        failureReason: const Value(null),
      ),
    );
  }

  Future<CaptureRecord> markReady({
    required String captureId,
    required String publishedUri,
  }) {
    if (publishedUri.trim().isEmpty) {
      throw ArgumentError.value(publishedUri, 'publishedUri');
    }
    return _transitionCapture(
      captureId: captureId,
      target: CaptureStatus.ready,
      companion: CaptureRecordsCompanion(
        status: const Value(CaptureStatus.ready),
        publishedUri: Value(publishedUri),
        failureReason: const Value(null),
      ),
    );
  }

  Future<CaptureRecord> markFailed({
    required String captureId,
    required String reason,
  }) {
    return _transitionCapture(
      captureId: captureId,
      target: CaptureStatus.failed,
      companion: CaptureRecordsCompanion(
        status: const Value(CaptureStatus.failed),
        failureReason: Value(reason),
      ),
    );
  }

  Future<CaptureRecord> _transitionCapture({
    required String captureId,
    required CaptureStatus target,
    required CaptureRecordsCompanion companion,
  }) {
    return transaction(() async {
      final current = await (select(
        captureRecords,
      )..where((row) => row.id.equals(captureId))).getSingle();
      if (!current.status.canTransitionTo(target)) {
        throw StateError(
          'Cannot transition ${current.status.name} to ${target.name}',
        );
      }
      await (update(
        captureRecords,
      )..where((row) => row.id.equals(captureId))).write(companion);
      return (select(
        captureRecords,
      )..where((row) => row.id.equals(captureId))).getSingle();
    });
  }

  Stream<AppSetting> watchAppSettings() {
    return (select(
      appSettings,
    )..where((row) => row.id.equals('global'))).watchSingle();
  }

  /// One-shot read of the singleton `global` settings row. Use this instead of
  /// `watchAppSettings().first` in contexts that must resolve on a single
  /// microtask (e.g. widget-test `FutureBuilder`s and form save handlers),
  /// because the watch stream's stream-store timers do not fire under
  /// `FakeAsync` until frames are pumped.
  Future<AppSetting> getAppSettings() {
    return (select(
      appSettings,
    )..where((row) => row.id.equals('global'))).getSingle();
  }

  Future<AppSetting> updateAppSettings({
    String? themeMode,
    String? localeCode,
    String? defaultWatermarkPosition,
    double? defaultWatermarkOpacity,
    int? defaultWatermarkAccentColorArgb,
    double? defaultWatermarkFontScale,
    bool? locationPermissionPromptDismissed,
    bool? useDynamicColor,
    bool? completionNotificationsEnabled,
  }) async {
    final companion = AppSettingsCompanion(
      themeMode: themeMode == null ? const Value.absent() : Value(themeMode),
      localeCode: localeCode == null
          ? const Value.absent()
          : Value(localeCode.isEmpty ? null : localeCode),
      defaultWatermarkPosition: defaultWatermarkPosition == null
          ? const Value.absent()
          : Value(defaultWatermarkPosition),
      defaultWatermarkOpacity: defaultWatermarkOpacity == null
          ? const Value.absent()
          : Value(defaultWatermarkOpacity),
      defaultWatermarkAccentColorArgb: defaultWatermarkAccentColorArgb == null
          ? const Value.absent()
          : Value(defaultWatermarkAccentColorArgb),
      defaultWatermarkFontScale: defaultWatermarkFontScale == null
          ? const Value.absent()
          : Value(_validatedFontScale(defaultWatermarkFontScale)),
      locationPermissionPromptDismissed:
          locationPermissionPromptDismissed == null
          ? const Value.absent()
          : Value(locationPermissionPromptDismissed),
      useDynamicColor: useDynamicColor == null
          ? const Value.absent()
          : Value(useDynamicColor),
      completionNotificationsEnabled: completionNotificationsEnabled == null
          ? const Value.absent()
          : Value(completionNotificationsEnabled),
      updatedAt: Value(DateTime.now()),
    );
    await (update(
      appSettings,
    )..where((row) => row.id.equals('global'))).write(companion);
    return (select(
      appSettings,
    )..where((row) => row.id.equals('global'))).getSingle();
  }

  Future<CaptureCarryForwardDraft?> latestCapturedDraft(String projectId) {
    final query = select(captureRecords)
      ..where(
        (row) =>
            row.projectId.equals(projectId) &
            row.status.equals(CaptureStatus.pendingCamera.name).not(),
      )
      ..orderBy([
        (row) => OrderingTerm(
          expression: coalesce([row.capturedAt, row.createdAt]),
          mode: OrderingMode.desc,
        ),
      ])
      ..limit(1);
    return query.map((row) => row.toCarryForwardDraft()).getSingleOrNull();
  }

  Stream<CaptureRecord?> watchCaptureById(String captureId) {
    final query = select(captureRecords)
      ..where((row) => row.id.equals(captureId));
    return watchWithConditionalPolling(
      source: query.watchSingleOrNull(),
      load: () => query.getSingleOrNull(),
      shouldPoll: (record) => record != null && _isProcessing(record.status),
      pollInterval: externalRefreshInterval,
    );
  }

  Stream<List<CaptureSummary>> watchCaptureSummaries(CaptureFilter filter) {
    final query = _captureSummarySelectable(filter);
    return watchWithConditionalPolling(
      source: query.watch(),
      load: query.get,
      shouldPoll: (rows) =>
          rows.any((summary) => _isProcessing(summary.capture.status)),
      equals: _sameCaptureSummaries,
      pollInterval: externalRefreshInterval,
    );
  }

  /// Unfiltered summary stream used to derive available filter options
  /// (projects, years, months, days) without applying the user's selection.
  Stream<List<CaptureSummary>> watchAllCaptureSummaries() {
    final query = _captureSummarySelectable(null);
    return watchWithConditionalPolling(
      source: query.watch(),
      load: query.get,
      shouldPoll: (rows) =>
          rows.any((summary) => _isProcessing(summary.capture.status)),
      equals: _sameCaptureSummaries,
      pollInterval: externalRefreshInterval,
    );
  }

  /// One-shot read used for app-private storage accounting.
  Future<List<CaptureRecord>> getAllCaptures() => select(captureRecords).get();

  bool _isProcessing(CaptureStatus status) =>
      status == CaptureStatus.captured || status == CaptureStatus.rendering;

  bool _sameCaptureSummaries(
    List<CaptureSummary> previous,
    List<CaptureSummary> next,
  ) {
    if (previous.length != next.length) return false;
    for (var index = 0; index < previous.length; index++) {
      if (previous[index].capture != next[index].capture ||
          previous[index].projectName != next[index].projectName) {
        return false;
      }
    }
    return true;
  }

  /// Returns captures in the `captured` or `rendering` states for startup
  /// reconciliation. Ordered oldest-first so pending work resumes in order.
  Future<List<CaptureRecord>> capturesAwaitingProcessing() {
    return (select(captureRecords)
          ..where(
            (row) =>
                (row.status.equals(CaptureStatus.captured.name) |
                    row.status.equals(CaptureStatus.rendering.name)) &
                row.locationResolution.equals('pending').not(),
          )
          ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
        .get();
  }

  /// Returns captures whose location source has not yet been resolved, ordered
  /// oldest-first. Used by startup recovery to finalize pending-location rows
  /// before queue reconciliation enqueues them for rendering.
  Future<List<CaptureRecord>> capturesAwaitingLocationResolution() {
    return (select(captureRecords)
          ..where((row) => row.locationResolution.equals('pending'))
          ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
        .get();
  }

  Future<CaptureRecord> incrementProcessingAttempts(String captureId) async {
    return transaction(() async {
      final current = await (select(
        captureRecords,
      )..where((row) => row.id.equals(captureId))).getSingle();
      await (update(
        captureRecords,
      )..where((row) => row.id.equals(captureId))).write(
        CaptureRecordsCompanion(
          processingAttempts: Value(current.processingAttempts + 1),
        ),
      );
      return (select(
        captureRecords,
      )..where((row) => row.id.equals(captureId))).getSingle();
    });
  }

  Future<CaptureRecord> resetCaptureForRetry(String captureId) async {
    return transaction(() async {
      final current = await (select(
        captureRecords,
      )..where((row) => row.id.equals(captureId))).getSingle();
      final target = CaptureStatus.captured;
      if (!current.status.canTransitionTo(target)) {
        throw StateError(
          'Cannot transition ${current.status.name} to ${target.name}',
        );
      }
      await (update(
        captureRecords,
      )..where((row) => row.id.equals(captureId))).write(
        CaptureRecordsCompanion(
          status: const Value(CaptureStatus.captured),
          failureReason: const Value(null),
          processingAttempts: const Value(0),
        ),
      );
      return (select(
        captureRecords,
      )..where((row) => row.id.equals(captureId))).getSingle();
    });
  }

  /// Validates that a watermark font scale is within the allowed 0.80-1.60
  /// range. Throws [ArgumentError] for out-of-range values.
  double _validatedFontScale(double value) {
    if (value < 0.80 || value > 1.60) {
      throw ArgumentError.value(value, 'fontScale');
    }
    return value;
  }

  /// Updates a capture's location resolution, outcome, and coordinates.
  ///
  /// [resolution] must be `'resolved'` or `'unavailable'`. Call this after
  /// EXIF or GPS lookup completes (successfully or not) to transition the
  /// capture out of the `'pending'` resolution state.
  Future<CaptureRecord> resolveCaptureLocation({
    required String captureId,
    required String resolution,
    required String outcome,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
    String? address,
  }) async {
    if (!{'resolved', 'unavailable'}.contains(resolution)) {
      throw ArgumentError.value(resolution, 'resolution');
    }
    await (update(
      captureRecords,
    )..where((row) => row.id.equals(captureId))).write(
      CaptureRecordsCompanion(
        locationResolution: Value(resolution),
        locationOutcome: Value(outcome),
        latitude: Value(latitude),
        longitude: Value(longitude),
        accuracyMeters: Value(accuracyMeters),
        address: Value(address),
      ),
    );
    return captureById(captureId).then((row) => row!);
  }

  /// Marks the original photo file as intentionally deleted at [deletedAt]
  /// (defaults to now). Does NOT clear `originalSha256` so the evidence
  /// hash survives cleanup.
  Future<CaptureRecord> markOriginalDeleted(
    String captureId, {
    DateTime? deletedAt,
  }) async {
    await (update(
      captureRecords,
    )..where((row) => row.id.equals(captureId))).write(
      CaptureRecordsCompanion(
        originalDeletedAt: Value(deletedAt ?? DateTime.now()),
      ),
    );
    return captureById(captureId).then((row) => row!);
  }

  /// Updates only the `publishedUri` column for [captureId], preserving the
  /// row's status, evidence hash, and other fields. Used by republish flows
  /// that re-publish an already-completed capture's watermarked JPEG and need
  /// to persist the new MediaStore URI.
  Future<CaptureRecord> updatePublishedUri(
    String captureId,
    String publishedUri,
  ) async {
    await (update(captureRecords)..where((row) => row.id.equals(captureId)))
        .write(CaptureRecordsCompanion(publishedUri: Value(publishedUri)));
    return captureById(captureId).then((row) => row!);
  }

  /// Returns captures matching any of the provided IDs, ordered by
  /// `createdAt` ascending. Returns an empty list for an empty input.
  Future<List<CaptureRecord>> capturesByIds(Iterable<String> captureIds) {
    final ids = captureIds.toSet().toList(growable: false);
    if (ids.isEmpty) return Future.value(const []);
    return (select(captureRecords)
          ..where((row) => row.id.isIn(ids))
          ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
        .get();
  }

  /// Shared select with a join on `captures.project_id = projects.id`,
  /// excluding `pendingCamera` rows, applying an optional [filter], and
  /// sorting by `coalesce(captured_at, created_at)` descending.
  Selectable<CaptureSummary> _captureSummarySelectable(CaptureFilter? filter) {
    final query =
        select(captureRecords).join([
            innerJoin(
              projects,
              projects.id.equalsExp(captureRecords.projectId),
            ),
          ])
          ..where(
            captureRecords.status
                .equals(CaptureStatus.pendingCamera.name)
                .not(),
          )
          ..orderBy([
            OrderingTerm(
              expression: coalesce([
                captureRecords.capturedAt,
                captureRecords.createdAt,
              ]),
              mode: OrderingMode.desc,
            ),
          ]);

    if (filter != null) {
      if (filter.projectId != null) {
        query.where(captureRecords.projectId.equals(filter.projectId!));
      }
      final range = filter.localRange;
      if (range != null) {
        final sortKey = coalesce([
          captureRecords.capturedAt,
          captureRecords.createdAt,
        ]);
        query.where(sortKey.isBiggerOrEqualValue(range.start));
        query.where(sortKey.isSmallerThanValue(range.end));
      }
    }
    return query.map(
      (row) => CaptureSummary(
        capture: row.readTable(captureRecords),
        projectName: row.read(projects.name)!,
      ),
    );
  }
}

/// Joined view of a capture row together with its parent project name.
class CaptureSummary {
  const CaptureSummary({required this.capture, required this.projectName});

  final CaptureRecord capture;
  final String projectName;
}

/// Subset of capture fields carried forward when creating a new capture from
/// the most recent non-pending record of a project. [notes] is always `null`
/// so stale review notes never leak into a fresh draft.
class CaptureCarryForwardDraft {
  const CaptureCarryForwardDraft({
    required this.workLocation,
    required this.workContent,
    required this.photographer,
  });

  final String workLocation;
  final String workContent;
  final String photographer;

  String? get notes => null;
}

extension _CaptureCarryForward on CaptureRecord {
  CaptureCarryForwardDraft toCarryForwardDraft() => CaptureCarryForwardDraft(
    workLocation: workLocation,
    workContent: workContent,
    photographer: photographer,
  );
}
