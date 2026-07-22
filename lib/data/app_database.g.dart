// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $ProjectsTable extends Projects with TableInfo<$ProjectsTable, Project> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProjectsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 120,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _watermarkPositionMeta = const VerificationMeta(
    'watermarkPosition',
  );
  @override
  late final GeneratedColumn<String> watermarkPosition =
      GeneratedColumn<String>(
        'watermark_position',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('bottomLeft'),
      );
  static const VerificationMeta _watermarkOpacityMeta = const VerificationMeta(
    'watermarkOpacity',
  );
  @override
  late final GeneratedColumn<double> watermarkOpacity = GeneratedColumn<double>(
    'watermark_opacity',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.78),
  );
  static const VerificationMeta _watermarkAccentColorArgbMeta =
      const VerificationMeta('watermarkAccentColorArgb');
  @override
  late final GeneratedColumn<int> watermarkAccentColorArgb =
      GeneratedColumn<int>(
        'watermark_accent_color_argb',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
        defaultValue: const Constant(0xff37c58b),
      );
  static const VerificationMeta _watermarkFontScaleMeta =
      const VerificationMeta('watermarkFontScale');
  @override
  late final GeneratedColumn<double> watermarkFontScale =
      GeneratedColumn<double>(
        'watermark_font_scale',
        aliasedName,
        false,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
        defaultValue: const Constant(1.0),
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    description,
    watermarkPosition,
    watermarkOpacity,
    watermarkAccentColorArgb,
    watermarkFontScale,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'projects';
  @override
  VerificationContext validateIntegrity(
    Insertable<Project> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('watermark_position')) {
      context.handle(
        _watermarkPositionMeta,
        watermarkPosition.isAcceptableOrUnknown(
          data['watermark_position']!,
          _watermarkPositionMeta,
        ),
      );
    }
    if (data.containsKey('watermark_opacity')) {
      context.handle(
        _watermarkOpacityMeta,
        watermarkOpacity.isAcceptableOrUnknown(
          data['watermark_opacity']!,
          _watermarkOpacityMeta,
        ),
      );
    }
    if (data.containsKey('watermark_accent_color_argb')) {
      context.handle(
        _watermarkAccentColorArgbMeta,
        watermarkAccentColorArgb.isAcceptableOrUnknown(
          data['watermark_accent_color_argb']!,
          _watermarkAccentColorArgbMeta,
        ),
      );
    }
    if (data.containsKey('watermark_font_scale')) {
      context.handle(
        _watermarkFontScaleMeta,
        watermarkFontScale.isAcceptableOrUnknown(
          data['watermark_font_scale']!,
          _watermarkFontScaleMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Project map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Project(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      watermarkPosition: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}watermark_position'],
      )!,
      watermarkOpacity: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}watermark_opacity'],
      )!,
      watermarkAccentColorArgb: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}watermark_accent_color_argb'],
      )!,
      watermarkFontScale: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}watermark_font_scale'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ProjectsTable createAlias(String alias) {
    return $ProjectsTable(attachedDatabase, alias);
  }
}

class Project extends DataClass implements Insertable<Project> {
  final String id;
  final String name;
  final String? description;
  final String watermarkPosition;
  final double watermarkOpacity;
  final int watermarkAccentColorArgb;
  final double watermarkFontScale;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Project({
    required this.id,
    required this.name,
    this.description,
    required this.watermarkPosition,
    required this.watermarkOpacity,
    required this.watermarkAccentColorArgb,
    required this.watermarkFontScale,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['watermark_position'] = Variable<String>(watermarkPosition);
    map['watermark_opacity'] = Variable<double>(watermarkOpacity);
    map['watermark_accent_color_argb'] = Variable<int>(
      watermarkAccentColorArgb,
    );
    map['watermark_font_scale'] = Variable<double>(watermarkFontScale);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ProjectsCompanion toCompanion(bool nullToAbsent) {
    return ProjectsCompanion(
      id: Value(id),
      name: Value(name),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      watermarkPosition: Value(watermarkPosition),
      watermarkOpacity: Value(watermarkOpacity),
      watermarkAccentColorArgb: Value(watermarkAccentColorArgb),
      watermarkFontScale: Value(watermarkFontScale),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Project.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Project(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String?>(json['description']),
      watermarkPosition: serializer.fromJson<String>(json['watermarkPosition']),
      watermarkOpacity: serializer.fromJson<double>(json['watermarkOpacity']),
      watermarkAccentColorArgb: serializer.fromJson<int>(
        json['watermarkAccentColorArgb'],
      ),
      watermarkFontScale: serializer.fromJson<double>(
        json['watermarkFontScale'],
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String?>(description),
      'watermarkPosition': serializer.toJson<String>(watermarkPosition),
      'watermarkOpacity': serializer.toJson<double>(watermarkOpacity),
      'watermarkAccentColorArgb': serializer.toJson<int>(
        watermarkAccentColorArgb,
      ),
      'watermarkFontScale': serializer.toJson<double>(watermarkFontScale),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Project copyWith({
    String? id,
    String? name,
    Value<String?> description = const Value.absent(),
    String? watermarkPosition,
    double? watermarkOpacity,
    int? watermarkAccentColorArgb,
    double? watermarkFontScale,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Project(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description.present ? description.value : this.description,
    watermarkPosition: watermarkPosition ?? this.watermarkPosition,
    watermarkOpacity: watermarkOpacity ?? this.watermarkOpacity,
    watermarkAccentColorArgb:
        watermarkAccentColorArgb ?? this.watermarkAccentColorArgb,
    watermarkFontScale: watermarkFontScale ?? this.watermarkFontScale,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Project copyWithCompanion(ProjectsCompanion data) {
    return Project(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      description: data.description.present
          ? data.description.value
          : this.description,
      watermarkPosition: data.watermarkPosition.present
          ? data.watermarkPosition.value
          : this.watermarkPosition,
      watermarkOpacity: data.watermarkOpacity.present
          ? data.watermarkOpacity.value
          : this.watermarkOpacity,
      watermarkAccentColorArgb: data.watermarkAccentColorArgb.present
          ? data.watermarkAccentColorArgb.value
          : this.watermarkAccentColorArgb,
      watermarkFontScale: data.watermarkFontScale.present
          ? data.watermarkFontScale.value
          : this.watermarkFontScale,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Project(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('watermarkPosition: $watermarkPosition, ')
          ..write('watermarkOpacity: $watermarkOpacity, ')
          ..write('watermarkAccentColorArgb: $watermarkAccentColorArgb, ')
          ..write('watermarkFontScale: $watermarkFontScale, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    description,
    watermarkPosition,
    watermarkOpacity,
    watermarkAccentColorArgb,
    watermarkFontScale,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Project &&
          other.id == this.id &&
          other.name == this.name &&
          other.description == this.description &&
          other.watermarkPosition == this.watermarkPosition &&
          other.watermarkOpacity == this.watermarkOpacity &&
          other.watermarkAccentColorArgb == this.watermarkAccentColorArgb &&
          other.watermarkFontScale == this.watermarkFontScale &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ProjectsCompanion extends UpdateCompanion<Project> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> description;
  final Value<String> watermarkPosition;
  final Value<double> watermarkOpacity;
  final Value<int> watermarkAccentColorArgb;
  final Value<double> watermarkFontScale;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ProjectsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.watermarkPosition = const Value.absent(),
    this.watermarkOpacity = const Value.absent(),
    this.watermarkAccentColorArgb = const Value.absent(),
    this.watermarkFontScale = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProjectsCompanion.insert({
    required String id,
    required String name,
    this.description = const Value.absent(),
    this.watermarkPosition = const Value.absent(),
    this.watermarkOpacity = const Value.absent(),
    this.watermarkAccentColorArgb = const Value.absent(),
    this.watermarkFontScale = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Project> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? description,
    Expression<String>? watermarkPosition,
    Expression<double>? watermarkOpacity,
    Expression<int>? watermarkAccentColorArgb,
    Expression<double>? watermarkFontScale,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (watermarkPosition != null) 'watermark_position': watermarkPosition,
      if (watermarkOpacity != null) 'watermark_opacity': watermarkOpacity,
      if (watermarkAccentColorArgb != null)
        'watermark_accent_color_argb': watermarkAccentColorArgb,
      if (watermarkFontScale != null)
        'watermark_font_scale': watermarkFontScale,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProjectsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String?>? description,
    Value<String>? watermarkPosition,
    Value<double>? watermarkOpacity,
    Value<int>? watermarkAccentColorArgb,
    Value<double>? watermarkFontScale,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ProjectsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      watermarkPosition: watermarkPosition ?? this.watermarkPosition,
      watermarkOpacity: watermarkOpacity ?? this.watermarkOpacity,
      watermarkAccentColorArgb:
          watermarkAccentColorArgb ?? this.watermarkAccentColorArgb,
      watermarkFontScale: watermarkFontScale ?? this.watermarkFontScale,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (watermarkPosition.present) {
      map['watermark_position'] = Variable<String>(watermarkPosition.value);
    }
    if (watermarkOpacity.present) {
      map['watermark_opacity'] = Variable<double>(watermarkOpacity.value);
    }
    if (watermarkAccentColorArgb.present) {
      map['watermark_accent_color_argb'] = Variable<int>(
        watermarkAccentColorArgb.value,
      );
    }
    if (watermarkFontScale.present) {
      map['watermark_font_scale'] = Variable<double>(watermarkFontScale.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProjectsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('watermarkPosition: $watermarkPosition, ')
          ..write('watermarkOpacity: $watermarkOpacity, ')
          ..write('watermarkAccentColorArgb: $watermarkAccentColorArgb, ')
          ..write('watermarkFontScale: $watermarkFontScale, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CaptureRecordsTable extends CaptureRecords
    with TableInfo<$CaptureRecordsTable, CaptureRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CaptureRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _projectIdMeta = const VerificationMeta(
    'projectId',
  );
  @override
  late final GeneratedColumn<String> projectId = GeneratedColumn<String>(
    'project_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES projects (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _photoNumberMeta = const VerificationMeta(
    'photoNumber',
  );
  @override
  late final GeneratedColumn<String> photoNumber = GeneratedColumn<String>(
    'photo_number',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _workLocationMeta = const VerificationMeta(
    'workLocation',
  );
  @override
  late final GeneratedColumn<String> workLocation = GeneratedColumn<String>(
    'work_location',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 160,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workContentMeta = const VerificationMeta(
    'workContent',
  );
  @override
  late final GeneratedColumn<String> workContent = GeneratedColumn<String>(
    'work_content',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 240,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _photographerMeta = const VerificationMeta(
    'photographer',
  );
  @override
  late final GeneratedColumn<String> photographer = GeneratedColumn<String>(
    'photographer',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 80,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _originalPathMeta = const VerificationMeta(
    'originalPath',
  );
  @override
  late final GeneratedColumn<String> originalPath = GeneratedColumn<String>(
    'original_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _publishedUriMeta = const VerificationMeta(
    'publishedUri',
  );
  @override
  late final GeneratedColumn<String> publishedUri = GeneratedColumn<String>(
    'published_uri',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _originalSha256Meta = const VerificationMeta(
    'originalSha256',
  );
  @override
  late final GeneratedColumn<String> originalSha256 = GeneratedColumn<String>(
    'original_sha256',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<CaptureStatus, String> status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<CaptureStatus>($CaptureRecordsTable.$converterstatus);
  static const VerificationMeta _failureReasonMeta = const VerificationMeta(
    'failureReason',
  );
  @override
  late final GeneratedColumn<String> failureReason = GeneratedColumn<String>(
    'failure_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _capturedAtMeta = const VerificationMeta(
    'capturedAt',
  );
  @override
  late final GeneratedColumn<DateTime> capturedAt = GeneratedColumn<DateTime>(
    'captured_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
    'latitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
    'longitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _accuracyMetersMeta = const VerificationMeta(
    'accuracyMeters',
  );
  @override
  late final GeneratedColumn<double> accuracyMeters = GeneratedColumn<double>(
    'accuracy_meters',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addressMeta = const VerificationMeta(
    'address',
  );
  @override
  late final GeneratedColumn<String> address = GeneratedColumn<String>(
    'address',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _locationOutcomeMeta = const VerificationMeta(
    'locationOutcome',
  );
  @override
  late final GeneratedColumn<String> locationOutcome = GeneratedColumn<String>(
    'location_outcome',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _processingAttemptsMeta =
      const VerificationMeta('processingAttempts');
  @override
  late final GeneratedColumn<int> processingAttempts = GeneratedColumn<int>(
    'processing_attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _watermarkLocaleCodeMeta =
      const VerificationMeta('watermarkLocaleCode');
  @override
  late final GeneratedColumn<String> watermarkLocaleCode =
      GeneratedColumn<String>(
        'watermark_locale_code',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('zh'),
      );
  static const VerificationMeta _locationResolutionMeta =
      const VerificationMeta('locationResolution');
  @override
  late final GeneratedColumn<String> locationResolution =
      GeneratedColumn<String>(
        'location_resolution',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('resolved'),
      );
  static const VerificationMeta _originalDeletedAtMeta = const VerificationMeta(
    'originalDeletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> originalDeletedAt =
      GeneratedColumn<DateTime>(
        'original_deleted_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    projectId,
    photoNumber,
    workLocation,
    workContent,
    photographer,
    notes,
    originalPath,
    publishedUri,
    originalSha256,
    status,
    failureReason,
    createdAt,
    capturedAt,
    latitude,
    longitude,
    accuracyMeters,
    address,
    locationOutcome,
    processingAttempts,
    watermarkLocaleCode,
    locationResolution,
    originalDeletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'captures';
  @override
  VerificationContext validateIntegrity(
    Insertable<CaptureRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('project_id')) {
      context.handle(
        _projectIdMeta,
        projectId.isAcceptableOrUnknown(data['project_id']!, _projectIdMeta),
      );
    } else if (isInserting) {
      context.missing(_projectIdMeta);
    }
    if (data.containsKey('photo_number')) {
      context.handle(
        _photoNumberMeta,
        photoNumber.isAcceptableOrUnknown(
          data['photo_number']!,
          _photoNumberMeta,
        ),
      );
    }
    if (data.containsKey('work_location')) {
      context.handle(
        _workLocationMeta,
        workLocation.isAcceptableOrUnknown(
          data['work_location']!,
          _workLocationMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workLocationMeta);
    }
    if (data.containsKey('work_content')) {
      context.handle(
        _workContentMeta,
        workContent.isAcceptableOrUnknown(
          data['work_content']!,
          _workContentMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workContentMeta);
    }
    if (data.containsKey('photographer')) {
      context.handle(
        _photographerMeta,
        photographer.isAcceptableOrUnknown(
          data['photographer']!,
          _photographerMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_photographerMeta);
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('original_path')) {
      context.handle(
        _originalPathMeta,
        originalPath.isAcceptableOrUnknown(
          data['original_path']!,
          _originalPathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_originalPathMeta);
    }
    if (data.containsKey('published_uri')) {
      context.handle(
        _publishedUriMeta,
        publishedUri.isAcceptableOrUnknown(
          data['published_uri']!,
          _publishedUriMeta,
        ),
      );
    }
    if (data.containsKey('original_sha256')) {
      context.handle(
        _originalSha256Meta,
        originalSha256.isAcceptableOrUnknown(
          data['original_sha256']!,
          _originalSha256Meta,
        ),
      );
    }
    if (data.containsKey('failure_reason')) {
      context.handle(
        _failureReasonMeta,
        failureReason.isAcceptableOrUnknown(
          data['failure_reason']!,
          _failureReasonMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('captured_at')) {
      context.handle(
        _capturedAtMeta,
        capturedAt.isAcceptableOrUnknown(data['captured_at']!, _capturedAtMeta),
      );
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    }
    if (data.containsKey('accuracy_meters')) {
      context.handle(
        _accuracyMetersMeta,
        accuracyMeters.isAcceptableOrUnknown(
          data['accuracy_meters']!,
          _accuracyMetersMeta,
        ),
      );
    }
    if (data.containsKey('address')) {
      context.handle(
        _addressMeta,
        address.isAcceptableOrUnknown(data['address']!, _addressMeta),
      );
    }
    if (data.containsKey('location_outcome')) {
      context.handle(
        _locationOutcomeMeta,
        locationOutcome.isAcceptableOrUnknown(
          data['location_outcome']!,
          _locationOutcomeMeta,
        ),
      );
    }
    if (data.containsKey('processing_attempts')) {
      context.handle(
        _processingAttemptsMeta,
        processingAttempts.isAcceptableOrUnknown(
          data['processing_attempts']!,
          _processingAttemptsMeta,
        ),
      );
    }
    if (data.containsKey('watermark_locale_code')) {
      context.handle(
        _watermarkLocaleCodeMeta,
        watermarkLocaleCode.isAcceptableOrUnknown(
          data['watermark_locale_code']!,
          _watermarkLocaleCodeMeta,
        ),
      );
    }
    if (data.containsKey('location_resolution')) {
      context.handle(
        _locationResolutionMeta,
        locationResolution.isAcceptableOrUnknown(
          data['location_resolution']!,
          _locationResolutionMeta,
        ),
      );
    }
    if (data.containsKey('original_deleted_at')) {
      context.handle(
        _originalDeletedAtMeta,
        originalDeletedAt.isAcceptableOrUnknown(
          data['original_deleted_at']!,
          _originalDeletedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CaptureRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CaptureRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      projectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project_id'],
      )!,
      photoNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}photo_number'],
      ),
      workLocation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}work_location'],
      )!,
      workContent: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}work_content'],
      )!,
      photographer: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}photographer'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      originalPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}original_path'],
      )!,
      publishedUri: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}published_uri'],
      ),
      originalSha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}original_sha256'],
      ),
      status: $CaptureRecordsTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      failureReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}failure_reason'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      capturedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}captured_at'],
      ),
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      ),
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      ),
      accuracyMeters: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}accuracy_meters'],
      ),
      address: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}address'],
      ),
      locationOutcome: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location_outcome'],
      ),
      processingAttempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}processing_attempts'],
      )!,
      watermarkLocaleCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}watermark_locale_code'],
      )!,
      locationResolution: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location_resolution'],
      )!,
      originalDeletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}original_deleted_at'],
      ),
    );
  }

  @override
  $CaptureRecordsTable createAlias(String alias) {
    return $CaptureRecordsTable(attachedDatabase, alias);
  }

  static TypeConverter<CaptureStatus, String> $converterstatus =
      const CaptureStatusConverter();
}

class CaptureRecord extends DataClass implements Insertable<CaptureRecord> {
  final String id;
  final String projectId;
  final String? photoNumber;
  final String workLocation;
  final String workContent;
  final String photographer;
  final String? notes;
  final String originalPath;
  final String? publishedUri;
  final String? originalSha256;
  final CaptureStatus status;
  final String? failureReason;
  final DateTime createdAt;
  final DateTime? capturedAt;
  final double? latitude;
  final double? longitude;
  final double? accuracyMeters;
  final String? address;
  final String? locationOutcome;
  final int processingAttempts;
  final String watermarkLocaleCode;
  final String locationResolution;
  final DateTime? originalDeletedAt;
  const CaptureRecord({
    required this.id,
    required this.projectId,
    this.photoNumber,
    required this.workLocation,
    required this.workContent,
    required this.photographer,
    this.notes,
    required this.originalPath,
    this.publishedUri,
    this.originalSha256,
    required this.status,
    this.failureReason,
    required this.createdAt,
    this.capturedAt,
    this.latitude,
    this.longitude,
    this.accuracyMeters,
    this.address,
    this.locationOutcome,
    required this.processingAttempts,
    required this.watermarkLocaleCode,
    required this.locationResolution,
    this.originalDeletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['project_id'] = Variable<String>(projectId);
    if (!nullToAbsent || photoNumber != null) {
      map['photo_number'] = Variable<String>(photoNumber);
    }
    map['work_location'] = Variable<String>(workLocation);
    map['work_content'] = Variable<String>(workContent);
    map['photographer'] = Variable<String>(photographer);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['original_path'] = Variable<String>(originalPath);
    if (!nullToAbsent || publishedUri != null) {
      map['published_uri'] = Variable<String>(publishedUri);
    }
    if (!nullToAbsent || originalSha256 != null) {
      map['original_sha256'] = Variable<String>(originalSha256);
    }
    {
      map['status'] = Variable<String>(
        $CaptureRecordsTable.$converterstatus.toSql(status),
      );
    }
    if (!nullToAbsent || failureReason != null) {
      map['failure_reason'] = Variable<String>(failureReason);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || capturedAt != null) {
      map['captured_at'] = Variable<DateTime>(capturedAt);
    }
    if (!nullToAbsent || latitude != null) {
      map['latitude'] = Variable<double>(latitude);
    }
    if (!nullToAbsent || longitude != null) {
      map['longitude'] = Variable<double>(longitude);
    }
    if (!nullToAbsent || accuracyMeters != null) {
      map['accuracy_meters'] = Variable<double>(accuracyMeters);
    }
    if (!nullToAbsent || address != null) {
      map['address'] = Variable<String>(address);
    }
    if (!nullToAbsent || locationOutcome != null) {
      map['location_outcome'] = Variable<String>(locationOutcome);
    }
    map['processing_attempts'] = Variable<int>(processingAttempts);
    map['watermark_locale_code'] = Variable<String>(watermarkLocaleCode);
    map['location_resolution'] = Variable<String>(locationResolution);
    if (!nullToAbsent || originalDeletedAt != null) {
      map['original_deleted_at'] = Variable<DateTime>(originalDeletedAt);
    }
    return map;
  }

  CaptureRecordsCompanion toCompanion(bool nullToAbsent) {
    return CaptureRecordsCompanion(
      id: Value(id),
      projectId: Value(projectId),
      photoNumber: photoNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(photoNumber),
      workLocation: Value(workLocation),
      workContent: Value(workContent),
      photographer: Value(photographer),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      originalPath: Value(originalPath),
      publishedUri: publishedUri == null && nullToAbsent
          ? const Value.absent()
          : Value(publishedUri),
      originalSha256: originalSha256 == null && nullToAbsent
          ? const Value.absent()
          : Value(originalSha256),
      status: Value(status),
      failureReason: failureReason == null && nullToAbsent
          ? const Value.absent()
          : Value(failureReason),
      createdAt: Value(createdAt),
      capturedAt: capturedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(capturedAt),
      latitude: latitude == null && nullToAbsent
          ? const Value.absent()
          : Value(latitude),
      longitude: longitude == null && nullToAbsent
          ? const Value.absent()
          : Value(longitude),
      accuracyMeters: accuracyMeters == null && nullToAbsent
          ? const Value.absent()
          : Value(accuracyMeters),
      address: address == null && nullToAbsent
          ? const Value.absent()
          : Value(address),
      locationOutcome: locationOutcome == null && nullToAbsent
          ? const Value.absent()
          : Value(locationOutcome),
      processingAttempts: Value(processingAttempts),
      watermarkLocaleCode: Value(watermarkLocaleCode),
      locationResolution: Value(locationResolution),
      originalDeletedAt: originalDeletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(originalDeletedAt),
    );
  }

  factory CaptureRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CaptureRecord(
      id: serializer.fromJson<String>(json['id']),
      projectId: serializer.fromJson<String>(json['projectId']),
      photoNumber: serializer.fromJson<String?>(json['photoNumber']),
      workLocation: serializer.fromJson<String>(json['workLocation']),
      workContent: serializer.fromJson<String>(json['workContent']),
      photographer: serializer.fromJson<String>(json['photographer']),
      notes: serializer.fromJson<String?>(json['notes']),
      originalPath: serializer.fromJson<String>(json['originalPath']),
      publishedUri: serializer.fromJson<String?>(json['publishedUri']),
      originalSha256: serializer.fromJson<String?>(json['originalSha256']),
      status: serializer.fromJson<CaptureStatus>(json['status']),
      failureReason: serializer.fromJson<String?>(json['failureReason']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      capturedAt: serializer.fromJson<DateTime?>(json['capturedAt']),
      latitude: serializer.fromJson<double?>(json['latitude']),
      longitude: serializer.fromJson<double?>(json['longitude']),
      accuracyMeters: serializer.fromJson<double?>(json['accuracyMeters']),
      address: serializer.fromJson<String?>(json['address']),
      locationOutcome: serializer.fromJson<String?>(json['locationOutcome']),
      processingAttempts: serializer.fromJson<int>(json['processingAttempts']),
      watermarkLocaleCode: serializer.fromJson<String>(
        json['watermarkLocaleCode'],
      ),
      locationResolution: serializer.fromJson<String>(
        json['locationResolution'],
      ),
      originalDeletedAt: serializer.fromJson<DateTime?>(
        json['originalDeletedAt'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'projectId': serializer.toJson<String>(projectId),
      'photoNumber': serializer.toJson<String?>(photoNumber),
      'workLocation': serializer.toJson<String>(workLocation),
      'workContent': serializer.toJson<String>(workContent),
      'photographer': serializer.toJson<String>(photographer),
      'notes': serializer.toJson<String?>(notes),
      'originalPath': serializer.toJson<String>(originalPath),
      'publishedUri': serializer.toJson<String?>(publishedUri),
      'originalSha256': serializer.toJson<String?>(originalSha256),
      'status': serializer.toJson<CaptureStatus>(status),
      'failureReason': serializer.toJson<String?>(failureReason),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'capturedAt': serializer.toJson<DateTime?>(capturedAt),
      'latitude': serializer.toJson<double?>(latitude),
      'longitude': serializer.toJson<double?>(longitude),
      'accuracyMeters': serializer.toJson<double?>(accuracyMeters),
      'address': serializer.toJson<String?>(address),
      'locationOutcome': serializer.toJson<String?>(locationOutcome),
      'processingAttempts': serializer.toJson<int>(processingAttempts),
      'watermarkLocaleCode': serializer.toJson<String>(watermarkLocaleCode),
      'locationResolution': serializer.toJson<String>(locationResolution),
      'originalDeletedAt': serializer.toJson<DateTime?>(originalDeletedAt),
    };
  }

  CaptureRecord copyWith({
    String? id,
    String? projectId,
    Value<String?> photoNumber = const Value.absent(),
    String? workLocation,
    String? workContent,
    String? photographer,
    Value<String?> notes = const Value.absent(),
    String? originalPath,
    Value<String?> publishedUri = const Value.absent(),
    Value<String?> originalSha256 = const Value.absent(),
    CaptureStatus? status,
    Value<String?> failureReason = const Value.absent(),
    DateTime? createdAt,
    Value<DateTime?> capturedAt = const Value.absent(),
    Value<double?> latitude = const Value.absent(),
    Value<double?> longitude = const Value.absent(),
    Value<double?> accuracyMeters = const Value.absent(),
    Value<String?> address = const Value.absent(),
    Value<String?> locationOutcome = const Value.absent(),
    int? processingAttempts,
    String? watermarkLocaleCode,
    String? locationResolution,
    Value<DateTime?> originalDeletedAt = const Value.absent(),
  }) => CaptureRecord(
    id: id ?? this.id,
    projectId: projectId ?? this.projectId,
    photoNumber: photoNumber.present ? photoNumber.value : this.photoNumber,
    workLocation: workLocation ?? this.workLocation,
    workContent: workContent ?? this.workContent,
    photographer: photographer ?? this.photographer,
    notes: notes.present ? notes.value : this.notes,
    originalPath: originalPath ?? this.originalPath,
    publishedUri: publishedUri.present ? publishedUri.value : this.publishedUri,
    originalSha256: originalSha256.present
        ? originalSha256.value
        : this.originalSha256,
    status: status ?? this.status,
    failureReason: failureReason.present
        ? failureReason.value
        : this.failureReason,
    createdAt: createdAt ?? this.createdAt,
    capturedAt: capturedAt.present ? capturedAt.value : this.capturedAt,
    latitude: latitude.present ? latitude.value : this.latitude,
    longitude: longitude.present ? longitude.value : this.longitude,
    accuracyMeters: accuracyMeters.present
        ? accuracyMeters.value
        : this.accuracyMeters,
    address: address.present ? address.value : this.address,
    locationOutcome: locationOutcome.present
        ? locationOutcome.value
        : this.locationOutcome,
    processingAttempts: processingAttempts ?? this.processingAttempts,
    watermarkLocaleCode: watermarkLocaleCode ?? this.watermarkLocaleCode,
    locationResolution: locationResolution ?? this.locationResolution,
    originalDeletedAt: originalDeletedAt.present
        ? originalDeletedAt.value
        : this.originalDeletedAt,
  );
  CaptureRecord copyWithCompanion(CaptureRecordsCompanion data) {
    return CaptureRecord(
      id: data.id.present ? data.id.value : this.id,
      projectId: data.projectId.present ? data.projectId.value : this.projectId,
      photoNumber: data.photoNumber.present
          ? data.photoNumber.value
          : this.photoNumber,
      workLocation: data.workLocation.present
          ? data.workLocation.value
          : this.workLocation,
      workContent: data.workContent.present
          ? data.workContent.value
          : this.workContent,
      photographer: data.photographer.present
          ? data.photographer.value
          : this.photographer,
      notes: data.notes.present ? data.notes.value : this.notes,
      originalPath: data.originalPath.present
          ? data.originalPath.value
          : this.originalPath,
      publishedUri: data.publishedUri.present
          ? data.publishedUri.value
          : this.publishedUri,
      originalSha256: data.originalSha256.present
          ? data.originalSha256.value
          : this.originalSha256,
      status: data.status.present ? data.status.value : this.status,
      failureReason: data.failureReason.present
          ? data.failureReason.value
          : this.failureReason,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      capturedAt: data.capturedAt.present
          ? data.capturedAt.value
          : this.capturedAt,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      accuracyMeters: data.accuracyMeters.present
          ? data.accuracyMeters.value
          : this.accuracyMeters,
      address: data.address.present ? data.address.value : this.address,
      locationOutcome: data.locationOutcome.present
          ? data.locationOutcome.value
          : this.locationOutcome,
      processingAttempts: data.processingAttempts.present
          ? data.processingAttempts.value
          : this.processingAttempts,
      watermarkLocaleCode: data.watermarkLocaleCode.present
          ? data.watermarkLocaleCode.value
          : this.watermarkLocaleCode,
      locationResolution: data.locationResolution.present
          ? data.locationResolution.value
          : this.locationResolution,
      originalDeletedAt: data.originalDeletedAt.present
          ? data.originalDeletedAt.value
          : this.originalDeletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CaptureRecord(')
          ..write('id: $id, ')
          ..write('projectId: $projectId, ')
          ..write('photoNumber: $photoNumber, ')
          ..write('workLocation: $workLocation, ')
          ..write('workContent: $workContent, ')
          ..write('photographer: $photographer, ')
          ..write('notes: $notes, ')
          ..write('originalPath: $originalPath, ')
          ..write('publishedUri: $publishedUri, ')
          ..write('originalSha256: $originalSha256, ')
          ..write('status: $status, ')
          ..write('failureReason: $failureReason, ')
          ..write('createdAt: $createdAt, ')
          ..write('capturedAt: $capturedAt, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('accuracyMeters: $accuracyMeters, ')
          ..write('address: $address, ')
          ..write('locationOutcome: $locationOutcome, ')
          ..write('processingAttempts: $processingAttempts, ')
          ..write('watermarkLocaleCode: $watermarkLocaleCode, ')
          ..write('locationResolution: $locationResolution, ')
          ..write('originalDeletedAt: $originalDeletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    projectId,
    photoNumber,
    workLocation,
    workContent,
    photographer,
    notes,
    originalPath,
    publishedUri,
    originalSha256,
    status,
    failureReason,
    createdAt,
    capturedAt,
    latitude,
    longitude,
    accuracyMeters,
    address,
    locationOutcome,
    processingAttempts,
    watermarkLocaleCode,
    locationResolution,
    originalDeletedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CaptureRecord &&
          other.id == this.id &&
          other.projectId == this.projectId &&
          other.photoNumber == this.photoNumber &&
          other.workLocation == this.workLocation &&
          other.workContent == this.workContent &&
          other.photographer == this.photographer &&
          other.notes == this.notes &&
          other.originalPath == this.originalPath &&
          other.publishedUri == this.publishedUri &&
          other.originalSha256 == this.originalSha256 &&
          other.status == this.status &&
          other.failureReason == this.failureReason &&
          other.createdAt == this.createdAt &&
          other.capturedAt == this.capturedAt &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.accuracyMeters == this.accuracyMeters &&
          other.address == this.address &&
          other.locationOutcome == this.locationOutcome &&
          other.processingAttempts == this.processingAttempts &&
          other.watermarkLocaleCode == this.watermarkLocaleCode &&
          other.locationResolution == this.locationResolution &&
          other.originalDeletedAt == this.originalDeletedAt);
}

class CaptureRecordsCompanion extends UpdateCompanion<CaptureRecord> {
  final Value<String> id;
  final Value<String> projectId;
  final Value<String?> photoNumber;
  final Value<String> workLocation;
  final Value<String> workContent;
  final Value<String> photographer;
  final Value<String?> notes;
  final Value<String> originalPath;
  final Value<String?> publishedUri;
  final Value<String?> originalSha256;
  final Value<CaptureStatus> status;
  final Value<String?> failureReason;
  final Value<DateTime> createdAt;
  final Value<DateTime?> capturedAt;
  final Value<double?> latitude;
  final Value<double?> longitude;
  final Value<double?> accuracyMeters;
  final Value<String?> address;
  final Value<String?> locationOutcome;
  final Value<int> processingAttempts;
  final Value<String> watermarkLocaleCode;
  final Value<String> locationResolution;
  final Value<DateTime?> originalDeletedAt;
  final Value<int> rowid;
  const CaptureRecordsCompanion({
    this.id = const Value.absent(),
    this.projectId = const Value.absent(),
    this.photoNumber = const Value.absent(),
    this.workLocation = const Value.absent(),
    this.workContent = const Value.absent(),
    this.photographer = const Value.absent(),
    this.notes = const Value.absent(),
    this.originalPath = const Value.absent(),
    this.publishedUri = const Value.absent(),
    this.originalSha256 = const Value.absent(),
    this.status = const Value.absent(),
    this.failureReason = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.capturedAt = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.accuracyMeters = const Value.absent(),
    this.address = const Value.absent(),
    this.locationOutcome = const Value.absent(),
    this.processingAttempts = const Value.absent(),
    this.watermarkLocaleCode = const Value.absent(),
    this.locationResolution = const Value.absent(),
    this.originalDeletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CaptureRecordsCompanion.insert({
    required String id,
    required String projectId,
    this.photoNumber = const Value.absent(),
    required String workLocation,
    required String workContent,
    required String photographer,
    this.notes = const Value.absent(),
    required String originalPath,
    this.publishedUri = const Value.absent(),
    this.originalSha256 = const Value.absent(),
    required CaptureStatus status,
    this.failureReason = const Value.absent(),
    required DateTime createdAt,
    this.capturedAt = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.accuracyMeters = const Value.absent(),
    this.address = const Value.absent(),
    this.locationOutcome = const Value.absent(),
    this.processingAttempts = const Value.absent(),
    this.watermarkLocaleCode = const Value.absent(),
    this.locationResolution = const Value.absent(),
    this.originalDeletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       projectId = Value(projectId),
       workLocation = Value(workLocation),
       workContent = Value(workContent),
       photographer = Value(photographer),
       originalPath = Value(originalPath),
       status = Value(status),
       createdAt = Value(createdAt);
  static Insertable<CaptureRecord> custom({
    Expression<String>? id,
    Expression<String>? projectId,
    Expression<String>? photoNumber,
    Expression<String>? workLocation,
    Expression<String>? workContent,
    Expression<String>? photographer,
    Expression<String>? notes,
    Expression<String>? originalPath,
    Expression<String>? publishedUri,
    Expression<String>? originalSha256,
    Expression<String>? status,
    Expression<String>? failureReason,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? capturedAt,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<double>? accuracyMeters,
    Expression<String>? address,
    Expression<String>? locationOutcome,
    Expression<int>? processingAttempts,
    Expression<String>? watermarkLocaleCode,
    Expression<String>? locationResolution,
    Expression<DateTime>? originalDeletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (projectId != null) 'project_id': projectId,
      if (photoNumber != null) 'photo_number': photoNumber,
      if (workLocation != null) 'work_location': workLocation,
      if (workContent != null) 'work_content': workContent,
      if (photographer != null) 'photographer': photographer,
      if (notes != null) 'notes': notes,
      if (originalPath != null) 'original_path': originalPath,
      if (publishedUri != null) 'published_uri': publishedUri,
      if (originalSha256 != null) 'original_sha256': originalSha256,
      if (status != null) 'status': status,
      if (failureReason != null) 'failure_reason': failureReason,
      if (createdAt != null) 'created_at': createdAt,
      if (capturedAt != null) 'captured_at': capturedAt,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (accuracyMeters != null) 'accuracy_meters': accuracyMeters,
      if (address != null) 'address': address,
      if (locationOutcome != null) 'location_outcome': locationOutcome,
      if (processingAttempts != null) 'processing_attempts': processingAttempts,
      if (watermarkLocaleCode != null)
        'watermark_locale_code': watermarkLocaleCode,
      if (locationResolution != null) 'location_resolution': locationResolution,
      if (originalDeletedAt != null) 'original_deleted_at': originalDeletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CaptureRecordsCompanion copyWith({
    Value<String>? id,
    Value<String>? projectId,
    Value<String?>? photoNumber,
    Value<String>? workLocation,
    Value<String>? workContent,
    Value<String>? photographer,
    Value<String?>? notes,
    Value<String>? originalPath,
    Value<String?>? publishedUri,
    Value<String?>? originalSha256,
    Value<CaptureStatus>? status,
    Value<String?>? failureReason,
    Value<DateTime>? createdAt,
    Value<DateTime?>? capturedAt,
    Value<double?>? latitude,
    Value<double?>? longitude,
    Value<double?>? accuracyMeters,
    Value<String?>? address,
    Value<String?>? locationOutcome,
    Value<int>? processingAttempts,
    Value<String>? watermarkLocaleCode,
    Value<String>? locationResolution,
    Value<DateTime?>? originalDeletedAt,
    Value<int>? rowid,
  }) {
    return CaptureRecordsCompanion(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      photoNumber: photoNumber ?? this.photoNumber,
      workLocation: workLocation ?? this.workLocation,
      workContent: workContent ?? this.workContent,
      photographer: photographer ?? this.photographer,
      notes: notes ?? this.notes,
      originalPath: originalPath ?? this.originalPath,
      publishedUri: publishedUri ?? this.publishedUri,
      originalSha256: originalSha256 ?? this.originalSha256,
      status: status ?? this.status,
      failureReason: failureReason ?? this.failureReason,
      createdAt: createdAt ?? this.createdAt,
      capturedAt: capturedAt ?? this.capturedAt,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracyMeters: accuracyMeters ?? this.accuracyMeters,
      address: address ?? this.address,
      locationOutcome: locationOutcome ?? this.locationOutcome,
      processingAttempts: processingAttempts ?? this.processingAttempts,
      watermarkLocaleCode: watermarkLocaleCode ?? this.watermarkLocaleCode,
      locationResolution: locationResolution ?? this.locationResolution,
      originalDeletedAt: originalDeletedAt ?? this.originalDeletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (projectId.present) {
      map['project_id'] = Variable<String>(projectId.value);
    }
    if (photoNumber.present) {
      map['photo_number'] = Variable<String>(photoNumber.value);
    }
    if (workLocation.present) {
      map['work_location'] = Variable<String>(workLocation.value);
    }
    if (workContent.present) {
      map['work_content'] = Variable<String>(workContent.value);
    }
    if (photographer.present) {
      map['photographer'] = Variable<String>(photographer.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (originalPath.present) {
      map['original_path'] = Variable<String>(originalPath.value);
    }
    if (publishedUri.present) {
      map['published_uri'] = Variable<String>(publishedUri.value);
    }
    if (originalSha256.present) {
      map['original_sha256'] = Variable<String>(originalSha256.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $CaptureRecordsTable.$converterstatus.toSql(status.value),
      );
    }
    if (failureReason.present) {
      map['failure_reason'] = Variable<String>(failureReason.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (capturedAt.present) {
      map['captured_at'] = Variable<DateTime>(capturedAt.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (accuracyMeters.present) {
      map['accuracy_meters'] = Variable<double>(accuracyMeters.value);
    }
    if (address.present) {
      map['address'] = Variable<String>(address.value);
    }
    if (locationOutcome.present) {
      map['location_outcome'] = Variable<String>(locationOutcome.value);
    }
    if (processingAttempts.present) {
      map['processing_attempts'] = Variable<int>(processingAttempts.value);
    }
    if (watermarkLocaleCode.present) {
      map['watermark_locale_code'] = Variable<String>(
        watermarkLocaleCode.value,
      );
    }
    if (locationResolution.present) {
      map['location_resolution'] = Variable<String>(locationResolution.value);
    }
    if (originalDeletedAt.present) {
      map['original_deleted_at'] = Variable<DateTime>(originalDeletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CaptureRecordsCompanion(')
          ..write('id: $id, ')
          ..write('projectId: $projectId, ')
          ..write('photoNumber: $photoNumber, ')
          ..write('workLocation: $workLocation, ')
          ..write('workContent: $workContent, ')
          ..write('photographer: $photographer, ')
          ..write('notes: $notes, ')
          ..write('originalPath: $originalPath, ')
          ..write('publishedUri: $publishedUri, ')
          ..write('originalSha256: $originalSha256, ')
          ..write('status: $status, ')
          ..write('failureReason: $failureReason, ')
          ..write('createdAt: $createdAt, ')
          ..write('capturedAt: $capturedAt, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('accuracyMeters: $accuracyMeters, ')
          ..write('address: $address, ')
          ..write('locationOutcome: $locationOutcome, ')
          ..write('processingAttempts: $processingAttempts, ')
          ..write('watermarkLocaleCode: $watermarkLocaleCode, ')
          ..write('locationResolution: $locationResolution, ')
          ..write('originalDeletedAt: $originalDeletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsTable extends AppSettings
    with TableInfo<$AppSettingsTable, AppSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('global'),
  );
  static const VerificationMeta _themeModeMeta = const VerificationMeta(
    'themeMode',
  );
  @override
  late final GeneratedColumn<String> themeMode = GeneratedColumn<String>(
    'theme_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('system'),
  );
  static const VerificationMeta _localeCodeMeta = const VerificationMeta(
    'localeCode',
  );
  @override
  late final GeneratedColumn<String> localeCode = GeneratedColumn<String>(
    'locale_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _defaultWatermarkPositionMeta =
      const VerificationMeta('defaultWatermarkPosition');
  @override
  late final GeneratedColumn<String> defaultWatermarkPosition =
      GeneratedColumn<String>(
        'default_watermark_position',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('bottomLeft'),
      );
  static const VerificationMeta _defaultWatermarkOpacityMeta =
      const VerificationMeta('defaultWatermarkOpacity');
  @override
  late final GeneratedColumn<double> defaultWatermarkOpacity =
      GeneratedColumn<double>(
        'default_watermark_opacity',
        aliasedName,
        false,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
        defaultValue: const Constant(0.78),
      );
  static const VerificationMeta _defaultWatermarkAccentColorArgbMeta =
      const VerificationMeta('defaultWatermarkAccentColorArgb');
  @override
  late final GeneratedColumn<int> defaultWatermarkAccentColorArgb =
      GeneratedColumn<int>(
        'default_watermark_accent_color_argb',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
        defaultValue: const Constant(0xff37c58b),
      );
  static const VerificationMeta _defaultWatermarkFontScaleMeta =
      const VerificationMeta('defaultWatermarkFontScale');
  @override
  late final GeneratedColumn<double> defaultWatermarkFontScale =
      GeneratedColumn<double>(
        'default_watermark_font_scale',
        aliasedName,
        false,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
        defaultValue: const Constant(1.0),
      );
  static const VerificationMeta _locationPermissionPromptDismissedMeta =
      const VerificationMeta('locationPermissionPromptDismissed');
  @override
  late final GeneratedColumn<bool> locationPermissionPromptDismissed =
      GeneratedColumn<bool>(
        'location_permission_prompt_dismissed',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("location_permission_prompt_dismissed" IN (0, 1))',
        ),
        defaultValue: const Constant(false),
      );
  static const VerificationMeta _useDynamicColorMeta = const VerificationMeta(
    'useDynamicColor',
  );
  @override
  late final GeneratedColumn<bool> useDynamicColor = GeneratedColumn<bool>(
    'use_dynamic_color',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("use_dynamic_color" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _completionNotificationsEnabledMeta =
      const VerificationMeta('completionNotificationsEnabled');
  @override
  late final GeneratedColumn<bool> completionNotificationsEnabled =
      GeneratedColumn<bool>(
        'completion_notifications_enabled',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("completion_notifications_enabled" IN (0, 1))',
        ),
        defaultValue: const Constant(false),
      );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    themeMode,
    localeCode,
    defaultWatermarkPosition,
    defaultWatermarkOpacity,
    defaultWatermarkAccentColorArgb,
    defaultWatermarkFontScale,
    locationPermissionPromptDismissed,
    useDynamicColor,
    completionNotificationsEnabled,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppSetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('theme_mode')) {
      context.handle(
        _themeModeMeta,
        themeMode.isAcceptableOrUnknown(data['theme_mode']!, _themeModeMeta),
      );
    }
    if (data.containsKey('locale_code')) {
      context.handle(
        _localeCodeMeta,
        localeCode.isAcceptableOrUnknown(data['locale_code']!, _localeCodeMeta),
      );
    }
    if (data.containsKey('default_watermark_position')) {
      context.handle(
        _defaultWatermarkPositionMeta,
        defaultWatermarkPosition.isAcceptableOrUnknown(
          data['default_watermark_position']!,
          _defaultWatermarkPositionMeta,
        ),
      );
    }
    if (data.containsKey('default_watermark_opacity')) {
      context.handle(
        _defaultWatermarkOpacityMeta,
        defaultWatermarkOpacity.isAcceptableOrUnknown(
          data['default_watermark_opacity']!,
          _defaultWatermarkOpacityMeta,
        ),
      );
    }
    if (data.containsKey('default_watermark_accent_color_argb')) {
      context.handle(
        _defaultWatermarkAccentColorArgbMeta,
        defaultWatermarkAccentColorArgb.isAcceptableOrUnknown(
          data['default_watermark_accent_color_argb']!,
          _defaultWatermarkAccentColorArgbMeta,
        ),
      );
    }
    if (data.containsKey('default_watermark_font_scale')) {
      context.handle(
        _defaultWatermarkFontScaleMeta,
        defaultWatermarkFontScale.isAcceptableOrUnknown(
          data['default_watermark_font_scale']!,
          _defaultWatermarkFontScaleMeta,
        ),
      );
    }
    if (data.containsKey('location_permission_prompt_dismissed')) {
      context.handle(
        _locationPermissionPromptDismissedMeta,
        locationPermissionPromptDismissed.isAcceptableOrUnknown(
          data['location_permission_prompt_dismissed']!,
          _locationPermissionPromptDismissedMeta,
        ),
      );
    }
    if (data.containsKey('use_dynamic_color')) {
      context.handle(
        _useDynamicColorMeta,
        useDynamicColor.isAcceptableOrUnknown(
          data['use_dynamic_color']!,
          _useDynamicColorMeta,
        ),
      );
    }
    if (data.containsKey('completion_notifications_enabled')) {
      context.handle(
        _completionNotificationsEnabledMeta,
        completionNotificationsEnabled.isAcceptableOrUnknown(
          data['completion_notifications_enabled']!,
          _completionNotificationsEnabledMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AppSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSetting(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      themeMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}theme_mode'],
      )!,
      localeCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}locale_code'],
      ),
      defaultWatermarkPosition: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}default_watermark_position'],
      )!,
      defaultWatermarkOpacity: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}default_watermark_opacity'],
      )!,
      defaultWatermarkAccentColorArgb: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}default_watermark_accent_color_argb'],
      )!,
      defaultWatermarkFontScale: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}default_watermark_font_scale'],
      )!,
      locationPermissionPromptDismissed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}location_permission_prompt_dismissed'],
      )!,
      useDynamicColor: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}use_dynamic_color'],
      )!,
      completionNotificationsEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}completion_notifications_enabled'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $AppSettingsTable createAlias(String alias) {
    return $AppSettingsTable(attachedDatabase, alias);
  }
}

class AppSetting extends DataClass implements Insertable<AppSetting> {
  final String id;
  final String themeMode;
  final String? localeCode;
  final String defaultWatermarkPosition;
  final double defaultWatermarkOpacity;
  final int defaultWatermarkAccentColorArgb;
  final double defaultWatermarkFontScale;
  final bool locationPermissionPromptDismissed;
  final bool useDynamicColor;
  final bool completionNotificationsEnabled;
  final DateTime updatedAt;
  const AppSetting({
    required this.id,
    required this.themeMode,
    this.localeCode,
    required this.defaultWatermarkPosition,
    required this.defaultWatermarkOpacity,
    required this.defaultWatermarkAccentColorArgb,
    required this.defaultWatermarkFontScale,
    required this.locationPermissionPromptDismissed,
    required this.useDynamicColor,
    required this.completionNotificationsEnabled,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['theme_mode'] = Variable<String>(themeMode);
    if (!nullToAbsent || localeCode != null) {
      map['locale_code'] = Variable<String>(localeCode);
    }
    map['default_watermark_position'] = Variable<String>(
      defaultWatermarkPosition,
    );
    map['default_watermark_opacity'] = Variable<double>(
      defaultWatermarkOpacity,
    );
    map['default_watermark_accent_color_argb'] = Variable<int>(
      defaultWatermarkAccentColorArgb,
    );
    map['default_watermark_font_scale'] = Variable<double>(
      defaultWatermarkFontScale,
    );
    map['location_permission_prompt_dismissed'] = Variable<bool>(
      locationPermissionPromptDismissed,
    );
    map['use_dynamic_color'] = Variable<bool>(useDynamicColor);
    map['completion_notifications_enabled'] = Variable<bool>(
      completionNotificationsEnabled,
    );
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  AppSettingsCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsCompanion(
      id: Value(id),
      themeMode: Value(themeMode),
      localeCode: localeCode == null && nullToAbsent
          ? const Value.absent()
          : Value(localeCode),
      defaultWatermarkPosition: Value(defaultWatermarkPosition),
      defaultWatermarkOpacity: Value(defaultWatermarkOpacity),
      defaultWatermarkAccentColorArgb: Value(defaultWatermarkAccentColorArgb),
      defaultWatermarkFontScale: Value(defaultWatermarkFontScale),
      locationPermissionPromptDismissed: Value(
        locationPermissionPromptDismissed,
      ),
      useDynamicColor: Value(useDynamicColor),
      completionNotificationsEnabled: Value(completionNotificationsEnabled),
      updatedAt: Value(updatedAt),
    );
  }

  factory AppSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSetting(
      id: serializer.fromJson<String>(json['id']),
      themeMode: serializer.fromJson<String>(json['themeMode']),
      localeCode: serializer.fromJson<String?>(json['localeCode']),
      defaultWatermarkPosition: serializer.fromJson<String>(
        json['defaultWatermarkPosition'],
      ),
      defaultWatermarkOpacity: serializer.fromJson<double>(
        json['defaultWatermarkOpacity'],
      ),
      defaultWatermarkAccentColorArgb: serializer.fromJson<int>(
        json['defaultWatermarkAccentColorArgb'],
      ),
      defaultWatermarkFontScale: serializer.fromJson<double>(
        json['defaultWatermarkFontScale'],
      ),
      locationPermissionPromptDismissed: serializer.fromJson<bool>(
        json['locationPermissionPromptDismissed'],
      ),
      useDynamicColor: serializer.fromJson<bool>(json['useDynamicColor']),
      completionNotificationsEnabled: serializer.fromJson<bool>(
        json['completionNotificationsEnabled'],
      ),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'themeMode': serializer.toJson<String>(themeMode),
      'localeCode': serializer.toJson<String?>(localeCode),
      'defaultWatermarkPosition': serializer.toJson<String>(
        defaultWatermarkPosition,
      ),
      'defaultWatermarkOpacity': serializer.toJson<double>(
        defaultWatermarkOpacity,
      ),
      'defaultWatermarkAccentColorArgb': serializer.toJson<int>(
        defaultWatermarkAccentColorArgb,
      ),
      'defaultWatermarkFontScale': serializer.toJson<double>(
        defaultWatermarkFontScale,
      ),
      'locationPermissionPromptDismissed': serializer.toJson<bool>(
        locationPermissionPromptDismissed,
      ),
      'useDynamicColor': serializer.toJson<bool>(useDynamicColor),
      'completionNotificationsEnabled': serializer.toJson<bool>(
        completionNotificationsEnabled,
      ),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  AppSetting copyWith({
    String? id,
    String? themeMode,
    Value<String?> localeCode = const Value.absent(),
    String? defaultWatermarkPosition,
    double? defaultWatermarkOpacity,
    int? defaultWatermarkAccentColorArgb,
    double? defaultWatermarkFontScale,
    bool? locationPermissionPromptDismissed,
    bool? useDynamicColor,
    bool? completionNotificationsEnabled,
    DateTime? updatedAt,
  }) => AppSetting(
    id: id ?? this.id,
    themeMode: themeMode ?? this.themeMode,
    localeCode: localeCode.present ? localeCode.value : this.localeCode,
    defaultWatermarkPosition:
        defaultWatermarkPosition ?? this.defaultWatermarkPosition,
    defaultWatermarkOpacity:
        defaultWatermarkOpacity ?? this.defaultWatermarkOpacity,
    defaultWatermarkAccentColorArgb:
        defaultWatermarkAccentColorArgb ?? this.defaultWatermarkAccentColorArgb,
    defaultWatermarkFontScale:
        defaultWatermarkFontScale ?? this.defaultWatermarkFontScale,
    locationPermissionPromptDismissed:
        locationPermissionPromptDismissed ??
        this.locationPermissionPromptDismissed,
    useDynamicColor: useDynamicColor ?? this.useDynamicColor,
    completionNotificationsEnabled:
        completionNotificationsEnabled ?? this.completionNotificationsEnabled,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  AppSetting copyWithCompanion(AppSettingsCompanion data) {
    return AppSetting(
      id: data.id.present ? data.id.value : this.id,
      themeMode: data.themeMode.present ? data.themeMode.value : this.themeMode,
      localeCode: data.localeCode.present
          ? data.localeCode.value
          : this.localeCode,
      defaultWatermarkPosition: data.defaultWatermarkPosition.present
          ? data.defaultWatermarkPosition.value
          : this.defaultWatermarkPosition,
      defaultWatermarkOpacity: data.defaultWatermarkOpacity.present
          ? data.defaultWatermarkOpacity.value
          : this.defaultWatermarkOpacity,
      defaultWatermarkAccentColorArgb:
          data.defaultWatermarkAccentColorArgb.present
          ? data.defaultWatermarkAccentColorArgb.value
          : this.defaultWatermarkAccentColorArgb,
      defaultWatermarkFontScale: data.defaultWatermarkFontScale.present
          ? data.defaultWatermarkFontScale.value
          : this.defaultWatermarkFontScale,
      locationPermissionPromptDismissed:
          data.locationPermissionPromptDismissed.present
          ? data.locationPermissionPromptDismissed.value
          : this.locationPermissionPromptDismissed,
      useDynamicColor: data.useDynamicColor.present
          ? data.useDynamicColor.value
          : this.useDynamicColor,
      completionNotificationsEnabled:
          data.completionNotificationsEnabled.present
          ? data.completionNotificationsEnabled.value
          : this.completionNotificationsEnabled,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSetting(')
          ..write('id: $id, ')
          ..write('themeMode: $themeMode, ')
          ..write('localeCode: $localeCode, ')
          ..write('defaultWatermarkPosition: $defaultWatermarkPosition, ')
          ..write('defaultWatermarkOpacity: $defaultWatermarkOpacity, ')
          ..write(
            'defaultWatermarkAccentColorArgb: $defaultWatermarkAccentColorArgb, ',
          )
          ..write('defaultWatermarkFontScale: $defaultWatermarkFontScale, ')
          ..write(
            'locationPermissionPromptDismissed: $locationPermissionPromptDismissed, ',
          )
          ..write('useDynamicColor: $useDynamicColor, ')
          ..write(
            'completionNotificationsEnabled: $completionNotificationsEnabled, ',
          )
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    themeMode,
    localeCode,
    defaultWatermarkPosition,
    defaultWatermarkOpacity,
    defaultWatermarkAccentColorArgb,
    defaultWatermarkFontScale,
    locationPermissionPromptDismissed,
    useDynamicColor,
    completionNotificationsEnabled,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSetting &&
          other.id == this.id &&
          other.themeMode == this.themeMode &&
          other.localeCode == this.localeCode &&
          other.defaultWatermarkPosition == this.defaultWatermarkPosition &&
          other.defaultWatermarkOpacity == this.defaultWatermarkOpacity &&
          other.defaultWatermarkAccentColorArgb ==
              this.defaultWatermarkAccentColorArgb &&
          other.defaultWatermarkFontScale == this.defaultWatermarkFontScale &&
          other.locationPermissionPromptDismissed ==
              this.locationPermissionPromptDismissed &&
          other.useDynamicColor == this.useDynamicColor &&
          other.completionNotificationsEnabled ==
              this.completionNotificationsEnabled &&
          other.updatedAt == this.updatedAt);
}

class AppSettingsCompanion extends UpdateCompanion<AppSetting> {
  final Value<String> id;
  final Value<String> themeMode;
  final Value<String?> localeCode;
  final Value<String> defaultWatermarkPosition;
  final Value<double> defaultWatermarkOpacity;
  final Value<int> defaultWatermarkAccentColorArgb;
  final Value<double> defaultWatermarkFontScale;
  final Value<bool> locationPermissionPromptDismissed;
  final Value<bool> useDynamicColor;
  final Value<bool> completionNotificationsEnabled;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const AppSettingsCompanion({
    this.id = const Value.absent(),
    this.themeMode = const Value.absent(),
    this.localeCode = const Value.absent(),
    this.defaultWatermarkPosition = const Value.absent(),
    this.defaultWatermarkOpacity = const Value.absent(),
    this.defaultWatermarkAccentColorArgb = const Value.absent(),
    this.defaultWatermarkFontScale = const Value.absent(),
    this.locationPermissionPromptDismissed = const Value.absent(),
    this.useDynamicColor = const Value.absent(),
    this.completionNotificationsEnabled = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppSettingsCompanion.insert({
    this.id = const Value.absent(),
    this.themeMode = const Value.absent(),
    this.localeCode = const Value.absent(),
    this.defaultWatermarkPosition = const Value.absent(),
    this.defaultWatermarkOpacity = const Value.absent(),
    this.defaultWatermarkAccentColorArgb = const Value.absent(),
    this.defaultWatermarkFontScale = const Value.absent(),
    this.locationPermissionPromptDismissed = const Value.absent(),
    this.useDynamicColor = const Value.absent(),
    this.completionNotificationsEnabled = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : updatedAt = Value(updatedAt);
  static Insertable<AppSetting> custom({
    Expression<String>? id,
    Expression<String>? themeMode,
    Expression<String>? localeCode,
    Expression<String>? defaultWatermarkPosition,
    Expression<double>? defaultWatermarkOpacity,
    Expression<int>? defaultWatermarkAccentColorArgb,
    Expression<double>? defaultWatermarkFontScale,
    Expression<bool>? locationPermissionPromptDismissed,
    Expression<bool>? useDynamicColor,
    Expression<bool>? completionNotificationsEnabled,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (themeMode != null) 'theme_mode': themeMode,
      if (localeCode != null) 'locale_code': localeCode,
      if (defaultWatermarkPosition != null)
        'default_watermark_position': defaultWatermarkPosition,
      if (defaultWatermarkOpacity != null)
        'default_watermark_opacity': defaultWatermarkOpacity,
      if (defaultWatermarkAccentColorArgb != null)
        'default_watermark_accent_color_argb': defaultWatermarkAccentColorArgb,
      if (defaultWatermarkFontScale != null)
        'default_watermark_font_scale': defaultWatermarkFontScale,
      if (locationPermissionPromptDismissed != null)
        'location_permission_prompt_dismissed':
            locationPermissionPromptDismissed,
      if (useDynamicColor != null) 'use_dynamic_color': useDynamicColor,
      if (completionNotificationsEnabled != null)
        'completion_notifications_enabled': completionNotificationsEnabled,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppSettingsCompanion copyWith({
    Value<String>? id,
    Value<String>? themeMode,
    Value<String?>? localeCode,
    Value<String>? defaultWatermarkPosition,
    Value<double>? defaultWatermarkOpacity,
    Value<int>? defaultWatermarkAccentColorArgb,
    Value<double>? defaultWatermarkFontScale,
    Value<bool>? locationPermissionPromptDismissed,
    Value<bool>? useDynamicColor,
    Value<bool>? completionNotificationsEnabled,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return AppSettingsCompanion(
      id: id ?? this.id,
      themeMode: themeMode ?? this.themeMode,
      localeCode: localeCode ?? this.localeCode,
      defaultWatermarkPosition:
          defaultWatermarkPosition ?? this.defaultWatermarkPosition,
      defaultWatermarkOpacity:
          defaultWatermarkOpacity ?? this.defaultWatermarkOpacity,
      defaultWatermarkAccentColorArgb:
          defaultWatermarkAccentColorArgb ??
          this.defaultWatermarkAccentColorArgb,
      defaultWatermarkFontScale:
          defaultWatermarkFontScale ?? this.defaultWatermarkFontScale,
      locationPermissionPromptDismissed:
          locationPermissionPromptDismissed ??
          this.locationPermissionPromptDismissed,
      useDynamicColor: useDynamicColor ?? this.useDynamicColor,
      completionNotificationsEnabled:
          completionNotificationsEnabled ?? this.completionNotificationsEnabled,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (themeMode.present) {
      map['theme_mode'] = Variable<String>(themeMode.value);
    }
    if (localeCode.present) {
      map['locale_code'] = Variable<String>(localeCode.value);
    }
    if (defaultWatermarkPosition.present) {
      map['default_watermark_position'] = Variable<String>(
        defaultWatermarkPosition.value,
      );
    }
    if (defaultWatermarkOpacity.present) {
      map['default_watermark_opacity'] = Variable<double>(
        defaultWatermarkOpacity.value,
      );
    }
    if (defaultWatermarkAccentColorArgb.present) {
      map['default_watermark_accent_color_argb'] = Variable<int>(
        defaultWatermarkAccentColorArgb.value,
      );
    }
    if (defaultWatermarkFontScale.present) {
      map['default_watermark_font_scale'] = Variable<double>(
        defaultWatermarkFontScale.value,
      );
    }
    if (locationPermissionPromptDismissed.present) {
      map['location_permission_prompt_dismissed'] = Variable<bool>(
        locationPermissionPromptDismissed.value,
      );
    }
    if (useDynamicColor.present) {
      map['use_dynamic_color'] = Variable<bool>(useDynamicColor.value);
    }
    if (completionNotificationsEnabled.present) {
      map['completion_notifications_enabled'] = Variable<bool>(
        completionNotificationsEnabled.value,
      );
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsCompanion(')
          ..write('id: $id, ')
          ..write('themeMode: $themeMode, ')
          ..write('localeCode: $localeCode, ')
          ..write('defaultWatermarkPosition: $defaultWatermarkPosition, ')
          ..write('defaultWatermarkOpacity: $defaultWatermarkOpacity, ')
          ..write(
            'defaultWatermarkAccentColorArgb: $defaultWatermarkAccentColorArgb, ',
          )
          ..write('defaultWatermarkFontScale: $defaultWatermarkFontScale, ')
          ..write(
            'locationPermissionPromptDismissed: $locationPermissionPromptDismissed, ',
          )
          ..write('useDynamicColor: $useDynamicColor, ')
          ..write(
            'completionNotificationsEnabled: $completionNotificationsEnabled, ',
          )
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ProjectsTable projects = $ProjectsTable(this);
  late final $CaptureRecordsTable captureRecords = $CaptureRecordsTable(this);
  late final $AppSettingsTable appSettings = $AppSettingsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    projects,
    captureRecords,
    appSettings,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'projects',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('captures', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$ProjectsTableCreateCompanionBuilder =
    ProjectsCompanion Function({
      required String id,
      required String name,
      Value<String?> description,
      Value<String> watermarkPosition,
      Value<double> watermarkOpacity,
      Value<int> watermarkAccentColorArgb,
      Value<double> watermarkFontScale,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$ProjectsTableUpdateCompanionBuilder =
    ProjectsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String?> description,
      Value<String> watermarkPosition,
      Value<double> watermarkOpacity,
      Value<int> watermarkAccentColorArgb,
      Value<double> watermarkFontScale,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$ProjectsTableReferences
    extends BaseReferences<_$AppDatabase, $ProjectsTable, Project> {
  $$ProjectsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$CaptureRecordsTable, List<CaptureRecord>>
  _captureRecordsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.captureRecords,
    aliasName: 'projects__id__captures__project_id',
  );

  $$CaptureRecordsTableProcessedTableManager get captureRecordsRefs {
    final manager = $$CaptureRecordsTableTableManager(
      $_db,
      $_db.captureRecords,
    ).filter((f) => f.projectId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_captureRecordsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ProjectsTableFilterComposer
    extends Composer<_$AppDatabase, $ProjectsTable> {
  $$ProjectsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get watermarkPosition => $composableBuilder(
    column: $table.watermarkPosition,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get watermarkOpacity => $composableBuilder(
    column: $table.watermarkOpacity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get watermarkAccentColorArgb => $composableBuilder(
    column: $table.watermarkAccentColorArgb,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get watermarkFontScale => $composableBuilder(
    column: $table.watermarkFontScale,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> captureRecordsRefs(
    Expression<bool> Function($$CaptureRecordsTableFilterComposer f) f,
  ) {
    final $$CaptureRecordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.captureRecords,
      getReferencedColumn: (t) => t.projectId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CaptureRecordsTableFilterComposer(
            $db: $db,
            $table: $db.captureRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ProjectsTableOrderingComposer
    extends Composer<_$AppDatabase, $ProjectsTable> {
  $$ProjectsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get watermarkPosition => $composableBuilder(
    column: $table.watermarkPosition,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get watermarkOpacity => $composableBuilder(
    column: $table.watermarkOpacity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get watermarkAccentColorArgb => $composableBuilder(
    column: $table.watermarkAccentColorArgb,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get watermarkFontScale => $composableBuilder(
    column: $table.watermarkFontScale,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProjectsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProjectsTable> {
  $$ProjectsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get watermarkPosition => $composableBuilder(
    column: $table.watermarkPosition,
    builder: (column) => column,
  );

  GeneratedColumn<double> get watermarkOpacity => $composableBuilder(
    column: $table.watermarkOpacity,
    builder: (column) => column,
  );

  GeneratedColumn<int> get watermarkAccentColorArgb => $composableBuilder(
    column: $table.watermarkAccentColorArgb,
    builder: (column) => column,
  );

  GeneratedColumn<double> get watermarkFontScale => $composableBuilder(
    column: $table.watermarkFontScale,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> captureRecordsRefs<T extends Object>(
    Expression<T> Function($$CaptureRecordsTableAnnotationComposer a) f,
  ) {
    final $$CaptureRecordsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.captureRecords,
      getReferencedColumn: (t) => t.projectId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CaptureRecordsTableAnnotationComposer(
            $db: $db,
            $table: $db.captureRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ProjectsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProjectsTable,
          Project,
          $$ProjectsTableFilterComposer,
          $$ProjectsTableOrderingComposer,
          $$ProjectsTableAnnotationComposer,
          $$ProjectsTableCreateCompanionBuilder,
          $$ProjectsTableUpdateCompanionBuilder,
          (Project, $$ProjectsTableReferences),
          Project,
          PrefetchHooks Function({bool captureRecordsRefs})
        > {
  $$ProjectsTableTableManager(_$AppDatabase db, $ProjectsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProjectsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProjectsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProjectsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String> watermarkPosition = const Value.absent(),
                Value<double> watermarkOpacity = const Value.absent(),
                Value<int> watermarkAccentColorArgb = const Value.absent(),
                Value<double> watermarkFontScale = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProjectsCompanion(
                id: id,
                name: name,
                description: description,
                watermarkPosition: watermarkPosition,
                watermarkOpacity: watermarkOpacity,
                watermarkAccentColorArgb: watermarkAccentColorArgb,
                watermarkFontScale: watermarkFontScale,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String?> description = const Value.absent(),
                Value<String> watermarkPosition = const Value.absent(),
                Value<double> watermarkOpacity = const Value.absent(),
                Value<int> watermarkAccentColorArgb = const Value.absent(),
                Value<double> watermarkFontScale = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ProjectsCompanion.insert(
                id: id,
                name: name,
                description: description,
                watermarkPosition: watermarkPosition,
                watermarkOpacity: watermarkOpacity,
                watermarkAccentColorArgb: watermarkAccentColorArgb,
                watermarkFontScale: watermarkFontScale,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ProjectsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({captureRecordsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (captureRecordsRefs) db.captureRecords,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (captureRecordsRefs)
                    await $_getPrefetchedData<
                      Project,
                      $ProjectsTable,
                      CaptureRecord
                    >(
                      currentTable: table,
                      referencedTable: $$ProjectsTableReferences
                          ._captureRecordsRefsTable(db),
                      managerFromTypedResult: (p0) => $$ProjectsTableReferences(
                        db,
                        table,
                        p0,
                      ).captureRecordsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.projectId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$ProjectsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProjectsTable,
      Project,
      $$ProjectsTableFilterComposer,
      $$ProjectsTableOrderingComposer,
      $$ProjectsTableAnnotationComposer,
      $$ProjectsTableCreateCompanionBuilder,
      $$ProjectsTableUpdateCompanionBuilder,
      (Project, $$ProjectsTableReferences),
      Project,
      PrefetchHooks Function({bool captureRecordsRefs})
    >;
typedef $$CaptureRecordsTableCreateCompanionBuilder =
    CaptureRecordsCompanion Function({
      required String id,
      required String projectId,
      Value<String?> photoNumber,
      required String workLocation,
      required String workContent,
      required String photographer,
      Value<String?> notes,
      required String originalPath,
      Value<String?> publishedUri,
      Value<String?> originalSha256,
      required CaptureStatus status,
      Value<String?> failureReason,
      required DateTime createdAt,
      Value<DateTime?> capturedAt,
      Value<double?> latitude,
      Value<double?> longitude,
      Value<double?> accuracyMeters,
      Value<String?> address,
      Value<String?> locationOutcome,
      Value<int> processingAttempts,
      Value<String> watermarkLocaleCode,
      Value<String> locationResolution,
      Value<DateTime?> originalDeletedAt,
      Value<int> rowid,
    });
typedef $$CaptureRecordsTableUpdateCompanionBuilder =
    CaptureRecordsCompanion Function({
      Value<String> id,
      Value<String> projectId,
      Value<String?> photoNumber,
      Value<String> workLocation,
      Value<String> workContent,
      Value<String> photographer,
      Value<String?> notes,
      Value<String> originalPath,
      Value<String?> publishedUri,
      Value<String?> originalSha256,
      Value<CaptureStatus> status,
      Value<String?> failureReason,
      Value<DateTime> createdAt,
      Value<DateTime?> capturedAt,
      Value<double?> latitude,
      Value<double?> longitude,
      Value<double?> accuracyMeters,
      Value<String?> address,
      Value<String?> locationOutcome,
      Value<int> processingAttempts,
      Value<String> watermarkLocaleCode,
      Value<String> locationResolution,
      Value<DateTime?> originalDeletedAt,
      Value<int> rowid,
    });

final class $$CaptureRecordsTableReferences
    extends BaseReferences<_$AppDatabase, $CaptureRecordsTable, CaptureRecord> {
  $$CaptureRecordsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ProjectsTable _projectIdTable(_$AppDatabase db) =>
      db.projects.createAlias('captures__project_id__projects__id');

  $$ProjectsTableProcessedTableManager get projectId {
    final $_column = $_itemColumn<String>('project_id')!;

    final manager = $$ProjectsTableTableManager(
      $_db,
      $_db.projects,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_projectIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$CaptureRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $CaptureRecordsTable> {
  $$CaptureRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get photoNumber => $composableBuilder(
    column: $table.photoNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workLocation => $composableBuilder(
    column: $table.workLocation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workContent => $composableBuilder(
    column: $table.workContent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get photographer => $composableBuilder(
    column: $table.photographer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originalPath => $composableBuilder(
    column: $table.originalPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get publishedUri => $composableBuilder(
    column: $table.publishedUri,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originalSha256 => $composableBuilder(
    column: $table.originalSha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<CaptureStatus, CaptureStatus, String>
  get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get failureReason => $composableBuilder(
    column: $table.failureReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get capturedAt => $composableBuilder(
    column: $table.capturedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get accuracyMeters => $composableBuilder(
    column: $table.accuracyMeters,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get locationOutcome => $composableBuilder(
    column: $table.locationOutcome,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get processingAttempts => $composableBuilder(
    column: $table.processingAttempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get watermarkLocaleCode => $composableBuilder(
    column: $table.watermarkLocaleCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get locationResolution => $composableBuilder(
    column: $table.locationResolution,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get originalDeletedAt => $composableBuilder(
    column: $table.originalDeletedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ProjectsTableFilterComposer get projectId {
    final $$ProjectsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.projectId,
      referencedTable: $db.projects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectsTableFilterComposer(
            $db: $db,
            $table: $db.projects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CaptureRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $CaptureRecordsTable> {
  $$CaptureRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get photoNumber => $composableBuilder(
    column: $table.photoNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workLocation => $composableBuilder(
    column: $table.workLocation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workContent => $composableBuilder(
    column: $table.workContent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get photographer => $composableBuilder(
    column: $table.photographer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originalPath => $composableBuilder(
    column: $table.originalPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get publishedUri => $composableBuilder(
    column: $table.publishedUri,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originalSha256 => $composableBuilder(
    column: $table.originalSha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get failureReason => $composableBuilder(
    column: $table.failureReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get capturedAt => $composableBuilder(
    column: $table.capturedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get accuracyMeters => $composableBuilder(
    column: $table.accuracyMeters,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get locationOutcome => $composableBuilder(
    column: $table.locationOutcome,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get processingAttempts => $composableBuilder(
    column: $table.processingAttempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get watermarkLocaleCode => $composableBuilder(
    column: $table.watermarkLocaleCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get locationResolution => $composableBuilder(
    column: $table.locationResolution,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get originalDeletedAt => $composableBuilder(
    column: $table.originalDeletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ProjectsTableOrderingComposer get projectId {
    final $$ProjectsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.projectId,
      referencedTable: $db.projects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectsTableOrderingComposer(
            $db: $db,
            $table: $db.projects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CaptureRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CaptureRecordsTable> {
  $$CaptureRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get photoNumber => $composableBuilder(
    column: $table.photoNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get workLocation => $composableBuilder(
    column: $table.workLocation,
    builder: (column) => column,
  );

  GeneratedColumn<String> get workContent => $composableBuilder(
    column: $table.workContent,
    builder: (column) => column,
  );

  GeneratedColumn<String> get photographer => $composableBuilder(
    column: $table.photographer,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get originalPath => $composableBuilder(
    column: $table.originalPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get publishedUri => $composableBuilder(
    column: $table.publishedUri,
    builder: (column) => column,
  );

  GeneratedColumn<String> get originalSha256 => $composableBuilder(
    column: $table.originalSha256,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<CaptureStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get failureReason => $composableBuilder(
    column: $table.failureReason,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get capturedAt => $composableBuilder(
    column: $table.capturedAt,
    builder: (column) => column,
  );

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<double> get accuracyMeters => $composableBuilder(
    column: $table.accuracyMeters,
    builder: (column) => column,
  );

  GeneratedColumn<String> get address =>
      $composableBuilder(column: $table.address, builder: (column) => column);

  GeneratedColumn<String> get locationOutcome => $composableBuilder(
    column: $table.locationOutcome,
    builder: (column) => column,
  );

  GeneratedColumn<int> get processingAttempts => $composableBuilder(
    column: $table.processingAttempts,
    builder: (column) => column,
  );

  GeneratedColumn<String> get watermarkLocaleCode => $composableBuilder(
    column: $table.watermarkLocaleCode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get locationResolution => $composableBuilder(
    column: $table.locationResolution,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get originalDeletedAt => $composableBuilder(
    column: $table.originalDeletedAt,
    builder: (column) => column,
  );

  $$ProjectsTableAnnotationComposer get projectId {
    final $$ProjectsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.projectId,
      referencedTable: $db.projects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectsTableAnnotationComposer(
            $db: $db,
            $table: $db.projects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CaptureRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CaptureRecordsTable,
          CaptureRecord,
          $$CaptureRecordsTableFilterComposer,
          $$CaptureRecordsTableOrderingComposer,
          $$CaptureRecordsTableAnnotationComposer,
          $$CaptureRecordsTableCreateCompanionBuilder,
          $$CaptureRecordsTableUpdateCompanionBuilder,
          (CaptureRecord, $$CaptureRecordsTableReferences),
          CaptureRecord,
          PrefetchHooks Function({bool projectId})
        > {
  $$CaptureRecordsTableTableManager(
    _$AppDatabase db,
    $CaptureRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CaptureRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CaptureRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CaptureRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> projectId = const Value.absent(),
                Value<String?> photoNumber = const Value.absent(),
                Value<String> workLocation = const Value.absent(),
                Value<String> workContent = const Value.absent(),
                Value<String> photographer = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String> originalPath = const Value.absent(),
                Value<String?> publishedUri = const Value.absent(),
                Value<String?> originalSha256 = const Value.absent(),
                Value<CaptureStatus> status = const Value.absent(),
                Value<String?> failureReason = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> capturedAt = const Value.absent(),
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<double?> accuracyMeters = const Value.absent(),
                Value<String?> address = const Value.absent(),
                Value<String?> locationOutcome = const Value.absent(),
                Value<int> processingAttempts = const Value.absent(),
                Value<String> watermarkLocaleCode = const Value.absent(),
                Value<String> locationResolution = const Value.absent(),
                Value<DateTime?> originalDeletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CaptureRecordsCompanion(
                id: id,
                projectId: projectId,
                photoNumber: photoNumber,
                workLocation: workLocation,
                workContent: workContent,
                photographer: photographer,
                notes: notes,
                originalPath: originalPath,
                publishedUri: publishedUri,
                originalSha256: originalSha256,
                status: status,
                failureReason: failureReason,
                createdAt: createdAt,
                capturedAt: capturedAt,
                latitude: latitude,
                longitude: longitude,
                accuracyMeters: accuracyMeters,
                address: address,
                locationOutcome: locationOutcome,
                processingAttempts: processingAttempts,
                watermarkLocaleCode: watermarkLocaleCode,
                locationResolution: locationResolution,
                originalDeletedAt: originalDeletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String projectId,
                Value<String?> photoNumber = const Value.absent(),
                required String workLocation,
                required String workContent,
                required String photographer,
                Value<String?> notes = const Value.absent(),
                required String originalPath,
                Value<String?> publishedUri = const Value.absent(),
                Value<String?> originalSha256 = const Value.absent(),
                required CaptureStatus status,
                Value<String?> failureReason = const Value.absent(),
                required DateTime createdAt,
                Value<DateTime?> capturedAt = const Value.absent(),
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<double?> accuracyMeters = const Value.absent(),
                Value<String?> address = const Value.absent(),
                Value<String?> locationOutcome = const Value.absent(),
                Value<int> processingAttempts = const Value.absent(),
                Value<String> watermarkLocaleCode = const Value.absent(),
                Value<String> locationResolution = const Value.absent(),
                Value<DateTime?> originalDeletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CaptureRecordsCompanion.insert(
                id: id,
                projectId: projectId,
                photoNumber: photoNumber,
                workLocation: workLocation,
                workContent: workContent,
                photographer: photographer,
                notes: notes,
                originalPath: originalPath,
                publishedUri: publishedUri,
                originalSha256: originalSha256,
                status: status,
                failureReason: failureReason,
                createdAt: createdAt,
                capturedAt: capturedAt,
                latitude: latitude,
                longitude: longitude,
                accuracyMeters: accuracyMeters,
                address: address,
                locationOutcome: locationOutcome,
                processingAttempts: processingAttempts,
                watermarkLocaleCode: watermarkLocaleCode,
                locationResolution: locationResolution,
                originalDeletedAt: originalDeletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$CaptureRecordsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({projectId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (projectId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.projectId,
                                referencedTable: $$CaptureRecordsTableReferences
                                    ._projectIdTable(db),
                                referencedColumn:
                                    $$CaptureRecordsTableReferences
                                        ._projectIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$CaptureRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CaptureRecordsTable,
      CaptureRecord,
      $$CaptureRecordsTableFilterComposer,
      $$CaptureRecordsTableOrderingComposer,
      $$CaptureRecordsTableAnnotationComposer,
      $$CaptureRecordsTableCreateCompanionBuilder,
      $$CaptureRecordsTableUpdateCompanionBuilder,
      (CaptureRecord, $$CaptureRecordsTableReferences),
      CaptureRecord,
      PrefetchHooks Function({bool projectId})
    >;
typedef $$AppSettingsTableCreateCompanionBuilder =
    AppSettingsCompanion Function({
      Value<String> id,
      Value<String> themeMode,
      Value<String?> localeCode,
      Value<String> defaultWatermarkPosition,
      Value<double> defaultWatermarkOpacity,
      Value<int> defaultWatermarkAccentColorArgb,
      Value<double> defaultWatermarkFontScale,
      Value<bool> locationPermissionPromptDismissed,
      Value<bool> useDynamicColor,
      Value<bool> completionNotificationsEnabled,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$AppSettingsTableUpdateCompanionBuilder =
    AppSettingsCompanion Function({
      Value<String> id,
      Value<String> themeMode,
      Value<String?> localeCode,
      Value<String> defaultWatermarkPosition,
      Value<double> defaultWatermarkOpacity,
      Value<int> defaultWatermarkAccentColorArgb,
      Value<double> defaultWatermarkFontScale,
      Value<bool> locationPermissionPromptDismissed,
      Value<bool> useDynamicColor,
      Value<bool> completionNotificationsEnabled,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$AppSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get themeMode => $composableBuilder(
    column: $table.themeMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localeCode => $composableBuilder(
    column: $table.localeCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get defaultWatermarkPosition => $composableBuilder(
    column: $table.defaultWatermarkPosition,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get defaultWatermarkOpacity => $composableBuilder(
    column: $table.defaultWatermarkOpacity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get defaultWatermarkAccentColorArgb => $composableBuilder(
    column: $table.defaultWatermarkAccentColorArgb,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get defaultWatermarkFontScale => $composableBuilder(
    column: $table.defaultWatermarkFontScale,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get locationPermissionPromptDismissed =>
      $composableBuilder(
        column: $table.locationPermissionPromptDismissed,
        builder: (column) => ColumnFilters(column),
      );

  ColumnFilters<bool> get useDynamicColor => $composableBuilder(
    column: $table.useDynamicColor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get completionNotificationsEnabled => $composableBuilder(
    column: $table.completionNotificationsEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get themeMode => $composableBuilder(
    column: $table.themeMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localeCode => $composableBuilder(
    column: $table.localeCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get defaultWatermarkPosition => $composableBuilder(
    column: $table.defaultWatermarkPosition,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get defaultWatermarkOpacity => $composableBuilder(
    column: $table.defaultWatermarkOpacity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get defaultWatermarkAccentColorArgb =>
      $composableBuilder(
        column: $table.defaultWatermarkAccentColorArgb,
        builder: (column) => ColumnOrderings(column),
      );

  ColumnOrderings<double> get defaultWatermarkFontScale => $composableBuilder(
    column: $table.defaultWatermarkFontScale,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get locationPermissionPromptDismissed =>
      $composableBuilder(
        column: $table.locationPermissionPromptDismissed,
        builder: (column) => ColumnOrderings(column),
      );

  ColumnOrderings<bool> get useDynamicColor => $composableBuilder(
    column: $table.useDynamicColor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get completionNotificationsEnabled =>
      $composableBuilder(
        column: $table.completionNotificationsEnabled,
        builder: (column) => ColumnOrderings(column),
      );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get themeMode =>
      $composableBuilder(column: $table.themeMode, builder: (column) => column);

  GeneratedColumn<String> get localeCode => $composableBuilder(
    column: $table.localeCode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get defaultWatermarkPosition => $composableBuilder(
    column: $table.defaultWatermarkPosition,
    builder: (column) => column,
  );

  GeneratedColumn<double> get defaultWatermarkOpacity => $composableBuilder(
    column: $table.defaultWatermarkOpacity,
    builder: (column) => column,
  );

  GeneratedColumn<int> get defaultWatermarkAccentColorArgb =>
      $composableBuilder(
        column: $table.defaultWatermarkAccentColorArgb,
        builder: (column) => column,
      );

  GeneratedColumn<double> get defaultWatermarkFontScale => $composableBuilder(
    column: $table.defaultWatermarkFontScale,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get locationPermissionPromptDismissed =>
      $composableBuilder(
        column: $table.locationPermissionPromptDismissed,
        builder: (column) => column,
      );

  GeneratedColumn<bool> get useDynamicColor => $composableBuilder(
    column: $table.useDynamicColor,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get completionNotificationsEnabled =>
      $composableBuilder(
        column: $table.completionNotificationsEnabled,
        builder: (column) => column,
      );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AppSettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AppSettingsTable,
          AppSetting,
          $$AppSettingsTableFilterComposer,
          $$AppSettingsTableOrderingComposer,
          $$AppSettingsTableAnnotationComposer,
          $$AppSettingsTableCreateCompanionBuilder,
          $$AppSettingsTableUpdateCompanionBuilder,
          (
            AppSetting,
            BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>,
          ),
          AppSetting,
          PrefetchHooks Function()
        > {
  $$AppSettingsTableTableManager(_$AppDatabase db, $AppSettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> themeMode = const Value.absent(),
                Value<String?> localeCode = const Value.absent(),
                Value<String> defaultWatermarkPosition = const Value.absent(),
                Value<double> defaultWatermarkOpacity = const Value.absent(),
                Value<int> defaultWatermarkAccentColorArgb =
                    const Value.absent(),
                Value<double> defaultWatermarkFontScale = const Value.absent(),
                Value<bool> locationPermissionPromptDismissed =
                    const Value.absent(),
                Value<bool> useDynamicColor = const Value.absent(),
                Value<bool> completionNotificationsEnabled =
                    const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion(
                id: id,
                themeMode: themeMode,
                localeCode: localeCode,
                defaultWatermarkPosition: defaultWatermarkPosition,
                defaultWatermarkOpacity: defaultWatermarkOpacity,
                defaultWatermarkAccentColorArgb:
                    defaultWatermarkAccentColorArgb,
                defaultWatermarkFontScale: defaultWatermarkFontScale,
                locationPermissionPromptDismissed:
                    locationPermissionPromptDismissed,
                useDynamicColor: useDynamicColor,
                completionNotificationsEnabled: completionNotificationsEnabled,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> themeMode = const Value.absent(),
                Value<String?> localeCode = const Value.absent(),
                Value<String> defaultWatermarkPosition = const Value.absent(),
                Value<double> defaultWatermarkOpacity = const Value.absent(),
                Value<int> defaultWatermarkAccentColorArgb =
                    const Value.absent(),
                Value<double> defaultWatermarkFontScale = const Value.absent(),
                Value<bool> locationPermissionPromptDismissed =
                    const Value.absent(),
                Value<bool> useDynamicColor = const Value.absent(),
                Value<bool> completionNotificationsEnabled =
                    const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion.insert(
                id: id,
                themeMode: themeMode,
                localeCode: localeCode,
                defaultWatermarkPosition: defaultWatermarkPosition,
                defaultWatermarkOpacity: defaultWatermarkOpacity,
                defaultWatermarkAccentColorArgb:
                    defaultWatermarkAccentColorArgb,
                defaultWatermarkFontScale: defaultWatermarkFontScale,
                locationPermissionPromptDismissed:
                    locationPermissionPromptDismissed,
                useDynamicColor: useDynamicColor,
                completionNotificationsEnabled: completionNotificationsEnabled,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AppSettingsTable,
      AppSetting,
      $$AppSettingsTableFilterComposer,
      $$AppSettingsTableOrderingComposer,
      $$AppSettingsTableAnnotationComposer,
      $$AppSettingsTableCreateCompanionBuilder,
      $$AppSettingsTableUpdateCompanionBuilder,
      (
        AppSetting,
        BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>,
      ),
      AppSetting,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ProjectsTableTableManager get projects =>
      $$ProjectsTableTableManager(_db, _db.projects);
  $$CaptureRecordsTableTableManager get captureRecords =>
      $$CaptureRecordsTableTableManager(_db, _db.captureRecords);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
}
