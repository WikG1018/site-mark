import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { CAPTURE_TEMPLATE_CONTENT_MAX_LENGTH, CAPTURE_TEMPLATE_LOCATION_MAX_LENGTH,
  CAPTURE_TEMPLATE_NAME_MAX_LENGTH, CAPTURE_TEMPLATE_PHOTOGRAPHER_MAX_LENGTH, formatPhotoNumber,
  captureTemplateNameKey, inspectCaptureFields, normalizeCaptureSearchTerms, normalizeCaptureTemplateName,
  normalizedProjectNameKey, safeProjectFileNameKey, validateTemplateField } from '../../domain/DomainRules';
import { AppSettingsRecord, CaptureDraft, CaptureFilter, CapturePage, CapturePageCursor,
  CaptureRecord, CaptureTemplateRecord, CaptureViewerWindow, ProjectRecord, ProjectSummary } from
  '../../domain/Models';
import { canCaptureTransition, canProjectTransition, CaptureStatus,
  ProjectLifecycleStatus } from '../../domain/StateMachine';
import { RestoredProjectInput } from '../../domain/RestoreModels';
import { CaptureViewerQueryExecutor, CaptureViewerQueryResultSet, CaptureViewerWindowQuery } from
  './CaptureViewerWindowQuery';

export interface CaptureWorkflowDatabase {
  projectById(id: string): Promise<ProjectRecord | null>;
  createCaptured(draft: CaptureDraft): Promise<CaptureRecord>;
  captureById(id: string): Promise<CaptureRecord | null>;
}

const DATABASE_NAME: string = 'sitemark_native.db';
const DATABASE_SCHEMA_VERSION: number = 14;
const DEFAULT_PAGE_SIZE: number = 50;

const SCHEMA_STATEMENTS: string[] = [
  `CREATE TABLE IF NOT EXISTS projects (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL CHECK(length(name) BETWEEN 1 AND 120),
    name_key TEXT NOT NULL,
    safe_name_key TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    restore_operation_id TEXT,
    lifecycle_status TEXT NOT NULL DEFAULT 'active'
      CHECK(lifecycle_status IN ('active','completed','archived')),
    is_pinned INTEGER NOT NULL DEFAULT 0 CHECK(is_pinned IN (0,1)),
    watermark_position TEXT NOT NULL DEFAULT 'bottomLeft',
    watermark_opacity REAL NOT NULL DEFAULT 0.78,
    watermark_accent_color_argb INTEGER NOT NULL DEFAULT 4281849227,
    watermark_font_scale REAL NOT NULL DEFAULT 1.0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )`,
  'CREATE UNIQUE INDEX IF NOT EXISTS projects_name_key_idx ON projects(name_key)',
  'CREATE UNIQUE INDEX IF NOT EXISTS projects_safe_name_key_idx ON projects(safe_name_key)',
  `CREATE TABLE IF NOT EXISTS captures (
    id TEXT PRIMARY KEY NOT NULL,
    project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    photo_number TEXT,
    work_location TEXT NOT NULL CHECK(length(work_location) BETWEEN 1 AND 160),
    work_content TEXT NOT NULL CHECK(length(work_content) BETWEEN 1 AND 240),
    photographer TEXT NOT NULL CHECK(length(photographer) BETWEEN 1 AND 80),
    notes TEXT NOT NULL DEFAULT '',
    original_path TEXT NOT NULL,
    rendered_path TEXT NOT NULL DEFAULT '',
    published_uri TEXT,
    original_sha256 TEXT,
    status TEXT NOT NULL CHECK(status IN ('pendingCamera','captured','rendering','ready','failed')),
    failure_reason TEXT,
    created_at INTEGER NOT NULL,
    captured_at INTEGER,
    latitude REAL,
    longitude REAL,
    accuracy_meters REAL,
    address TEXT,
    location_outcome TEXT,
    processing_attempts INTEGER NOT NULL DEFAULT 0,
    watermark_locale_code TEXT NOT NULL DEFAULT 'zh',
    location_resolution TEXT NOT NULL DEFAULT 'resolved',
    original_deleted_at INTEGER
  )`,
  'CREATE INDEX IF NOT EXISTS captures_status_idx ON captures(status)',
  `CREATE TRIGGER IF NOT EXISTS captures_fields_validate_insert BEFORE INSERT ON captures
   WHEN instr(NEW.work_location,char(0))>0 OR length(trim(NEW.work_location)) NOT BETWEEN 1 AND 160
     OR instr(NEW.work_content,char(0))>0 OR length(trim(NEW.work_content)) NOT BETWEEN 1 AND 240
     OR instr(NEW.photographer,char(0))>0 OR length(trim(NEW.photographer)) NOT BETWEEN 1 AND 80
     OR instr(NEW.notes,char(0))>0
   BEGIN SELECT RAISE(ABORT,'capture_form_invalid'); END`,
  `CREATE TRIGGER IF NOT EXISTS captures_fields_validate_update BEFORE UPDATE OF
   work_location,work_content,photographer,notes ON captures
   WHEN instr(NEW.work_location,char(0))>0 OR length(trim(NEW.work_location)) NOT BETWEEN 1 AND 160
     OR instr(NEW.work_content,char(0))>0 OR length(trim(NEW.work_content)) NOT BETWEEN 1 AND 240
     OR instr(NEW.photographer,char(0))>0 OR length(trim(NEW.photographer)) NOT BETWEEN 1 AND 80
     OR instr(NEW.notes,char(0))>0
   BEGIN SELECT RAISE(ABORT,'capture_form_invalid'); END`,
  'CREATE INDEX IF NOT EXISTS captures_sort_cursor_idx ON captures(COALESCE(captured_at, created_at) DESC, id DESC)',
  'CREATE INDEX IF NOT EXISTS captures_project_sort_cursor_idx ON captures(project_id, COALESCE(captured_at, created_at) DESC, id DESC)',
  `CREATE TABLE IF NOT EXISTS capture_templates (
    id TEXT PRIMARY KEY NOT NULL,
    project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    name_key TEXT NOT NULL,
    work_location TEXT NOT NULL,
    work_content TEXT NOT NULL,
    photographer TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    UNIQUE(project_id, name_key),
    CHECK(instr(name, char(0)) = 0 AND length(name) BETWEEN 1 AND 80),
    CHECK(instr(name_key, char(0)) = 0 AND length(name_key) BETWEEN 1 AND 80),
    CHECK(instr(work_location, char(0)) = 0 AND length(work_location) BETWEEN 1 AND 160),
    CHECK(instr(work_content, char(0)) = 0 AND length(work_content) BETWEEN 1 AND 240),
    CHECK(instr(photographer, char(0)) = 0 AND length(photographer) BETWEEN 1 AND 80)
  )`,
  'CREATE INDEX IF NOT EXISTS capture_templates_project_updated_name_idx ON capture_templates(project_id, updated_at DESC, name_key)',
  `CREATE TABLE IF NOT EXISTS app_settings (
    id TEXT PRIMARY KEY NOT NULL DEFAULT 'global',
    theme_mode TEXT NOT NULL DEFAULT 'system',
    locale_code TEXT,
    default_watermark_position TEXT NOT NULL DEFAULT 'bottomLeft',
    default_watermark_opacity REAL NOT NULL DEFAULT 0.78,
    default_watermark_accent_color_argb INTEGER NOT NULL DEFAULT 4281849227,
    default_watermark_font_scale REAL NOT NULL DEFAULT 1.0,
    location_permission_prompt_dismissed INTEGER NOT NULL DEFAULT 0,
    completion_notifications_enabled INTEGER NOT NULL DEFAULT 0,
    app_seed_color_argb INTEGER NOT NULL DEFAULT 4281849227,
    updated_at INTEGER NOT NULL
  )`,
  `CREATE TABLE IF NOT EXISTS capture_media_cleanups (
    published_uri TEXT PRIMARY KEY NOT NULL,
    capture_id TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    retry_count INTEGER NOT NULL DEFAULT 0,
    last_attempt_at INTEGER,
    stalled_at INTEGER
  )`,
  `CREATE TABLE IF NOT EXISTS capture_file_cleanups (
    path TEXT PRIMARY KEY NOT NULL,
    capture_id TEXT NOT NULL,
    kind TEXT NOT NULL CHECK(kind IN ('original','rendered')),
    created_at INTEGER NOT NULL,
    retry_count INTEGER NOT NULL DEFAULT 0,
    stalled_at INTEGER
  )`,
  `CREATE TABLE IF NOT EXISTS daily_sequences (
    local_date TEXT PRIMARY KEY NOT NULL,
    last_sequence INTEGER NOT NULL
  )`,
  `CREATE TABLE IF NOT EXISTS diagnostic_events (
    id TEXT PRIMARY KEY NOT NULL,
    category TEXT NOT NULL,
    outcome TEXT NOT NULL,
    duration_ms INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL
  )`,
  'CREATE INDEX IF NOT EXISTS diagnostic_events_created_idx ON diagnostic_events(created_at DESC)'
];

function parseCaptureStatus(value: string): CaptureStatus {
  switch (value) {
    case 'pendingCamera': return CaptureStatus.PENDING_CAMERA;
    case 'captured': return CaptureStatus.CAPTURED;
    case 'rendering': return CaptureStatus.RENDERING;
    case 'ready': return CaptureStatus.READY;
    case 'failed': return CaptureStatus.FAILED;
    default: throw new Error('invalid capture status');
  }
}

function parseLifecycle(value: string): ProjectLifecycleStatus {
  switch (value) {
    case 'active': return ProjectLifecycleStatus.ACTIVE;
    case 'completed': return ProjectLifecycleStatus.COMPLETED;
    case 'archived': return ProjectLifecycleStatus.ARCHIVED;
    default: throw new Error('invalid project lifecycle');
  }
}

function nullableString(rows: relationalStore.ResultSet, column: string): string {
  const index = rows.getColumnIndex(column);
  return rows.isColumnNull(index) ? '' : rows.getString(index);
}

function nullableNumber(rows: relationalStore.ResultSet, column: string): number | null {
  const index = rows.getColumnIndex(column);
  return rows.isColumnNull(index) ? null : rows.getDouble(index);
}

function nullableLong(rows: relationalStore.ResultSet, column: string): number | null {
  const index = rows.getColumnIndex(column);
  return rows.isColumnNull(index) ? null : rows.getLong(index);
}

function escapeLike(value: string): string {
  return value.replace(/\\/g, '\\\\').replace(/%/g, '\\%').replace(/_/g, '\\_');
}

function projectFromRow(rows: relationalStore.ResultSet): ProjectRecord {
  return new ProjectRecord({
    id: rows.getString(rows.getColumnIndex('id')),
    name: rows.getString(rows.getColumnIndex('name')),
    description: nullableString(rows, 'description'),
    lifecycleStatus: parseLifecycle(rows.getString(rows.getColumnIndex('lifecycle_status'))),
    isPinned: rows.getLong(rows.getColumnIndex('is_pinned')) === 1,
    watermarkPosition: rows.getString(rows.getColumnIndex('watermark_position')),
    watermarkOpacity: rows.getDouble(rows.getColumnIndex('watermark_opacity')),
    watermarkAccentColorArgb: rows.getLong(rows.getColumnIndex('watermark_accent_color_argb')),
    watermarkFontScale: rows.getDouble(rows.getColumnIndex('watermark_font_scale')),
    createdAt: rows.getLong(rows.getColumnIndex('created_at')),
    updatedAt: rows.getLong(rows.getColumnIndex('updated_at'))
  });
}

function captureFromRow(rows: relationalStore.ResultSet): CaptureRecord {
  return new CaptureRecord({
    id: rows.getString(rows.getColumnIndex('id')),
    projectId: rows.getString(rows.getColumnIndex('project_id')),
    projectName: nullableString(rows, 'project_name'),
    photoNumber: nullableString(rows, 'photo_number'),
    workLocation: rows.getString(rows.getColumnIndex('work_location')),
    workContent: rows.getString(rows.getColumnIndex('work_content')),
    photographer: rows.getString(rows.getColumnIndex('photographer')),
    notes: nullableString(rows, 'notes'),
    originalPath: rows.getString(rows.getColumnIndex('original_path')),
    renderedPath: nullableString(rows, 'rendered_path'),
    publishedUri: nullableString(rows, 'published_uri'),
    originalSha256: nullableString(rows, 'original_sha256'),
    status: parseCaptureStatus(rows.getString(rows.getColumnIndex('status'))),
    failureReason: nullableString(rows, 'failure_reason'),
    createdAt: rows.getLong(rows.getColumnIndex('created_at')),
    capturedAt: nullableLong(rows, 'captured_at') ?? rows.getLong(rows.getColumnIndex('created_at')),
    latitude: nullableNumber(rows, 'latitude'),
    longitude: nullableNumber(rows, 'longitude'),
    accuracyMeters: nullableNumber(rows, 'accuracy_meters'),
    address: nullableString(rows, 'address'),
    locationOutcome: nullableString(rows, 'location_outcome'),
    processingAttempts: rows.getLong(rows.getColumnIndex('processing_attempts')),
    watermarkLocaleCode: rows.getString(rows.getColumnIndex('watermark_locale_code')),
    locationResolution: rows.getString(rows.getColumnIndex('location_resolution')),
    originalDeletedAt: nullableLong(rows, 'original_deleted_at')
  });
}

class RdbCaptureViewerQueryResultSet implements CaptureViewerQueryResultSet {
  private readonly rows: relationalStore.ResultSet;

  constructor(rows: relationalStore.ResultSet) {
    this.rows = rows;
  }

  goToFirstRow(): boolean { return this.rows.goToFirstRow(); }
  goToNextRow(): boolean { return this.rows.goToNextRow(); }
  getColumnIndex(column: string): number { return this.rows.getColumnIndex(column); }
  isColumnNull(columnIndex: number): boolean { return this.rows.isColumnNull(columnIndex); }
  getString(columnIndex: number): string { return this.rows.getString(columnIndex); }
  getLong(columnIndex: number): number { return this.rows.getLong(columnIndex); }
  getDouble(columnIndex: number): number { return this.rows.getDouble(columnIndex); }
  close(): void { this.rows.close(); }
}

class RdbCaptureViewerQueryExecutor implements CaptureViewerQueryExecutor {
  private readonly transaction: relationalStore.Transaction;

  constructor(transaction: relationalStore.Transaction) {
    this.transaction = transaction;
  }

  async querySql(sql: string,
    args: relationalStore.ValueType[] = []): Promise<CaptureViewerQueryResultSet> {
    const rows = await this.transaction.querySql(sql, args);
    return new RdbCaptureViewerQueryResultSet(rows);
  }
}

export class AppDatabase implements CaptureWorkflowDatabase {
  private readonly store: relationalStore.RdbStore;

  private constructor(store: relationalStore.RdbStore) {
    this.store = store;
  }

  static async open(context: common.UIAbilityContext): Promise<AppDatabase> {
    const config: relationalStore.StoreConfig = {
      name: DATABASE_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    const store = await relationalStore.getRdbStore(context, config);
    const database = new AppDatabase(store);
    await database.initialize();
    return database;
  }

  private async initialize(): Promise<void> {
    await this.store.executeSql('PRAGMA foreign_keys = ON');
    for (const statement of SCHEMA_STATEMENTS) {
      await this.store.executeSql(statement);
    }
    await this.store.executeSql(`PRAGMA user_version = ${DATABASE_SCHEMA_VERSION}`);
    await this.store.executeSql(
      `INSERT OR IGNORE INTO app_settings(id, updated_at) VALUES('global', ?)`,
      [Date.now()]
    );
  }

  async createProject(name: string, description: string = ''): Promise<ProjectRecord> {
    const displayName = name.trim().replace(/\s+/g, ' ');
    if (displayName.length === 0 || displayName.length > 120) {
      throw new Error('project_name_invalid');
    }
    const id = util.generateRandomUUID();
    const now = Date.now();
    const defaults = await this.settings();
    try {
      await this.store.executeSql(
        `INSERT INTO projects(id,name,name_key,safe_name_key,description,watermark_position,
         watermark_opacity,watermark_accent_color_argb,watermark_font_scale,created_at,updated_at)
         VALUES(?,?,?,?,?,?,?,?,?,?,?)`,
        [id, displayName, normalizedProjectNameKey(displayName), safeProjectFileNameKey(displayName),
          description.trim(), defaults.defaultWatermarkPosition, defaults.defaultWatermarkOpacity,
          defaults.defaultWatermarkAccentColorArgb, defaults.defaultWatermarkFontScale, now, now]
      );
    } catch (_) {
      throw new Error('project_name_conflict');
    }
    const created = await this.projectById(id);
    if (created === null) {
      throw new Error('project_create_failed');
    }
    return created;
  }

  async renameProject(id: string, name: string): Promise<void> {
    const displayName = name.trim().replace(/\s+/g, ' ');
    if (displayName.length === 0 || displayName.length > 120) {
      throw new Error('project_name_invalid');
    }
    try {
      await this.store.executeSql(
        `UPDATE projects SET name=?, name_key=?, safe_name_key=?, updated_at=? WHERE id=?`,
        [displayName, normalizedProjectNameKey(displayName), safeProjectFileNameKey(displayName), Date.now(), id]
      );
    } catch (_) {
      throw new Error('project_name_conflict');
    }
  }

  async updateProject(id: string, description: string, watermarkPosition: string,
    watermarkOpacity: number, watermarkAccentColorArgb: number,
    watermarkFontScale: number): Promise<void> {
    const position = watermarkPosition === 'bottomRight' ? 'bottomRight' : 'bottomLeft';
    const opacity = Math.max(0.35, Math.min(1, watermarkOpacity));
    const fontScale = Math.max(0.75, Math.min(1.6, watermarkFontScale));
    await this.store.executeSql(
      `UPDATE projects SET description=?,watermark_position=?,watermark_opacity=?,
       watermark_accent_color_argb=?,watermark_font_scale=?,updated_at=? WHERE id=?`,
      [description.trim(), position, opacity, watermarkAccentColorArgb, fontScale, Date.now(), id]
    );
  }

  async projectById(id: string): Promise<ProjectRecord | null> {
    const rows = await this.store.querySql('SELECT * FROM projects WHERE id=? LIMIT 1', [id]);
    try {
      if (!rows.goToFirstRow()) {
        return null;
      }
      return projectFromRow(rows);
    } finally {
      rows.close();
    }
  }

  async projectNameAvailable(name: string): Promise<boolean> {
    const rows = await this.store.querySql(
      'SELECT 1 FROM projects WHERE name_key=? OR safe_name_key=? LIMIT 1',
      [normalizedProjectNameKey(name), safeProjectFileNameKey(name)]);
    try {
      return !rows.goToFirstRow();
    } finally {
      rows.close();
    }
  }

  async restoreProjects(projects: RestoredProjectInput[]): Promise<void> {
    if (projects.length === 0) {
      throw new Error('restore_empty');
    }
    const transaction = await this.store.createTransaction();
    try {
      const now = Date.now();
      for (const project of projects) {
        await transaction.execute(
          `INSERT INTO projects(id,name,name_key,safe_name_key,description,restore_operation_id,
           lifecycle_status,is_pinned,watermark_position,watermark_opacity,
           watermark_accent_color_argb,watermark_font_scale,created_at,updated_at)
           VALUES(?,?,?,?,?,NULL,?,?,?,?,?,?,?,?)`,
          [project.id, project.name, normalizedProjectNameKey(project.name),
            safeProjectFileNameKey(project.name), project.description, project.lifecycleStatus,
            project.isPinned ? 1 : 0, project.watermarkPosition, project.watermarkOpacity,
            project.watermarkAccentColorArgb, project.watermarkFontScale, project.createdAt, now]);
        for (const capture of project.captures) {
          const fields = inspectCaptureFields(capture.workLocation, capture.workContent,
            capture.photographer, capture.notes);
          if (!fields.valid) {
            throw new Error(`restore_capture_fields_invalid:${capture.photoNumber}`);
          }
          await transaction.execute(
            `INSERT INTO captures(id,project_id,photo_number,work_location,work_content,photographer,
             notes,original_path,rendered_path,published_uri,original_sha256,status,failure_reason,
             created_at,captured_at,latitude,longitude,accuracy_meters,address,location_outcome,
             processing_attempts,watermark_locale_code,location_resolution,original_deleted_at)
             VALUES(?,?,?,?,?,?,?,?,?,NULL,?,'ready',NULL,?,?,?,?,?,?,?,?,?,'resolved',?)`,
            [capture.id, project.id, capture.photoNumber, fields.location, fields.work,
              fields.photographer, fields.notes, capture.originalPath, capture.renderedPath,
              capture.originalSha256, capture.capturedAt, capture.capturedAt, capture.latitude,
              capture.longitude, capture.accuracyMeters, capture.address, 'restored', 0,
              capture.watermarkLocaleCode, capture.originalMissing ? now : null]);
        }
        for (const template of project.templates) {
          const name = normalizeCaptureTemplateName(template.name);
          const fields = inspectCaptureFields(template.workLocation, template.workContent,
            template.photographer, '');
          if (!validateTemplateField(name, CAPTURE_TEMPLATE_NAME_MAX_LENGTH) || !fields.valid) {
            throw new Error(`restore_template_fields_invalid:${template.name}`);
          }
          await transaction.execute(
            `INSERT INTO capture_templates(id,project_id,name,name_key,work_location,work_content,
             photographer,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?)`,
            [template.id, project.id, name, captureTemplateNameKey(name), fields.location,
              fields.work, fields.photographer, template.createdAt, template.updatedAt]);
        }
      }
      await transaction.commit();
    } catch (error) {
      await transaction.rollback();
      throw new Error((error as Error).message);
    }
  }

  async privatePathReferenced(path: string): Promise<boolean> {
    const rows = await this.store.querySql(
      'SELECT 1 FROM captures WHERE original_path=? OR rendered_path=? LIMIT 1', [path, path]);
    try {
      return rows.goToFirstRow();
    } finally {
      rows.close();
    }
  }

  async listProjectSummaries(status: ProjectLifecycleStatus, searchText: string = ''):
    Promise<ProjectSummary[]> {
    let sql = `SELECT p.*,
      COUNT(c.id) AS capture_count,
      COALESCE(SUM(CASE WHEN c.status='ready' THEN 1 ELSE 0 END),0) AS ready_count,
      COALESCE(SUM(CASE WHEN c.status IN ('captured','rendering','pendingCamera') THEN 1 ELSE 0 END),0)
        AS pending_count,
      COALESCE(MAX(COALESCE(c.captured_at,c.created_at)),0) AS latest_capture_at,
      COALESCE((SELECT GROUP_CONCAT(rendered_path, char(31)) FROM
        (SELECT rc.rendered_path AS rendered_path FROM captures rc
         WHERE rc.project_id=p.id AND rc.status='ready' AND rc.rendered_path<>''
         ORDER BY COALESCE(rc.captured_at,rc.created_at) DESC, rc.id DESC LIMIT 3)), '') AS recent_paths
      FROM projects p LEFT JOIN captures c ON c.project_id=p.id
      WHERE p.lifecycle_status=?`;
    const args: relationalStore.ValueType[] = [status];
    const terms = normalizeCaptureSearchTerms(searchText);
    for (const term of terms) {
      sql += ` AND (p.name LIKE ? ESCAPE '\\' OR p.description LIKE ? ESCAPE '\\')`;
      const pattern = `%${escapeLike(term)}%`;
      args.push(pattern, pattern);
    }
    sql += ` GROUP BY p.id ORDER BY p.is_pinned DESC, latest_capture_at DESC, p.updated_at DESC, p.id DESC`;
    const rows = await this.store.querySql(sql, args);
    const result: ProjectSummary[] = [];
    try {
      if (!rows.goToFirstRow()) {
        return result;
      }
      do {
        const encodedPaths = nullableString(rows, 'recent_paths');
        const paths = encodedPaths.length === 0 ? [] : encodedPaths.split(String.fromCharCode(31));
        result.push(new ProjectSummary(
          projectFromRow(rows),
          rows.getLong(rows.getColumnIndex('capture_count')),
          rows.getLong(rows.getColumnIndex('ready_count')),
          rows.getLong(rows.getColumnIndex('pending_count')),
          rows.getLong(rows.getColumnIndex('latest_capture_at')),
          paths
        ));
      } while (rows.goToNextRow());
      return result;
    } finally {
      rows.close();
    }
  }

  async setProjectPinned(id: string, pinned: boolean): Promise<void> {
    await this.store.executeSql('UPDATE projects SET is_pinned=?, updated_at=? WHERE id=?',
      [pinned ? 1 : 0, Date.now(), id]);
  }

  async listProjectsForFilter(): Promise<ProjectRecord[]> {
    const rows = await this.store.querySql(
      'SELECT * FROM projects ORDER BY is_pinned DESC, name_key ASC, id ASC');
    const result: ProjectRecord[] = [];
    try {
      if (rows.goToFirstRow()) {
        do {
          result.push(projectFromRow(rows));
        } while (rows.goToNextRow());
      }
      return result;
    } finally {
      rows.close();
    }
  }

  async setProjectLifecycle(id: string, target: ProjectLifecycleStatus,
    confirmFailed: boolean = false): Promise<void> {
    const project = await this.projectById(id);
    if (project === null || !canProjectTransition(project.lifecycleStatus, target)) {
      throw new Error('project_lifecycle_conflict');
    }
    if (target !== ProjectLifecycleStatus.ACTIVE) {
      const counts = await this.captureStateCounts(id);
      if (counts.processing > 0) {
        throw new Error('project_has_processing_captures');
      }
      if (counts.failed > 0 && !confirmFailed) {
        throw new Error('project_has_failed_captures');
      }
    }
    await this.store.executeSql(
      'UPDATE projects SET lifecycle_status=?, is_pinned=CASE WHEN ?=\'archived\' THEN 0 ELSE is_pinned END, updated_at=? WHERE id=?',
      [target, target, Date.now(), id]
    );
  }

  async deleteProject(id: string): Promise<void> {
    const counts = await this.captureStateCounts(id);
    if (counts.processing > 0) {
      throw new Error('project_has_processing_captures');
    }
    await this.store.executeSql('DELETE FROM projects WHERE id=?', [id]);
  }

  private async captureStateCounts(projectId: string): Promise<CaptureStateCounts> {
    const rows = await this.store.querySql(
      `SELECT COALESCE(SUM(CASE WHEN status IN ('pendingCamera','captured','rendering') THEN 1 ELSE 0 END),0)
        AS processing, COALESCE(SUM(CASE WHEN status='failed' THEN 1 ELSE 0 END),0) AS failed
       FROM captures WHERE project_id=?`, [projectId]);
    try {
      rows.goToFirstRow();
      return new CaptureStateCounts(
        rows.getLong(rows.getColumnIndex('processing')),
        rows.getLong(rows.getColumnIndex('failed'))
      );
    } finally {
      rows.close();
    }
  }

  async createCaptured(draft: CaptureDraft): Promise<CaptureRecord> {
    const project = await this.projectById(draft.projectId);
    if (project === null || project.lifecycleStatus !== ProjectLifecycleStatus.ACTIVE) {
      throw new Error('project_read_only');
    }
    const fields = inspectCaptureFields(draft.workLocation, draft.workContent, draft.photographer, draft.notes);
    if (!fields.valid) throw new Error('capture_form_invalid');
    const capturedDate = new Date(draft.capturedAt);
    const dateKey = `${capturedDate.getFullYear().toString().padStart(4, '0')}${
      (capturedDate.getMonth() + 1).toString().padStart(2, '0')}${capturedDate.getDate().toString().padStart(2, '0')}`;
    const transaction = await this.store.createTransaction();
    try {
      await transaction.execute(
        `INSERT INTO daily_sequences(local_date,last_sequence) VALUES(?,1)
         ON CONFLICT(local_date) DO UPDATE SET last_sequence=last_sequence+1`, [dateKey]);
      const sequenceResult = await transaction.querySql(
        'SELECT last_sequence FROM daily_sequences WHERE local_date=?', [dateKey]);
      let sequence = 0;
      try {
        if (sequenceResult.goToFirstRow()) {
          sequence = sequenceResult.getLong(sequenceResult.getColumnIndex('last_sequence'));
        }
      } finally {
        sequenceResult.close();
      }
      if (sequence < 1) {
        throw new Error('sequence_allocation_failed');
      }
      const photoNumber = formatPhotoNumber(project.name, capturedDate.getFullYear(),
        capturedDate.getMonth() + 1, capturedDate.getDate(), sequence);
      await transaction.execute(
        `INSERT INTO captures(id,project_id,photo_number,work_location,work_content,photographer,notes,
          original_path,status,created_at,captured_at,latitude,longitude,accuracy_meters,location_outcome,
          address,watermark_locale_code)
         VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
        [draft.id, draft.projectId, photoNumber, fields.location, fields.work,
          fields.photographer, fields.notes, draft.originalPath, CaptureStatus.CAPTURED,
          Date.now(), draft.capturedAt, draft.latitude, draft.longitude, draft.accuracyMeters,
          draft.locationOutcome, draft.address, draft.watermarkLocaleCode]
      );
      await transaction.execute('UPDATE projects SET updated_at=? WHERE id=?', [Date.now(), draft.projectId]);
      await transaction.commit();
    } catch (error) {
      await transaction.rollback();
      throw new Error((error as Error).message);
    }
    const created = await this.captureById(draft.id);
    if (created === null) {
      throw new Error('capture_create_failed');
    }
    return created;
  }

  async captureById(id: string): Promise<CaptureRecord | null> {
    const rows = await this.store.querySql(
      `SELECT c.*, p.name AS project_name FROM captures c
       JOIN projects p ON p.id=c.project_id WHERE c.id=? LIMIT 1`, [id]);
    try {
      if (!rows.goToFirstRow()) {
        return null;
      }
      return captureFromRow(rows);
    } finally {
      rows.close();
    }
  }

  async captureViewerWindow(captureId: string, radius: number = 2): Promise<CaptureViewerWindow> {
    const transaction = await this.store.createTransaction({
      transactionType: relationalStore.TransactionType.DEFERRED
    });
    try {
      const executor = new RdbCaptureViewerQueryExecutor(transaction);
      const window = await new CaptureViewerWindowQuery().load(executor, captureId, radius);
      await transaction.commit();
      return window;
    } catch (error) {
      await transaction.rollback();
      throw new Error((error as Error).message);
    }
  }

  async pendingCaptureIds(): Promise<string[]> {
    const rows = await this.store.querySql(
      `SELECT id FROM captures WHERE status IN ('captured','rendering')
       ORDER BY COALESCE(captured_at,created_at), id`);
    const result: string[] = [];
    try {
      if (rows.goToFirstRow()) {
        do {
          result.push(rows.getString(rows.getColumnIndex('id')));
        } while (rows.goToNextRow());
      }
      return result;
    } finally {
      rows.close();
    }
  }

  async listCaptures(filter: CaptureFilter, cursor: CapturePageCursor | null = null,
    pageSize: number = DEFAULT_PAGE_SIZE): Promise<CapturePage> {
    let sql = `SELECT c.*, p.name AS project_name FROM captures c
      JOIN projects p ON p.id=c.project_id WHERE 1=1`;
    const args: relationalStore.ValueType[] = [];
    if (filter.projectId.length > 0) {
      sql += ' AND c.project_id=?';
      args.push(filter.projectId);
    }
    const dateRange = this.dateRange(filter);
    if (dateRange !== null) {
      sql += ' AND COALESCE(c.captured_at,c.created_at)>=? AND COALESCE(c.captured_at,c.created_at)<?';
      args.push(dateRange.start, dateRange.end);
    }
    for (const term of normalizeCaptureSearchTerms(filter.searchText)) {
      const pattern = `%${escapeLike(term)}%`;
      sql += ` AND (COALESCE(c.photo_number,'') LIKE ? ESCAPE '\\'
        OR p.name LIKE ? ESCAPE '\\' OR c.work_location LIKE ? ESCAPE '\\'
        OR c.work_content LIKE ? ESCAPE '\\' OR c.photographer LIKE ? ESCAPE '\\'
        OR c.notes LIKE ? ESCAPE '\\')`;
      args.push(pattern, pattern, pattern, pattern, pattern, pattern);
    }
    if (cursor !== null) {
      sql += ` AND (COALESCE(c.captured_at,c.created_at)<?
        OR (COALESCE(c.captured_at,c.created_at)=? AND c.id<?))`;
      args.push(cursor.sortTime, cursor.sortTime, cursor.id);
    }
    sql += ' ORDER BY COALESCE(c.captured_at,c.created_at) DESC, c.id DESC LIMIT ?';
    args.push(pageSize + 1);
    const rows = await this.store.querySql(sql, args);
    const captures: CaptureRecord[] = [];
    try {
      if (rows.goToFirstRow()) {
        do {
          captures.push(captureFromRow(rows));
        } while (rows.goToNextRow());
      }
    } finally {
      rows.close();
    }
    const hasMore = captures.length > pageSize;
    if (hasMore) {
      captures.pop();
    }
    const last = captures.length === 0 ? null : captures[captures.length - 1];
    const next = hasMore && last !== null ? new CapturePageCursor(last.capturedAt, last.id) : null;
    return new CapturePage(captures, next);
  }

  async captureIds(filter: CaptureFilter): Promise<string[]> {
    let sql = `SELECT c.id FROM captures c
      JOIN projects p ON p.id=c.project_id WHERE 1=1`;
    const args: relationalStore.ValueType[] = [];
    if (filter.projectId.length > 0) {
      sql += ' AND c.project_id=?';
      args.push(filter.projectId);
    }
    const dateRange = this.dateRange(filter);
    if (dateRange !== null) {
      sql += ' AND COALESCE(c.captured_at,c.created_at)>=? AND COALESCE(c.captured_at,c.created_at)<?';
      args.push(dateRange.start, dateRange.end);
    }
    for (const term of normalizeCaptureSearchTerms(filter.searchText)) {
      const pattern = `%${escapeLike(term)}%`;
      sql += ` AND (COALESCE(c.photo_number,'') LIKE ? ESCAPE '\\'
        OR p.name LIKE ? ESCAPE '\\' OR c.work_location LIKE ? ESCAPE '\\'
        OR c.work_content LIKE ? ESCAPE '\\' OR c.photographer LIKE ? ESCAPE '\\'
        OR c.notes LIKE ? ESCAPE '\\')`;
      args.push(pattern, pattern, pattern, pattern, pattern, pattern);
    }
    sql += ' ORDER BY COALESCE(c.captured_at,c.created_at) DESC, c.id DESC';
    const rows = await this.store.querySql(sql, args);
    const result: string[] = [];
    try {
      if (rows.goToFirstRow()) {
        do {
          result.push(rows.getString(rows.getColumnIndex('id')));
        } while (rows.goToNextRow());
      }
      return result;
    } finally {
      rows.close();
    }
  }

  private dateRange(filter: CaptureFilter): DateRange | null {
    if (filter.year < 1) {
      return null;
    }
    const startMonth = filter.month > 0 ? filter.month - 1 : 0;
    const startDay = filter.day > 0 ? filter.day : 1;
    const start = new Date(filter.year, startMonth, startDay).getTime();
    let end: number;
    if (filter.day > 0) {
      end = new Date(filter.year, startMonth, filter.day + 1).getTime();
    } else if (filter.month > 0) {
      end = new Date(filter.year, filter.month, 1).getTime();
    } else {
      end = new Date(filter.year + 1, 0, 1).getTime();
    }
    return new DateRange(start, end);
  }

  async transitionCapture(id: string, next: CaptureStatus): Promise<void> {
    const capture = await this.captureById(id);
    if (capture === null || !canCaptureTransition(capture.status, next)) {
      throw new Error('capture_state_conflict');
    }
    await this.store.executeSql('UPDATE captures SET status=? WHERE id=? AND status=?',
      [next, id, capture.status]);
  }

  async markRendering(id: string): Promise<void> {
    const capture = await this.captureById(id);
    if (capture === null || !canCaptureTransition(capture.status, CaptureStatus.RENDERING)) {
      throw new Error('capture_state_conflict');
    }
    await this.store.executeSql(
      `UPDATE captures SET status='rendering', processing_attempts=processing_attempts+1,
       failure_reason=NULL WHERE id=? AND status=?`, [id, capture.status]);
  }

  async markReady(id: string, renderedPath: string, sha256: string, publishedUri: string,
    supersededUris: string[]): Promise<void> {
    const capture = await this.captureById(id);
    if (capture === null || !canCaptureTransition(capture.status, CaptureStatus.READY)) {
      throw new Error('capture_state_conflict');
    }
    const transaction = await this.store.createTransaction();
    try {
      await transaction.execute(
        `UPDATE captures SET status='ready', rendered_path=?, original_sha256=?, published_uri=?,
         failure_reason=NULL WHERE id=? AND status=?`,
        [renderedPath, sha256, publishedUri.length === 0 ? null : publishedUri, id, capture.status]);
      for (const uri of supersededUris) {
        if (uri.length > 0 && uri !== publishedUri) {
          await transaction.execute(
            `INSERT INTO capture_media_cleanups(published_uri,capture_id,created_at,retry_count,last_attempt_at,stalled_at)
             VALUES(?,?,?,0,NULL,NULL) ON CONFLICT(published_uri) DO UPDATE SET
             capture_id=excluded.capture_id, created_at=excluded.created_at, retry_count=0,
             last_attempt_at=NULL, stalled_at=NULL`, [uri, id, Date.now()]);
        }
      }
      await transaction.commit();
    } catch (error) {
      await transaction.rollback();
      throw new Error((error as Error).message);
    }
  }

  async markFailed(id: string, reason: string): Promise<void> {
    const capture = await this.captureById(id);
    if (capture === null || !canCaptureTransition(capture.status, CaptureStatus.FAILED)) {
      throw new Error('capture_state_conflict');
    }
    await this.store.executeSql('UPDATE captures SET status=?, failure_reason=? WHERE id=? AND status=?',
      [CaptureStatus.FAILED, reason, id, capture.status]);
  }

  async retryCapture(id: string): Promise<void> {
    await this.transitionCapture(id, CaptureStatus.CAPTURED);
  }

  async updateCaptureFields(id: string, workLocation: string, workContent: string,
    photographer: string, notes: string): Promise<void> {
    const fields = inspectCaptureFields(workLocation, workContent, photographer, notes);
    if (!fields.valid) throw new Error('capture_form_invalid');
    const changedValue = await this.store.execute(
      `UPDATE captures SET work_location=?, work_content=?, photographer=?, notes=?,
       status='captured', failure_reason=NULL WHERE id=? AND status IN ('ready','failed')
       AND original_deleted_at IS NULL AND original_path<>''
       AND EXISTS(SELECT 1 FROM projects WHERE projects.id=captures.project_id
         AND projects.lifecycle_status='active')`,
      [fields.location, fields.work, fields.photographer, fields.notes, id]
    );
    const changed = typeof changedValue === 'number' ? changedValue : 0;
    if (changed < 1) {
      throw new Error('capture_state_conflict');
    }
  }

  async setOriginalDeleted(id: string): Promise<void> {
    await this.store.executeSql('UPDATE captures SET original_deleted_at=? WHERE id=? AND original_deleted_at IS NULL',
      [Date.now(), id]);
  }

  async scheduleOriginalCleanup(id: string): Promise<void> {
    const capture = await this.captureById(id);
    if (capture === null || (capture.status !== CaptureStatus.READY &&
      capture.status !== CaptureStatus.FAILED)) {
      throw new Error('capture_original_cleanup_conflict');
    }
    if (!capture.hasOriginal()) {
      return;
    }
    const transaction = await this.store.createTransaction();
    try {
      await transaction.execute(
        `INSERT INTO capture_file_cleanups(path,capture_id,kind,created_at,retry_count,stalled_at)
         VALUES(?,?, 'original',?,0,NULL) ON CONFLICT(path) DO UPDATE SET
         capture_id=excluded.capture_id,kind='original',created_at=excluded.created_at,
         retry_count=0,stalled_at=NULL`, [capture.originalPath, id, Date.now()]);
      await transaction.execute(
        'UPDATE captures SET original_deleted_at=? WHERE id=? AND original_deleted_at IS NULL',
        [Date.now(), id]);
      await transaction.commit();
    } catch (error) {
      await transaction.rollback();
      throw new Error((error as Error).message);
    }
  }

  async deleteCapture(id: string): Promise<void> {
    const capture = await this.captureById(id);
    if (capture !== null && (capture.status === CaptureStatus.CAPTURED ||
      capture.status === CaptureStatus.RENDERING || capture.status === CaptureStatus.PENDING_CAMERA)) {
      throw new Error('capture_is_processing');
    }
    await this.store.executeSql('DELETE FROM captures WHERE id=?', [id]);
  }

  async scheduleCaptureDeletion(id: string): Promise<void> {
    const capture = await this.captureById(id);
    if (capture === null) {
      return;
    }
    if (capture.status === CaptureStatus.CAPTURED || capture.status === CaptureStatus.RENDERING ||
      capture.status === CaptureStatus.PENDING_CAMERA) {
      throw new Error('capture_is_processing');
    }
    const transaction = await this.store.createTransaction();
    try {
      await this.insertFileCleanup(transaction, capture.originalPath, id, 'original');
      await this.insertFileCleanup(transaction, capture.renderedPath, id, 'rendered');
      if (capture.publishedUri.length > 0) {
        await transaction.execute(
          `INSERT INTO capture_media_cleanups(published_uri,capture_id,created_at,retry_count,last_attempt_at,stalled_at)
           VALUES(?,?,?,0,NULL,NULL) ON CONFLICT(published_uri) DO UPDATE SET
           capture_id=excluded.capture_id,created_at=excluded.created_at,retry_count=0,
           last_attempt_at=NULL,stalled_at=NULL`, [capture.publishedUri, id, Date.now()]);
      }
      await transaction.execute('DELETE FROM captures WHERE id=?', [id]);
      await transaction.commit();
    } catch (error) {
      await transaction.rollback();
      throw new Error((error as Error).message);
    }
  }

  async scheduleProjectDeletion(id: string): Promise<void> {
    const counts = await this.captureStateCounts(id);
    if (counts.processing > 0) {
      throw new Error('project_has_processing_captures');
    }
    const transaction = await this.store.createTransaction();
    try {
      const rows = await transaction.querySql(
        'SELECT id,original_path,rendered_path FROM captures WHERE project_id=?', [id]);
      try {
        if (rows.goToFirstRow()) {
          do {
            const captureId = rows.getString(rows.getColumnIndex('id'));
            await this.insertFileCleanup(transaction,
              rows.getString(rows.getColumnIndex('original_path')), captureId, 'original');
            await this.insertFileCleanup(transaction,
              nullableString(rows, 'rendered_path'), captureId, 'rendered');
          } while (rows.goToNextRow());
        }
      } finally {
        rows.close();
      }
      // Project deletion intentionally preserves photos already saved to the
      // system album. Only app-private files and rows are removed.
      await transaction.execute('DELETE FROM projects WHERE id=?', [id]);
      await transaction.commit();
    } catch (error) {
      await transaction.rollback();
      throw new Error((error as Error).message);
    }
  }

  async pendingFileCleanups(limit: number = 50): Promise<PrivateFileCleanupTask[]> {
    const rows = await this.store.querySql(
      `SELECT path,capture_id,kind,retry_count FROM capture_file_cleanups
       WHERE stalled_at IS NULL ORDER BY created_at LIMIT ?`, [limit]);
    const result: PrivateFileCleanupTask[] = [];
    try {
      if (rows.goToFirstRow()) {
        do {
          result.push(new PrivateFileCleanupTask(
            rows.getString(rows.getColumnIndex('path')),
            rows.getString(rows.getColumnIndex('capture_id')),
            rows.getString(rows.getColumnIndex('kind')),
            rows.getLong(rows.getColumnIndex('retry_count'))
          ));
        } while (rows.goToNextRow());
      }
      return result;
    } finally {
      rows.close();
    }
  }

  async completeFileCleanup(path: string): Promise<void> {
    await this.store.executeSql('DELETE FROM capture_file_cleanups WHERE path=?', [path]);
  }

  async failFileCleanup(path: string, maxAttempts: number = 5): Promise<void> {
    await this.store.executeSql(
      `UPDATE capture_file_cleanups SET retry_count=retry_count+1,
       stalled_at=CASE WHEN retry_count+1>=? THEN ? ELSE NULL END WHERE path=?`,
      [maxAttempts, Date.now(), path]
    );
  }

  private async insertFileCleanup(transaction: relationalStore.Transaction,
    path: string, captureId: string, kind: string): Promise<void> {
    if (path.length === 0) {
      return;
    }
    await transaction.execute(
      `INSERT INTO capture_file_cleanups(path,capture_id,kind,created_at,retry_count,stalled_at)
       VALUES(?,?,?,?,0,NULL) ON CONFLICT(path) DO UPDATE SET
       capture_id=excluded.capture_id,kind=excluded.kind,created_at=excluded.created_at,
       retry_count=0,stalled_at=NULL`, [path, captureId, kind, Date.now()]);
  }

  async isPublishedUriReferenced(uri: string): Promise<boolean> {
    const rows = await this.store.querySql('SELECT 1 FROM captures WHERE published_uri=? LIMIT 1', [uri]);
    try {
      return rows.goToFirstRow();
    } finally {
      rows.close();
    }
  }

  async pendingMediaCleanups(limit: number = 20): Promise<MediaCleanupTask[]> {
    const rows = await this.store.querySql(
      `SELECT published_uri,capture_id,retry_count FROM capture_media_cleanups
       WHERE stalled_at IS NULL ORDER BY created_at LIMIT ?`, [limit]);
    const result: MediaCleanupTask[] = [];
    try {
      if (rows.goToFirstRow()) {
        do {
          result.push(new MediaCleanupTask(
            rows.getString(rows.getColumnIndex('published_uri')),
            rows.getString(rows.getColumnIndex('capture_id')),
            rows.getLong(rows.getColumnIndex('retry_count'))
          ));
        } while (rows.goToNextRow());
      }
      return result;
    } finally {
      rows.close();
    }
  }

  async completeMediaCleanup(uri: string): Promise<void> {
    await this.store.executeSql('DELETE FROM capture_media_cleanups WHERE published_uri=?', [uri]);
  }

  async queueMediaCleanups(captureId: string, uris: string[]): Promise<void> {
    const transaction = await this.store.createTransaction();
    try {
      for (const uri of uris) {
        if (uri.length === 0) {
          continue;
        }
        await transaction.execute(
          `INSERT INTO capture_media_cleanups(published_uri,capture_id,created_at,retry_count,last_attempt_at,stalled_at)
           VALUES(?,?,?,0,NULL,NULL) ON CONFLICT(published_uri) DO UPDATE SET
           capture_id=excluded.capture_id,created_at=excluded.created_at,retry_count=0,
           last_attempt_at=NULL,stalled_at=NULL`, [uri, captureId, Date.now()]);
      }
      await transaction.commit();
    } catch (error) {
      await transaction.rollback();
      throw new Error((error as Error).message);
    }
  }

  async adoptPublishedUriFromJournal(captureId: string, expectedPreviousUri: string,
    newUri: string, supersededUris: string[]): Promise<boolean> {
    const transaction = await this.store.createTransaction();
    try {
      const changedValue = await transaction.execute(
        `UPDATE captures SET published_uri=? WHERE id=? AND status='ready'
         AND COALESCE(published_uri,'')=?`, [newUri, captureId, expectedPreviousUri]);
      const changed = typeof changedValue === 'number' ? changedValue : 0;
      if (changed < 1) {
        await transaction.rollback();
        return false;
      }
      const cleanupUris = supersededUris.slice();
      if (expectedPreviousUri.length > 0 && expectedPreviousUri !== newUri &&
        cleanupUris.indexOf(expectedPreviousUri) < 0) {
        cleanupUris.push(expectedPreviousUri);
      }
      for (const uri of cleanupUris) {
        if (uri.length > 0 && uri !== newUri) {
          await transaction.execute(
            `INSERT INTO capture_media_cleanups(published_uri,capture_id,created_at,retry_count,last_attempt_at,stalled_at)
             VALUES(?,?,?,0,NULL,NULL) ON CONFLICT(published_uri) DO UPDATE SET
             capture_id=excluded.capture_id,created_at=excluded.created_at,retry_count=0,
             last_attempt_at=NULL,stalled_at=NULL`, [uri, captureId, Date.now()]);
        }
      }
      await transaction.commit();
      return true;
    } catch (error) {
      await transaction.rollback();
      throw new Error((error as Error).message);
    }
  }

  async failMediaCleanup(uri: string, maxAttempts: number = 3): Promise<void> {
    await this.store.executeSql(
      `UPDATE capture_media_cleanups SET retry_count=retry_count+1,last_attempt_at=?,
       stalled_at=CASE WHEN retry_count+1>=? THEN ? ELSE NULL END WHERE published_uri=?`,
      [Date.now(), maxAttempts, Date.now(), uri]
    );
  }

  async listTemplates(projectId: string): Promise<CaptureTemplateRecord[]> {
    const rows = await this.store.querySql(
      'SELECT * FROM capture_templates WHERE project_id=? ORDER BY updated_at DESC,name_key', [projectId]);
    const result: CaptureTemplateRecord[] = [];
    try {
      if (rows.goToFirstRow()) {
        do {
          result.push(new CaptureTemplateRecord({
            id: rows.getString(rows.getColumnIndex('id')),
            projectId: rows.getString(rows.getColumnIndex('project_id')),
            name: rows.getString(rows.getColumnIndex('name')),
            nameKey: rows.getString(rows.getColumnIndex('name_key')),
            workLocation: rows.getString(rows.getColumnIndex('work_location')),
            workContent: rows.getString(rows.getColumnIndex('work_content')),
            photographer: rows.getString(rows.getColumnIndex('photographer')),
            createdAt: rows.getLong(rows.getColumnIndex('created_at')),
            updatedAt: rows.getLong(rows.getColumnIndex('updated_at'))
          }));
        } while (rows.goToNextRow());
      }
      return result;
    } finally {
      rows.close();
    }
  }

  async saveTemplate(template: CaptureTemplateRecord): Promise<void> {
    const name = template.name.trim();
    const nameKey = template.nameKey.trim();
    const location = template.workLocation.trim();
    const content = template.workContent.trim();
    const photographer = template.photographer.trim();
    if (!validateTemplateField(name, CAPTURE_TEMPLATE_NAME_MAX_LENGTH) ||
      !validateTemplateField(nameKey, CAPTURE_TEMPLATE_NAME_MAX_LENGTH) ||
      !validateTemplateField(location, CAPTURE_TEMPLATE_LOCATION_MAX_LENGTH) ||
      !validateTemplateField(content, CAPTURE_TEMPLATE_CONTENT_MAX_LENGTH) ||
      !validateTemplateField(photographer, CAPTURE_TEMPLATE_PHOTOGRAPHER_MAX_LENGTH)) {
      throw new Error('capture_template_invalid');
    }
    await this.store.executeSql(
      `INSERT INTO capture_templates(id,project_id,name,name_key,work_location,work_content,photographer,
       created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?)`,
      [template.id, template.projectId, name, nameKey, location,
        content, photographer, template.createdAt, template.updatedAt]
    );
  }

  async renameTemplate(id: string, name: string, _nameKey: string): Promise<void> {
    const normalized = normalizeCaptureTemplateName(name);
    if (!validateTemplateField(normalized, CAPTURE_TEMPLATE_NAME_MAX_LENGTH)) {
      throw new Error('capture_template_invalid');
    }
    const changedValue = await this.store.execute(
      'UPDATE capture_templates SET name=?,name_key=?,updated_at=? WHERE id=?',
      [normalized, captureTemplateNameKey(normalized), Date.now(), id]
    );
    const changed = typeof changedValue === 'number' ? changedValue : 0;
    if (changed < 1) throw new Error('capture_template_missing');
  }

  async deleteTemplate(id: string): Promise<void> {
    await this.store.executeSql('DELETE FROM capture_templates WHERE id=?', [id]);
  }

  async recentSuggestions(projectId: string, field: string, limit: number = 20): Promise<string[]> {
    const allowed = field === 'work_location' || field === 'work_content' || field === 'photographer';
    if (!allowed) {
      return [];
    }
    const boundedLimit = Math.max(1, Math.min(20, Math.floor(limit)));
    const rows = await this.store.querySql(
      `SELECT value FROM (
         SELECT TRIM(${field}) AS value, COALESCE(captured_at,created_at) AS latest,
           ROW_NUMBER() OVER (PARTITION BY LOWER(TRIM(${field}))
             ORDER BY COALESCE(captured_at,created_at) DESC,id DESC) AS suggestion_rank
         FROM captures WHERE project_id=? AND status<>'pendingCamera' AND TRIM(${field})<>''
       ) WHERE suggestion_rank=1 ORDER BY latest DESC LIMIT ?`, [projectId, boundedLimit]);
    const result: string[] = [];
    try {
      if (rows.goToFirstRow()) {
        do {
          result.push(rows.getString(rows.getColumnIndex('value')));
        } while (rows.goToNextRow());
      }
      return result;
    } finally {
      rows.close();
    }
  }

  async settings(): Promise<AppSettingsRecord> {
    const rows = await this.store.querySql('SELECT * FROM app_settings WHERE id=\'global\' LIMIT 1');
    try {
      if (!rows.goToFirstRow()) {
        throw new Error('settings_missing');
      }
      return new AppSettingsRecord({
        themeMode: rows.getString(rows.getColumnIndex('theme_mode')),
        localeCode: nullableString(rows, 'locale_code'),
        defaultWatermarkPosition: rows.getString(rows.getColumnIndex('default_watermark_position')),
        defaultWatermarkOpacity: rows.getDouble(rows.getColumnIndex('default_watermark_opacity')),
        defaultWatermarkAccentColorArgb:
          rows.getLong(rows.getColumnIndex('default_watermark_accent_color_argb')),
        defaultWatermarkFontScale: rows.getDouble(rows.getColumnIndex('default_watermark_font_scale')),
        locationPermissionPromptDismissed:
          rows.getLong(rows.getColumnIndex('location_permission_prompt_dismissed')) === 1,
        completionNotificationsEnabled:
          rows.getLong(rows.getColumnIndex('completion_notifications_enabled')) === 1,
        appSeedColorArgb: rows.getLong(rows.getColumnIndex('app_seed_color_argb'))
      });
    } finally {
      rows.close();
    }
  }

  async updateSettings(value: AppSettingsRecord): Promise<void> {
    await this.store.executeSql(
      `UPDATE app_settings SET theme_mode=?,locale_code=?,default_watermark_position=?,
       default_watermark_opacity=?,default_watermark_accent_color_argb=?,default_watermark_font_scale=?,
       location_permission_prompt_dismissed=?,completion_notifications_enabled=?,app_seed_color_argb=?,updated_at=?
       WHERE id='global'`,
      [value.themeMode, value.localeCode.length === 0 ? null : value.localeCode,
        value.defaultWatermarkPosition, value.defaultWatermarkOpacity,
        value.defaultWatermarkAccentColorArgb, value.defaultWatermarkFontScale,
        value.locationPermissionPromptDismissed ? 1 : 0,
        value.completionNotificationsEnabled ? 1 : 0, value.appSeedColorArgb, Date.now()]
    );
  }

  async recordDiagnostic(category: string, outcome: string, durationMs: number): Promise<void> {
    const retentionCutoff = Date.now() - (7 * 24 * 60 * 60 * 1000);
    await this.store.executeSql(
      'INSERT INTO diagnostic_events(id,category,outcome,duration_ms,created_at) VALUES(?,?,?,?,?)',
      [util.generateRandomUUID(), category, outcome, durationMs, Date.now()]
    );
    await this.store.executeSql(
      `DELETE FROM diagnostic_events WHERE id NOT IN
       (SELECT id FROM diagnostic_events WHERE created_at>=? ORDER BY created_at DESC LIMIT 200)`,
      [retentionCutoff]
    );
  }

  async diagnosticSummary(): Promise<DiagnosticSummary> {
    const rows = await this.store.querySql(
      'SELECT COUNT(*) AS event_count,COALESCE(MAX(created_at),0) AS latest FROM diagnostic_events');
    try {
      rows.goToFirstRow();
      return new DiagnosticSummary(rows.getLong(rows.getColumnIndex('event_count')),
        rows.getLong(rows.getColumnIndex('latest')));
    } finally {
      rows.close();
    }
  }

  async diagnosticEvents(): Promise<DiagnosticEventRecord[]> {
    const rows = await this.store.querySql(
      'SELECT category,outcome,duration_ms,created_at FROM diagnostic_events ORDER BY created_at DESC LIMIT 200');
    const result: DiagnosticEventRecord[] = [];
    try {
      while (rows.goToNextRow()) {
        result.push(new DiagnosticEventRecord(
          rows.getString(rows.getColumnIndex('category')),
          rows.getString(rows.getColumnIndex('outcome')),
          rows.getLong(rows.getColumnIndex('duration_ms')),
          rows.getLong(rows.getColumnIndex('created_at'))
        ));
      }
      return result;
    } finally {
      rows.close();
    }
  }

  async clearDiagnostics(): Promise<void> {
    await this.store.executeSql('DELETE FROM diagnostic_events');
  }
}

class CaptureStateCounts {
  processing: number;
  failed: number;

  constructor(processing: number, failed: number) {
    this.processing = processing;
    this.failed = failed;
  }
}

class DateRange {
  start: number;
  end: number;

  constructor(start: number, end: number) {
    this.start = start;
    this.end = end;
  }
}

export class MediaCleanupTask {
  publishedUri: string;
  captureId: string;
  retryCount: number;

  constructor(publishedUri: string, captureId: string, retryCount: number) {
    this.publishedUri = publishedUri;
    this.captureId = captureId;
    this.retryCount = retryCount;
  }
}

export class PrivateFileCleanupTask {
  path: string;
  captureId: string;
  kind: string;
  retryCount: number;

  constructor(path: string, captureId: string, kind: string, retryCount: number) {
    this.path = path;
    this.captureId = captureId;
    this.kind = kind;
    this.retryCount = retryCount;
  }
}

export class DiagnosticSummary {
  eventCount: number;
  latestAt: number;

  constructor(eventCount: number, latestAt: number) {
    this.eventCount = eventCount;
    this.latestAt = latestAt;
  }
}

export class DiagnosticEventRecord {
  category: string;
  outcome: string;
  durationMs: number;
  createdAt: number;

  constructor(category: string, outcome: string, durationMs: number, createdAt: number) {
    this.category = category;
    this.outcome = outcome;
    this.durationMs = durationMs;
    this.createdAt = createdAt;
  }
}
