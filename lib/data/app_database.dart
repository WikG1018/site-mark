import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:sitemark/domain/capture_filter.dart';
import 'package:sitemark/domain/capture_status.dart';

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

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [Projects, CaptureRecords, AppSettings])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'sitemark'));

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    onUpgrade: (migrator, from, to) async {
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
        await _ensureGlobalSettingsRow();
      }
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
        updatedAt: now,
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }

  Future<Project> createProject({
    required String id,
    required String name,
    String? description,
    DateTime? createdAt,
  }) {
    final timestamp = createdAt ?? DateTime.now();
    return into(projects).insertReturning(
      ProjectsCompanion.insert(
        id: id,
        name: name.trim(),
        description: Value(description?.trim()),
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
    );
  }

  Stream<List<Project>> watchProjects() {
    return (select(
      projects,
    )..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])).watch();
  }

  Future<CaptureRecord> createPendingCapture({
    required String id,
    required String projectId,
    required String originalPath,
    required String workLocation,
    required String workContent,
    required String photographer,
    String? notes,
    DateTime? createdAt,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
    String? address,
    String? locationOutcome,
  }) {
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
  }) async {
    if (!{'bottomLeft', 'bottomRight'}.contains(position)) {
      throw ArgumentError.value(position, 'position');
    }
    if (opacity < 0.2 || opacity > 0.95) {
      throw ArgumentError.value(opacity, 'opacity');
    }
    await (update(projects)..where((row) => row.id.equals(projectId))).write(
      ProjectsCompanion(
        watermarkPosition: Value(position),
        watermarkOpacity: Value(opacity),
        watermarkAccentColorArgb: Value(accentColorArgb),
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

      final startOfDay = DateTime(
        capturedAt.year,
        capturedAt.month,
        capturedAt.day,
      );
      final endOfDay = startOfDay.add(const Duration(days: 1));
      final sameDay =
          await (select(captureRecords)..where(
                (row) =>
                    row.projectId.equals(current.projectId) &
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
      final number =
          'SM-'
          '${capturedAt.year.toString().padLeft(4, '0')}'
          '${capturedAt.month.toString().padLeft(2, '0')}'
          '${capturedAt.day.toString().padLeft(2, '0')}-'
          '${(highestSequence + 1).toString().padLeft(3, '0')}';

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

  Future<AppSetting> updateAppSettings({
    String? themeMode,
    String? localeCode,
    String? defaultWatermarkPosition,
    double? defaultWatermarkOpacity,
    int? defaultWatermarkAccentColorArgb,
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
    return (select(
      captureRecords,
    )..where((row) => row.id.equals(captureId))).watchSingleOrNull();
  }

  Stream<List<CaptureSummary>> watchCaptureSummaries(CaptureFilter filter) {
    return _captureSummarySelectable(filter).watch();
  }

  /// Unfiltered summary stream used to derive available filter options
  /// (projects, years, months, days) without applying the user's selection.
  Stream<List<CaptureSummary>> watchAllCaptureSummaries() {
    return _captureSummarySelectable(null).watch();
  }

  /// Returns captures in the `captured` or `rendering` states for startup
  /// reconciliation. Ordered oldest-first so pending work resumes in order.
  Future<List<CaptureRecord>> capturesAwaitingProcessing() {
    return (select(captureRecords)
          ..where(
            (row) =>
                row.status.equals(CaptureStatus.captured.name) |
                row.status.equals(CaptureStatus.rendering.name),
          )
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
          publishedUri: const Value(null),
          originalSha256: const Value(null),
          failureReason: const Value(null),
          processingAttempts: const Value(0),
        ),
      );
      return (select(
        captureRecords,
      )..where((row) => row.id.equals(captureId))).getSingle();
    });
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
