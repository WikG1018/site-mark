import { relationalStore } from '@kit.ArkData';
import { CaptureRecord, CaptureViewerWindow } from '../../domain/Models';
import { CaptureStatus } from '../../domain/StateMachine';

export const CAPTURE_VIEWER_SORT_DESC: string =
  'COALESCE(c.captured_at,c.created_at) DESC, c.id DESC';
export const CAPTURE_VIEWER_SORT_ASC: string =
  'COALESCE(c.captured_at,c.created_at) ASC, c.id ASC';

export interface CaptureViewerQueryResultSet {
  goToFirstRow(): boolean;
  goToNextRow(): boolean;
  getColumnIndex(column: string): number;
  isColumnNull(columnIndex: number): boolean;
  getString(columnIndex: number): string;
  getLong(columnIndex: number): number;
  getDouble(columnIndex: number): number;
  close(): void;
}

export interface CaptureViewerQueryExecutor {
  querySql(sql: string, args?: relationalStore.ValueType[]): Promise<CaptureViewerQueryResultSet>;
}

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

function nullableString(rows: CaptureViewerQueryResultSet, column: string): string {
  const index = rows.getColumnIndex(column);
  return rows.isColumnNull(index) ? '' : rows.getString(index);
}

function nullableNumber(rows: CaptureViewerQueryResultSet, column: string): number | null {
  const index = rows.getColumnIndex(column);
  return rows.isColumnNull(index) ? null : rows.getDouble(index);
}

function nullableLong(rows: CaptureViewerQueryResultSet, column: string): number | null {
  const index = rows.getColumnIndex(column);
  return rows.isColumnNull(index) ? null : rows.getLong(index);
}

function captureFromRow(rows: CaptureViewerQueryResultSet): CaptureRecord {
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

function normalizedRadius(radius: number): number {
  if (!Number.isFinite(radius)) {
    return 0;
  }
  return Math.max(0, Math.floor(radius));
}

export class CaptureViewerWindowQuery {
  async load(executor: CaptureViewerQueryExecutor, captureId: string,
    radius: number = 2): Promise<CaptureViewerWindow> {
    const current = await this.captureById(executor, captureId);
    if (current === null) {
      return new CaptureViewerWindow([], 0, 0, 0);
    }
    if (current.status !== CaptureStatus.READY) {
      return new CaptureViewerWindow([current], 0, 0, 1);
    }

    const boundedRadius = normalizedRadius(radius);
    const sortTime = current.capturedAt;
    const counts = await executor.querySql(
      `SELECT COUNT(*) AS total_count,
       COALESCE(SUM(CASE WHEN (COALESCE(c.captured_at,c.created_at)>?
         OR (COALESCE(c.captured_at,c.created_at)=? AND c.id>?)) THEN 1 ELSE 0 END),0) AS newer_count,
       COALESCE(SUM(CASE WHEN c.id=? THEN 1 ELSE 0 END),0) AS current_count
       FROM captures c WHERE c.project_id=? AND c.status='ready'`,
      [sortTime, sortTime, current.id, current.id, current.projectId]);
    let totalCount = 0;
    let absoluteIndex = 0;
    let currentCount = 0;
    try {
      if (counts.goToFirstRow()) {
        totalCount = counts.getLong(counts.getColumnIndex('total_count'));
        absoluteIndex = counts.getLong(counts.getColumnIndex('newer_count'));
        currentCount = counts.getLong(counts.getColumnIndex('current_count'));
      }
    } finally {
      counts.close();
    }
    if (currentCount !== 1) {
      return new CaptureViewerWindow([current], 0, 0, 1);
    }

    const newer = await this.captureRows(executor,
      `SELECT c.*, p.name AS project_name FROM captures c
       JOIN projects p ON p.id=c.project_id
       WHERE c.project_id=? AND c.status='ready'
         AND (COALESCE(c.captured_at,c.created_at)>?
           OR (COALESCE(c.captured_at,c.created_at)=? AND c.id>?))
       ORDER BY ${CAPTURE_VIEWER_SORT_ASC} LIMIT ?`,
      [current.projectId, sortTime, sortTime, current.id, boundedRadius]);
    newer.reverse();
    const older = await this.captureRows(executor,
      `SELECT c.*, p.name AS project_name FROM captures c
       JOIN projects p ON p.id=c.project_id
       WHERE c.project_id=? AND c.status='ready'
         AND (COALESCE(c.captured_at,c.created_at)<?
           OR (COALESCE(c.captured_at,c.created_at)=? AND c.id<?))
       ORDER BY ${CAPTURE_VIEWER_SORT_DESC} LIMIT ?`,
      [current.projectId, sortTime, sortTime, current.id, boundedRadius]);
    const rows: CaptureRecord[] = [];
    rows.push(...newer);
    rows.push(current);
    rows.push(...older);
    return new CaptureViewerWindow(rows, newer.length, absoluteIndex, totalCount);
  }

  private async captureById(executor: CaptureViewerQueryExecutor,
    captureId: string): Promise<CaptureRecord | null> {
    const rows = await executor.querySql(
      `SELECT c.*, p.name AS project_name FROM captures c
       JOIN projects p ON p.id=c.project_id WHERE c.id=? LIMIT 1`, [captureId]);
    try {
      if (!rows.goToFirstRow()) {
        return null;
      }
      return captureFromRow(rows);
    } finally {
      rows.close();
    }
  }

  private async captureRows(executor: CaptureViewerQueryExecutor, sql: string,
    args: relationalStore.ValueType[]): Promise<CaptureRecord[]> {
    const rows = await executor.querySql(sql, args);
    const captures: CaptureRecord[] = [];
    try {
      if (rows.goToFirstRow()) {
        do {
          captures.push(captureFromRow(rows));
        } while (rows.goToNextRow());
      }
      return captures;
    } finally {
      rows.close();
    }
  }
}
