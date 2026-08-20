import { CaptureRecord, CaptureViewerWindow } from '../../domain/Models';

const MAX_VIEWER_ROWS: number = 5;

export interface PhotoViewerWindowLoader {
  captureViewerWindow(captureId: string): Promise<CaptureViewerWindow>;
}

export class PhotoViewerWindowController {
  rows: CaptureRecord[] = [];
  currentIndex: number = 0;
  absoluteIndex: number = 0;
  totalCount: number = 0;
  loading: boolean = false;
  failed: boolean = false;
  needsRefill: boolean = false;

  private readonly loader: PhotoViewerWindowLoader;
  private readonly changed: () => void;
  private generation: number = 0;
  private visibleCaptureId: string = '';

  constructor(loader: PhotoViewerWindowLoader, changed: () => void = (): void => {}) {
    this.loader = loader;
    this.changed = changed;
  }

  seed(capture: CaptureRecord): void {
    this.generation += 1;
    this.rows = [capture];
    this.currentIndex = 0;
    this.absoluteIndex = 0;
    this.totalCount = 1;
    this.visibleCaptureId = capture.id;
    this.loading = false;
    this.failed = false;
    this.needsRefill = true;
    this.changed();
  }

  async loadAround(captureId: string): Promise<void> {
    const generation = ++this.generation;
    const requestedCaptureId = captureId;
    this.visibleCaptureId = captureId;
    this.loading = true;
    this.failed = false;
    this.changed();
    try {
      const window = await this.loader.captureViewerWindow(captureId);
      if (generation !== this.generation || requestedCaptureId !== this.visibleCaptureId) {
        return;
      }
      const selectedIndex = window.rows.findIndex((row: CaptureRecord): boolean =>
        row.id === requestedCaptureId);
      if (selectedIndex < 0 || window.rows.length > MAX_VIEWER_ROWS) {
        this.failed = true;
        this.changed();
        return;
      }
      this.rows = window.rows.slice();
      this.currentIndex = selectedIndex;
      this.absoluteIndex = window.absoluteIndex + selectedIndex - window.currentIndex;
      this.totalCount = window.totalCount;
      this.failed = false;
      this.needsRefill = false;
      this.changed();
    } catch (_) {
      if (generation === this.generation && requestedCaptureId === this.visibleCaptureId) {
        this.failed = true;
        this.changed();
      }
    } finally {
      if (generation === this.generation) {
        this.loading = false;
        this.changed();
      }
    }
  }

  moveTo(index: number): Promise<void> {
    if (index < 0 || index >= this.rows.length) {
      return Promise.resolve();
    }
    if (index === this.currentIndex) {
      return Promise.resolve();
    }
    const previousIndex = this.currentIndex;
    const selected = this.rows[index];
    this.visibleCaptureId = selected.id;
    this.currentIndex = index;
    this.absoluteIndex = Math.max(0,
      Math.min(this.totalCount - 1, this.absoluteIndex + index - previousIndex));
    this.failed = false;
    this.changed();
    if (index <= 1 || index >= this.rows.length - 2) {
      return this.loadAround(selected.id);
    }
    return Promise.resolve();
  }

  retry(): Promise<void> {
    if (this.visibleCaptureId.length === 0) {
      return Promise.resolve();
    }
    return this.loadAround(this.visibleCaptureId);
  }

  refill(): Promise<void> {
    if (!this.needsRefill || this.visibleCaptureId.length === 0 || this.loading) {
      return Promise.resolve();
    }
    return this.loadAround(this.visibleCaptureId);
  }

  invalidate(): void {
    this.generation += 1;
    this.loading = false;
    this.changed();
  }

  currentCaptureId(): string {
    return this.visibleCaptureId;
  }

  shrinkToCurrent(): void {
    if (this.currentIndex < 0 || this.currentIndex >= this.rows.length) {
      return;
    }
    const current = this.rows[this.currentIndex];
    this.generation += 1;
    this.rows = [current];
    this.currentIndex = 0;
    this.visibleCaptureId = current.id;
    this.loading = false;
    this.failed = false;
    this.needsRefill = true;
    this.changed();
  }
}
