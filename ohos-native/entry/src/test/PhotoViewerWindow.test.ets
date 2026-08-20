import { describe, expect, it } from '@ohos/hypium';
import { CAPTURE_VIEWER_SORT_ASC, CAPTURE_VIEWER_SORT_DESC } from
  '../main/ets/data/database/AppDatabase';
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

export default function photoViewerWindowTest(): void {
  describe('PhotoViewerWindow', () => {
    it('keeps the database order stable when sort times match', 0, () => {
      expect(CAPTURE_VIEWER_SORT_DESC).assertEqual(
        'COALESCE(c.captured_at,c.created_at) DESC, c.id DESC');
      expect(CAPTURE_VIEWER_SORT_ASC).assertEqual(
        'COALESCE(c.captured_at,c.created_at) ASC, c.id ASC');
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
        await controller.moveTo(Math.min(controller.currentIndex + 1, controller.rows.length - 1));
        expect(controller.rows.length <= 5).assertTrue();
      }
      expect(controller.absoluteIndex).assertEqual(24);
    });
  });
}
