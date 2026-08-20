import { describe, expect, it } from '@ohos/hypium';
import { relationalStore } from '@kit.ArkData';
import { CaptureViewerQueryExecutor, CaptureViewerQueryResultSet, CaptureViewerWindowQuery,
  CAPTURE_VIEWER_SORT_ASC, CAPTURE_VIEWER_SORT_DESC } from
  '../main/ets/data/database/CaptureViewerWindowQuery';
import { CaptureRecord, CaptureViewerWindow } from '../main/ets/domain/Models';
import { CaptureStatus } from '../main/ets/domain/StateMachine';
import { PhotoViewerWindowController, PhotoViewerWindowLoader } from
  '../main/ets/feature/records/PhotoViewerWindow';

function capture(id: string, capturedAt: number = 100): CaptureRecord {
  return new CaptureRecord({
    id: id,
    projectId: 'project',
    projectName: 'Project',
    photoNumber: id,
    workLocation: 'Location',
    workContent: 'Content',
    photographer: 'Photographer',
    notes: '',
    originalPath: `/original/${id}.jpg`,
    renderedPath: `/rendered/${id}.jpg`,
    publishedUri: '',
    originalSha256: '',
    status: CaptureStatus.READY,
    failureReason: '',
    createdAt: capturedAt,
    capturedAt: capturedAt,
    latitude: null,
    longitude: null,
    accuracyMeters: null,
    address: '',
    locationOutcome: '',
    processingAttempts: 0,
    watermarkLocaleCode: 'zh',
    locationResolution: 'resolved',
    originalDeletedAt: null
  });
}

class BoundedLoader implements PhotoViewerWindowLoader {
  private readonly captures: CaptureRecord[];

  constructor(captures: CaptureRecord[]) {
    this.captures = captures;
  }

  captureViewerWindow(captureId: string): Promise<CaptureViewerWindow> {
    const absoluteIndex = this.captures.findIndex((row: CaptureRecord): boolean => row.id === captureId);
    if (absoluteIndex < 0) {
      return Promise.reject(new Error('capture_missing'));
    }
    const start = Math.max(0, absoluteIndex - 2);
    const end = Math.min(this.captures.length, absoluteIndex + 3);
    return Promise.resolve(new CaptureViewerWindow(
      this.captures.slice(start, end), absoluteIndex - start, absoluteIndex, this.captures.length));
  }
}

class DeferredWindow {
  readonly promise: Promise<CaptureViewerWindow>;
  resolve: (value: CaptureViewerWindow) => void = (_value: CaptureViewerWindow): void => {};
  reject: (reason: Error) => void = (_reason: Error): void => {};

  constructor() {
    this.promise = new Promise<CaptureViewerWindow>((resolve: (value: CaptureViewerWindow) => void,
      reject: (reason: Error) => void): void => {
      this.resolve = resolve;
      this.reject = reject;
    });
  }
}

class ControlledLoader implements PhotoViewerWindowLoader {
  readonly requests: string[] = [];
  readonly pending: DeferredWindow[] = [];

  captureViewerWindow(captureId: string): Promise<CaptureViewerWindow> {
    this.requests.push(captureId);
    const deferred = new DeferredWindow();
    this.pending.push(deferred);
    return deferred.promise;
  }
}

class RetryLoader implements PhotoViewerWindowLoader {
  calls: number = 0;
  private readonly first: CaptureViewerWindow;
  private readonly retry: CaptureViewerWindow;

  constructor(first: CaptureViewerWindow, retry: CaptureViewerWindow) {
    this.first = first;
    this.retry = retry;
  }

  captureViewerWindow(_captureId: string): Promise<CaptureViewerWindow> {
    this.calls += 1;
    if (this.calls === 1) {
      return Promise.resolve(this.first);
    }
    if (this.calls === 2) {
      return Promise.reject(new Error('temporary_failure'));
    }
    return Promise.resolve(this.retry);
  }
}

const FAKE_COLUMNS: string[] = [
  'id', 'project_id', 'project_name', 'photo_number', 'work_location', 'work_content',
  'photographer', 'notes', 'original_path', 'rendered_path', 'published_uri', 'original_sha256',
  'status', 'failure_reason', 'created_at', 'captured_at', 'latitude', 'longitude',
  'accuracy_meters', 'address', 'location_outcome', 'processing_attempts', 'watermark_locale_code',
  'location_resolution', 'original_deleted_at', 'total_count', 'newer_count', 'current_count'
];

class FakeQueryResultSet implements CaptureViewerQueryResultSet {
  private readonly rows: Array<Map<string, relationalStore.ValueType>>;
  private index: number = -1;

  constructor(rows: Array<Map<string, relationalStore.ValueType>>) {
    this.rows = rows;
  }

  goToFirstRow(): boolean {
    if (this.rows.length === 0) {
      return false;
    }
    this.index = 0;
    return true;
  }

  goToNextRow(): boolean {
    if (this.index + 1 >= this.rows.length) {
      return false;
    }
    this.index += 1;
    return true;
  }

  getColumnIndex(column: string): number {
    return FAKE_COLUMNS.indexOf(column);
  }

  isColumnNull(columnIndex: number): boolean {
    return this.value(columnIndex) === null;
  }

  getString(columnIndex: number): string {
    const value = this.value(columnIndex);
    return typeof value === 'string' ? value : '';
  }

  getLong(columnIndex: number): number {
    const value = this.value(columnIndex);
    return typeof value === 'number' ? value : 0;
  }

  getDouble(columnIndex: number): number {
    return this.getLong(columnIndex);
  }

  close(): void {}

  private value(columnIndex: number): relationalStore.ValueType {
    const column = columnIndex < 0 ? '' : FAKE_COLUMNS[columnIndex];
    const value = this.rows[this.index].get(column);
    return value === undefined ? null : value;
  }
}

class RawCaptureRow {
  readonly id: string;
  readonly projectId: string;
  readonly status: string;
  readonly capturedAt: number | null;
  readonly createdAt: number;
  readonly values: Map<string, relationalStore.ValueType>;

  constructor(id: string, sortTime: number, status: string = 'ready', capturedAt: number | null = sortTime) {
    this.id = id;
    this.projectId = 'project';
    this.status = status;
    this.capturedAt = capturedAt;
    this.createdAt = sortTime;
    this.values = new Map<string, relationalStore.ValueType>();
    this.values.set('id', id);
    this.values.set('project_id', this.projectId);
    this.values.set('project_name', 'Mapped Project');
    this.values.set('photo_number', `PHOTO-${id}`);
    this.values.set('work_location', `Location ${id}`);
    this.values.set('work_content', `Content ${id}`);
    this.values.set('photographer', 'Photographer');
    this.values.set('notes', '');
    this.values.set('original_path', `/original/${id}.jpg`);
    this.values.set('rendered_path', `/rendered/${id}.jpg`);
    this.values.set('published_uri', null);
    this.values.set('original_sha256', null);
    this.values.set('status', status);
    this.values.set('failure_reason', null);
    this.values.set('created_at', sortTime);
    this.values.set('captured_at', capturedAt);
    this.values.set('latitude', null);
    this.values.set('longitude', null);
    this.values.set('accuracy_meters', null);
    this.values.set('address', null);
    this.values.set('location_outcome', null);
    this.values.set('processing_attempts', 0);
    this.values.set('watermark_locale_code', 'zh');
    this.values.set('location_resolution', 'resolved');
    this.values.set('original_deleted_at', null);
  }

  sortTime(): number {
    return this.capturedAt === null ? this.createdAt : this.capturedAt;
  }
}

function compareId(left: string, right: string): number {
  if (left < right) return -1;
  if (left > right) return 1;
  return 0;
}

class InMemoryViewerQuery implements CaptureViewerQueryExecutor {
  private readonly snapshot: RawCaptureRow[];
  private readonly liveRows: RawCaptureRow[];
  private readonly replacementAfterFirstQuery: RawCaptureRow[] | null;
  private readonly omitReadyCurrentId: string;
  private current: RawCaptureRow | null = null;
  queryCount: number = 0;

  constructor(rows: RawCaptureRow[], replacementAfterFirstQuery: RawCaptureRow[] | null = null,
    omitReadyCurrentId: string = '') {
    this.snapshot = rows.slice();
    this.liveRows = rows;
    this.replacementAfterFirstQuery = replacementAfterFirstQuery;
    this.omitReadyCurrentId = omitReadyCurrentId;
  }

  querySql(sql: string, args: relationalStore.ValueType[] = []): Promise<CaptureViewerQueryResultSet> {
    this.queryCount += 1;
    if (sql.indexOf('WHERE c.id=? LIMIT 1') >= 0) {
      this.requireSql(sql, 'SELECT c.*, p.name AS project_name');
      const id = args[0] as string;
      const current = this.snapshot.filter((row: RawCaptureRow): boolean => row.id === id);
      this.current = current.length === 1 ? current[0] : null;
      if (this.queryCount === 1 && this.replacementAfterFirstQuery !== null) {
        this.liveRows.splice(0, this.liveRows.length, ...this.replacementAfterFirstQuery);
      }
      return Promise.resolve(new FakeQueryResultSet(current.map(
        (row: RawCaptureRow): Map<string, relationalStore.ValueType> => row.values)));
    }
    if (sql.indexOf('SELECT COUNT(*) AS total_count') >= 0) {
      this.requireSql(sql, "c.status='ready'");
      this.requireSql(sql, 'COALESCE(c.captured_at,c.created_at)>?');
      this.requireSql(sql, 'c.id>?');
      const current = this.requireCurrent();
      this.requireArguments(args,
        [current.sortTime(), current.sortTime(), current.id, current.id, current.projectId]);
      const ready = this.readyRows(current.projectId);
      const counts = new Map<string, relationalStore.ValueType>();
      counts.set('total_count', ready.length);
      counts.set('newer_count', ready.filter((row: RawCaptureRow): boolean =>
        row.sortTime() > current.sortTime() ||
          (row.sortTime() === current.sortTime() && row.id > current.id)).length);
      counts.set('current_count', ready.filter((row: RawCaptureRow): boolean => row.id === current.id).length);
      return Promise.resolve(new FakeQueryResultSet([counts]));
    }
    if (sql.indexOf(`ORDER BY ${CAPTURE_VIEWER_SORT_ASC} LIMIT ?`) >= 0) {
      this.requireSql(sql, "c.status='ready'");
      this.requireSql(sql, 'COALESCE(c.captured_at,c.created_at)>?');
      this.requireSql(sql, 'c.id>?');
      const current = this.requireCurrent();
      const radius = this.finiteRadius(args[4]);
      this.requireArguments(args,
        [current.projectId, current.sortTime(), current.sortTime(), current.id, radius]);
      const rows = this.readyRows(current.projectId).filter((row: RawCaptureRow): boolean =>
        row.sortTime() > current.sortTime() ||
          (row.sortTime() === current.sortTime() && row.id > current.id));
      rows.sort((left: RawCaptureRow, right: RawCaptureRow): number => {
        if (left.sortTime() !== right.sortTime()) return left.sortTime() - right.sortTime();
        return compareId(left.id, right.id);
      });
      return Promise.resolve(new FakeQueryResultSet(rows.slice(0, radius).map(
        (row: RawCaptureRow): Map<string, relationalStore.ValueType> => row.values)));
    }
    if (sql.indexOf(`ORDER BY ${CAPTURE_VIEWER_SORT_DESC} LIMIT ?`) >= 0) {
      this.requireSql(sql, "c.status='ready'");
      this.requireSql(sql, 'COALESCE(c.captured_at,c.created_at)<?');
      this.requireSql(sql, 'c.id<?');
      const current = this.requireCurrent();
      const radius = this.finiteRadius(args[4]);
      this.requireArguments(args,
        [current.projectId, current.sortTime(), current.sortTime(), current.id, radius]);
      const rows = this.readyRows(current.projectId).filter((row: RawCaptureRow): boolean =>
        row.sortTime() < current.sortTime() ||
          (row.sortTime() === current.sortTime() && row.id < current.id));
      rows.sort((left: RawCaptureRow, right: RawCaptureRow): number => {
        if (left.sortTime() !== right.sortTime()) return right.sortTime() - left.sortTime();
        return compareId(right.id, left.id);
      });
      return Promise.resolve(new FakeQueryResultSet(rows.slice(0, radius).map(
        (row: RawCaptureRow): Map<string, relationalStore.ValueType> => row.values)));
    }
    return Promise.reject(new Error(`unexpected_query:${sql}`));
  }

  private readyRows(projectId: string): RawCaptureRow[] {
    return this.snapshot.filter((row: RawCaptureRow): boolean =>
      row.projectId === projectId && row.status === 'ready' && row.id !== this.omitReadyCurrentId);
  }

  private finiteRadius(value: relationalStore.ValueType): number {
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      throw new Error('non_finite_radius');
    }
    if (!Number.isInteger(value) || value < 0) {
      throw new Error('invalid_bounded_radius');
    }
    return value;
  }

  private requireCurrent(): RawCaptureRow {
    if (this.current === null) {
      throw new Error('current_query_required');
    }
    return this.current;
  }

  private requireArguments(actual: relationalStore.ValueType[],
    expected: relationalStore.ValueType[]): void {
    if (actual.length !== expected.length) {
      throw new Error('unexpected_argument_count');
    }
    for (let index = 0; index < expected.length; index += 1) {
      if (actual[index] !== expected[index]) {
        throw new Error(`unexpected_argument:${index}`);
      }
    }
  }

  private requireSql(sql: string, fragment: string): void {
    if (sql.indexOf(fragment) < 0) {
      throw new Error(`missing_sql_fragment:${fragment}`);
    }
  }
}

function rawRows(ids: string[]): RawCaptureRow[] {
  return ids.map((id: string): RawCaptureRow => new RawCaptureRow(id, 100));
}

export default function photoViewerWindowTest(): void {
  describe('PhotoViewerWindow', () => {
    it('keeps the database order stable when sort times match', 0, () => {
      expect(CAPTURE_VIEWER_SORT_DESC).assertEqual(
        'COALESCE(c.captured_at,c.created_at) DESC, c.id DESC');
      expect(CAPTURE_VIEWER_SORT_ASC).assertEqual(
        'COALESCE(c.captured_at,c.created_at) ASC, c.id ASC');
    });

    it('queries and maps a stable middle window from one snapshot', 0, async () => {
      const rows = rawRows(['b', 'g', 'd', 'a', 'f', 'c', 'e']);
      rows.filter((row: RawCaptureRow): boolean => row.id === 'd')[0].values.set('captured_at', null);
      const query = new InMemoryViewerQuery(rows, [new RawCaptureRow('z', 999)]);

      const window = await new CaptureViewerWindowQuery().load(query, 'd', 2);

      expect(window.rows.map((row: CaptureRecord): string => row.id).join(',')).assertEqual('f,e,d,c,b');
      expect(window.currentIndex).assertEqual(2);
      expect(window.absoluteIndex).assertEqual(3);
      expect(window.totalCount).assertEqual(7);
      expect(window.rows[2].capturedAt).assertEqual(100);
      expect(window.rows[2].projectName).assertEqual('Mapped Project');
      expect(query.queryCount).assertEqual(4);
      expect(rows.map((row: RawCaptureRow): string => row.id).join(',')).assertEqual('z');
    });

    it('queries naturally shorter first and last windows with absolute counts', 0, async () => {
      const query = new InMemoryViewerQuery(rawRows(['b', 'e', 'a', 'd', 'c']));
      const reader = new CaptureViewerWindowQuery();

      const first = await reader.load(query, 'e', 2);
      expect(first.rows.map((row: CaptureRecord): string => row.id).join(',')).assertEqual('e,d,c');
      expect(first.absoluteIndex).assertEqual(0);
      expect(first.totalCount).assertEqual(5);

      const last = await reader.load(query, 'a', 2);
      expect(last.rows.map((row: CaptureRecord): string => row.id).join(',')).assertEqual('c,b,a');
      expect(last.absoluteIndex).assertEqual(4);
      expect(last.totalCount).assertEqual(5);
    });

    it('falls back when the current capture is not ready or leaves the ready set', 0, async () => {
      const failed = new RawCaptureRow('failed', 100, 'failed');
      const failedWindow = await new CaptureViewerWindowQuery().load(
        new InMemoryViewerQuery([failed]), 'failed', 2);
      expect(failedWindow.rows.length).assertEqual(1);
      expect(failedWindow.rows[0].id).assertEqual('failed');
      expect(failedWindow.totalCount).assertEqual(1);

      const ready = new RawCaptureRow('ready', 100);
      const lostWindow = await new CaptureViewerWindowQuery().load(
        new InMemoryViewerQuery([ready, new RawCaptureRow('neighbor', 90)], null, 'ready'), 'ready', 2);
      expect(lostWindow.rows.length).assertEqual(1);
      expect(lostWindow.rows[0].id).assertEqual('ready');
      expect(lostWindow.absoluteIndex).assertEqual(0);
      expect(lostWindow.totalCount).assertEqual(1);
    });

    it('returns an empty window only when the requested capture no longer exists', 0, async () => {
      const window = await new CaptureViewerWindowQuery().load(
        new InMemoryViewerQuery([new RawCaptureRow('other', 100)]), 'missing', 2);
      expect(window.rows.length).assertEqual(0);
      expect(window.totalCount).assertEqual(0);
    });

    it('normalizes zero negative fractional and non-finite radii before querying', 0, async () => {
      const reader = new CaptureViewerWindowQuery();
      const rows = rawRows(['e', 'd', 'c', 'b', 'a']);

      const zero = await reader.load(new InMemoryViewerQuery(rows), 'c', 0);
      const negative = await reader.load(new InMemoryViewerQuery(rows), 'c', -3);
      const fractional = await reader.load(new InMemoryViewerQuery(rows), 'c', 2.9);
      const notANumber = await reader.load(new InMemoryViewerQuery(rows), 'c', Number.NaN);
      const infinite = await reader.load(new InMemoryViewerQuery(rows), 'c', Number.POSITIVE_INFINITY);
      const negativeInfinite = await reader.load(new InMemoryViewerQuery(rows), 'c', Number.NEGATIVE_INFINITY);

      expect(zero.rows.map((row: CaptureRecord): string => row.id).join(',')).assertEqual('c');
      expect(negative.rows.map((row: CaptureRecord): string => row.id).join(',')).assertEqual('c');
      expect(fractional.rows.map((row: CaptureRecord): string => row.id).join(',')).assertEqual('e,d,c,b,a');
      expect(notANumber.rows.map((row: CaptureRecord): string => row.id).join(',')).assertEqual('c');
      expect(infinite.rows.map((row: CaptureRecord): string => row.id).join(',')).assertEqual('c');
      expect(negativeInfinite.rows.map((row: CaptureRecord): string => row.id).join(',')).assertEqual('c');
      expect(infinite.absoluteIndex).assertEqual(2);
      expect(infinite.totalCount).assertEqual(5);
    });

    it('loads two newer rows, the current row, and two older rows', 0, async () => {
      const rows = ['g', 'f', 'e', 'd', 'c', 'b', 'a'].map((id: string): CaptureRecord => capture(id));
      const controller = new PhotoViewerWindowController(new BoundedLoader(rows));

      await controller.loadAround('d');

      expect(controller.rows.map((row: CaptureRecord): string => row.id).join(',')).assertEqual('f,e,d,c,b');
      expect(controller.currentIndex).assertEqual(2);
      expect(controller.absoluteIndex).assertEqual(3);
      expect(controller.totalCount).assertEqual(7);
    });

    it('seeds the current capture synchronously before the bounded query completes', 0, () => {
      const loader = new ControlledLoader();
      const controller = new PhotoViewerWindowController(loader);

      controller.seed(capture('seed'));

      expect(controller.rows.length).assertEqual(1);
      expect(controller.rows[0].id).assertEqual('seed');
      expect(controller.currentCaptureId()).assertEqual('seed');
      expect(controller.currentIndex).assertEqual(0);
      expect(controller.needsRefill).assertTrue();
      expect(loader.requests.length).assertEqual(0);
    });

    it('allows naturally shorter windows at the first and last rows', 0, async () => {
      const rows = ['e', 'd', 'c', 'b', 'a'].map((id: string): CaptureRecord => capture(id));
      const controller = new PhotoViewerWindowController(new BoundedLoader(rows));

      await controller.loadAround('e');
      expect(controller.rows.map((row: CaptureRecord): string => row.id).join(',')).assertEqual('e,d,c');
      expect(controller.currentIndex).assertEqual(0);
      expect(controller.absoluteIndex).assertEqual(0);

      await controller.loadAround('a');
      expect(controller.rows.map((row: CaptureRecord): string => row.id).join(',')).assertEqual('c,b,a');
      expect(controller.currentIndex).assertEqual(2);
      expect(controller.absoluteIndex).assertEqual(4);
    });

    it('drops an older request that finishes after the current request', 0, async () => {
      const loader = new ControlledLoader();
      const controller = new PhotoViewerWindowController(loader);
      const oldLoad = controller.loadAround('old');
      const newLoad = controller.loadAround('new');

      loader.pending[1].resolve(new CaptureViewerWindow([capture('new')], 0, 8, 10));
      await newLoad;
      loader.pending[0].resolve(new CaptureViewerWindow([capture('old')], 0, 2, 10));
      await oldLoad;

      expect(controller.rows[0].id).assertEqual('new');
      expect(controller.absoluteIndex).assertEqual(8);
    });

    it('drops a replenishment result when the visible capture changes without a newer query', 0, async () => {
      const loader = new ControlledLoader();
      const controller = new PhotoViewerWindowController(loader);
      const initial = controller.loadAround('c');
      loader.pending[0].resolve(new CaptureViewerWindow(
        [capture('e'), capture('d'), capture('c'), capture('b'), capture('a')], 2, 2, 5));
      await initial;

      const pending = controller.moveTo(3);
      expect(loader.requests[1]).assertEqual('b');
      await controller.moveTo(2);
      expect(controller.currentCaptureId()).assertEqual('c');
      loader.pending[1].resolve(new CaptureViewerWindow(
        [capture('d'), capture('c'), capture('b'), capture('a')], 2, 3, 5));
      await pending;

      expect(controller.currentCaptureId()).assertEqual('c');
      expect(controller.rows.map((row: CaptureRecord): string => row.id).join(','))
        .assertEqual('e,d,c,b,a');
      expect(controller.currentIndex).assertEqual(2);
    });

    it('does not attach a stale replenishment error to a newer visible capture', 0, async () => {
      const loader = new ControlledLoader();
      const controller = new PhotoViewerWindowController(loader);
      const initial = controller.loadAround('c');
      loader.pending[0].resolve(new CaptureViewerWindow(
        [capture('e'), capture('d'), capture('c'), capture('b'), capture('a')], 2, 2, 5));
      await initial;

      const pending = controller.moveTo(3);
      await controller.moveTo(2);
      loader.pending[1].reject(new Error('stale_failure'));
      await pending;

      expect(controller.currentCaptureId()).assertEqual('c');
      expect(controller.failed).assertFalse();
      expect(controller.rows.map((row: CaptureRecord): string => row.id).join(','))
        .assertEqual('e,d,c,b,a');
    });

    it('keeps a successful window after failure and retries around the visible row', 0, async () => {
      const first = new CaptureViewerWindow([capture('c'), capture('b'), capture('a')], 1, 4, 6);
      const retry = new CaptureViewerWindow([capture('e'), capture('d'), capture('c')], 2, 2, 6);
      const loader = new RetryLoader(first, retry);
      const controller = new PhotoViewerWindowController(loader);
      await controller.loadAround('b');

      await controller.moveTo(0);
      expect(controller.failed).assertTrue();
      expect(controller.rows.map((row: CaptureRecord): string => row.id).join(',')).assertEqual('c,b,a');
      expect(controller.currentIndex).assertEqual(0);

      await controller.retry();
      expect(controller.failed).assertFalse();
      expect(controller.rows.map((row: CaptureRecord): string => row.id).join(',')).assertEqual('e,d,c');
      expect(controller.currentIndex).assertEqual(2);
      expect(controller.absoluteIndex).assertEqual(2);
      expect(loader.calls).assertEqual(3);
    });

    it('keeps at most five rows through twenty consecutive moves', 0, async () => {
      const rows: CaptureRecord[] = [];
      for (let index = 29; index >= 0; index -= 1) {
        rows.push(capture(index.toString(), index));
      }
      const controller = new PhotoViewerWindowController(new BoundedLoader(rows));
      await controller.loadAround('25');

      for (let move = 0; move < 20; move += 1) {
        const nextIndex = Math.min(controller.currentIndex + 1, controller.rows.length - 1);
        const expectedId = controller.rows[nextIndex].id;
        const previousAbsoluteIndex = controller.absoluteIndex;
        await controller.moveTo(nextIndex);
        expect(controller.rows.length <= 5).assertTrue();
        expect(controller.currentCaptureId()).assertEqual(expectedId);
        expect(controller.absoluteIndex).assertEqual(previousAbsoluteIndex + 1);
      }
      expect(controller.absoluteIndex).assertEqual(24);
    });

    it('shrinks memory to the current row and invalidates an in-flight replenishment', 0, async () => {
      const loader = new ControlledLoader();
      const controller = new PhotoViewerWindowController(loader);
      const initial = controller.loadAround('c');
      loader.pending[0].resolve(new CaptureViewerWindow(
        [capture('e'), capture('d'), capture('c'), capture('b'), capture('a')], 2, 12, 30));
      await initial;

      const pending = controller.moveTo(3);
      controller.shrinkToCurrent();
      expect(controller.rows.length).assertEqual(1);
      expect(controller.rows[0].id).assertEqual('b');
      expect(controller.currentIndex).assertEqual(0);
      expect(controller.absoluteIndex).assertEqual(13);
      expect(controller.needsRefill).assertTrue();
      loader.pending[1].resolve(new CaptureViewerWindow(
        [capture('d'), capture('c'), capture('b'), capture('a')], 2, 13, 30));
      await pending;

      expect(controller.rows.length).assertEqual(1);
      expect(controller.currentCaptureId()).assertEqual('b');

      const refill = controller.refill();
      expect(loader.requests[2]).assertEqual('b');
      loader.pending[2].resolve(new CaptureViewerWindow(
        [capture('d'), capture('c'), capture('b'), capture('a')], 2, 13, 30));
      await refill;
      expect(controller.rows.length).assertEqual(4);
      expect(controller.currentCaptureId()).assertEqual('b');
      expect(controller.needsRefill).assertFalse();
    });
  });
}
