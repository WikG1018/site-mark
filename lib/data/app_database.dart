import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
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

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [Projects, CaptureRecords])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'sitemark'));

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.addColumn(projects, projects.watermarkPosition);
        await migrator.addColumn(projects, projects.watermarkOpacity);
        await migrator.addColumn(projects, projects.watermarkAccentColorArgb);
      }
    },
  );

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
}
