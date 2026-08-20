import { describe, expect, it } from '@ohos/hypium';
import { CapturePage, CapturePageCursor, CaptureFilter, CaptureRecord } from '../main/ets/domain/Models';
import { CaptureStatus } from '../main/ets/domain/StateMachine';
import { CAPTURE_PAGE_SIZE, CapturePageLoader,
  CapturePagedController } from '../main/ets/feature/records/CapturePagedController';

class DeferredPage {
  readonly promise: Promise<CapturePage>;
  private resolvePage: (page: CapturePage) => void = (): void => {};
  private rejectPage: (error: Error) => void = (): void => {};

  constructor() {
    this.promise = new Promise<CapturePage>((resolve: (page: CapturePage) => void,
      reject: (error: Error) => void): void => {
      this.resolvePage = resolve;
      this.rejectPage = reject;
    });
  }

  resolve(page: CapturePage): void {
    this.resolvePage(page);
  }

  reject(error: Error): void {
    this.rejectPage(error);
  }
}

class PageCall {
  filter: CaptureFilter;
  cursor: CapturePageCursor | null;
  pageSize: number;

  constructor(filter: CaptureFilter, cursor: CapturePageCursor | null, pageSize: number) {
    this.filter = filter;
    this.cursor = cursor;
    this.pageSize = pageSize;
  }
}

class ControlledLoader implements CapturePageLoader {
  calls: PageCall[] = [];
  pending: DeferredPage[] = [];

  load(filter: CaptureFilter, cursor: CapturePageCursor | null, pageSize: number): Promise<CapturePage> {
    this.calls.push(new PageCall({ projectId: filter.projectId, year: filter.year, month: filter.month,
      day: filter.day, searchText: filter.searchText }, cursor, pageSize));
    const deferred = new DeferredPage();
    this.pending.push(deferred);
    return deferred.promise;
  }
}

class StressLoader implements CapturePageLoader {
  calls: PageCall[] = [];
  private readonly rows: CaptureRecord[];

  constructor(rows: CaptureRecord[]) {
    this.rows = rows;
  }

  load(filter: CaptureFilter, cursor: CapturePageCursor | null, pageSize: number): Promise<CapturePage> {
    this.calls.push(new PageCall(filter, cursor, pageSize));
    const start = cursor === null ? 0 : cursor.sortTime;
    const rows = this.rows.slice(start, start + pageSize);
    const nextStart = start + rows.length;
    const next = nextStart < this.rows.length ? new CapturePageCursor(nextStart, `cursor-${nextStart}`) : null;
    return Promise.resolve(new CapturePage(rows, next));
  }
}

function filter(projectId: string, searchText: string = ''): CaptureFilter {
  return { projectId, year: 0, month: 0, day: 0, searchText };
}

function capture(id: string, capturedAt: number): CaptureRecord {
  return new CaptureRecord({
    id,
    projectId: 'project-1',
    projectName: 'Project 1',
    photoNumber: `P-${id}`,
    workLocation: 'Location',
    workContent: 'Content',
    photographer: 'Photographer',
    notes: 'Notes',
    originalPath: '/data/original.jpg',
    renderedPath: '/data/rendered.jpg',
    publishedUri: '',
    originalSha256: 'sha256',
    status: CaptureStatus.READY,
    failureReason: '',
    createdAt: capturedAt,
    capturedAt,
    latitude: null,
    longitude: null,
    accuracyMeters: null,
    address: '',
    locationOutcome: 'resolved',
    processingAttempts: 0,
    watermarkLocaleCode: 'zh-CN',
    locationResolution: 'resolved',
    originalDeletedAt: null
  });
}

export default function capturePagedControllerTest(): void {
  describe('CapturePagedController', () => {
    it('discards a stale reset result and copies the requested filter', 0, async () => {
      const loader = new ControlledLoader();
      let changes = 0;
      const controller = new CapturePagedController(loader, (): void => { changes += 1; });
      const firstFilter = filter('project-a', 'first');
      const first = controller.reset(firstFilter);
      firstFilter.searchText = 'mutated-after-reset';
      const second = controller.reset(filter('project-b', 'second'));

      expect(loader.calls.length).assertEqual(2);
      expect(loader.calls[0].filter.searchText).assertEqual('first');
      loader.pending[1].resolve(new CapturePage([capture('new', 2)], null));
      await second;
      loader.pending[0].resolve(new CapturePage([capture('old', 1)], null));
      await first;

      expect(controller.data.snapshot()[0].id).assertEqual('new');
      expect(controller.hasMore).assertFalse();
      expect(controller.loadingInitial).assertFalse();
      expect(changes > 0).assertTrue();
    });

    it('allows only one in-flight next-page request', 0, async () => {
      const loader = new ControlledLoader();
      const controller = new CapturePagedController(loader, (): void => {});
      const initial = controller.reset(filter('project-1'));
      loader.pending[0].resolve(new CapturePage([capture('first', 1)], new CapturePageCursor(1, 'first')));
      await initial;

      const firstNext = controller.loadNext();
      const duplicateNext = controller.loadNext();
      expect(loader.calls.length).assertEqual(2);
      expect(controller.loadingMore).assertTrue();
      loader.pending[1].resolve(new CapturePage([capture('second', 2)], null));
      await firstNext;
      await duplicateNext;

      expect(controller.data.totalCount()).assertEqual(2);
      expect(controller.loadingMore).assertFalse();
    });

    it('retries a failed initial request as a new initial page', 0, async () => {
      const loader = new ControlledLoader();
      const controller = new CapturePagedController(loader, (): void => {});
      const initial = controller.reset(filter('project-1'));
      loader.pending[0].reject(new Error('expected initial failure'));
      await initial;
      expect(controller.failed).assertTrue();

      const retry = controller.retry();
      expect(loader.calls.length).assertEqual(2);
      expect(loader.calls[1].cursor).assertNull();
      loader.pending[1].resolve(new CapturePage([capture('recovered', 1)], null));
      await retry;

      expect(controller.failed).assertFalse();
      expect(controller.data.snapshot()[0].id).assertEqual('recovered');
    });

    it('keeps prior records after an append failure and retries the same cursor without duplicates', 0, async () => {
      const loader = new ControlledLoader();
      const controller = new CapturePagedController(loader, (): void => {});
      const initial = controller.reset(filter('project-1'));
      const cursor = new CapturePageCursor(1, 'b');
      loader.pending[0].resolve(new CapturePage([capture('a', 2), capture('b', 1)], cursor));
      await initial;

      const failedPage = controller.loadNext();
      expect(loader.calls[1].cursor?.id).assertEqual('b');
      loader.pending[1].reject(new Error('expected append failure'));
      await failedPage;
      expect(controller.failed).assertTrue();
      expect(controller.data.totalCount()).assertEqual(2);

      const retry = controller.retry();
      expect(loader.calls.length).assertEqual(3);
      expect(loader.calls[2].cursor?.id).assertEqual('b');
      loader.pending[2].resolve(new CapturePage([capture('b', 1), capture('c', 0)], null));
      await retry;
      await controller.loadNext();

      expect(controller.failed).assertFalse();
      expect(controller.hasMore).assertFalse();
      expect(controller.data.snapshot().map((row: CaptureRecord): string => row.id).join(','))
        .assertEqual('a,b,c');
      expect(loader.calls.length).assertEqual(3);
    });

    it('invalidates every in-flight result', 0, async () => {
      const loader = new ControlledLoader();
      const controller = new CapturePagedController(loader, (): void => {});
      const pending = controller.reset(filter('project-1'));
      controller.invalidate();
      loader.pending[0].resolve(new CapturePage([capture('stale', 1)], null));
      await pending;

      expect(controller.data.totalCount()).assertEqual(0);
      expect(controller.loadingInitial).assertFalse();
      expect(controller.loadingMore).assertFalse();
    });

    it('loads 2,000 records in 40 fixed-size pages without duplicate ids', 0, async () => {
      const records: CaptureRecord[] = [];
      for (let index = 0; index < 2000; index += 1) {
        records.push(capture(`capture-${index}`, index));
      }
      const loader = new StressLoader(records);
      const controller = new CapturePagedController(loader, (): void => {});
      await controller.reset(filter('project-1'));
      while (controller.hasMore) {
        await controller.loadNext();
      }

      const ids = controller.data.snapshot().map((row: CaptureRecord): string => row.id);
      expect(CAPTURE_PAGE_SIZE).assertEqual(50);
      expect(loader.calls.length).assertEqual(40);
      expect(controller.data.totalCount()).assertEqual(2000);
      expect(new Set<string>(ids).size).assertEqual(2000);
      expect(loader.calls.every((call: PageCall): boolean => call.pageSize === 50)).assertTrue();
    });
  });
}
