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

  private readonly loader: PhotoViewerWindowLoader;
  private generation: number = 0;
  private currentCaptureId: string = '';

  constructor(loader: PhotoViewerWindowLoader) {
    this.loader = loader;
  }

  async loadAround(captureId: string): Promise<void> {
    const generation = ++this.generation;
    this.currentCaptureId = captureId;
    this.loading = true;
    this.failed = false;
    try {
      const window = await this.loader.captureViewerWindow(captureId);
      if (generation !== this.generation) {
        return;
      }
      const selectedIndex = window.rows.findIndex((row: CaptureRecord): boolean =>
        row.id === this.currentCaptureId);
      if (selectedIndex < 0 || window.rows.length > MAX_VIEWER_ROWS) {
        this.failed = true;
        return;
      }
      this.rows = window.rows.slice();
      this.currentIndex = selectedIndex;
      this.absoluteIndex = window.absoluteIndex + selectedIndex - window.currentIndex;
      this.totalCount = window.totalCount;
    } catch (_) {
      if (generation === this.generation) {
        this.failed = true;
      }
    } finally {
      if (generation === this.generation) {
        this.loading = false;
      }
    }
  }

  moveTo(index: number): Promise<void> {
    if (index < 0 || index >= this.rows.length) {
      return Promise.resolve();
    }
    const previousIndex = this.currentIndex;
    const selected = this.rows[index];
    this.currentCaptureId = selected.id;
    this.currentIndex = index;
    this.absoluteIndex = Math.max(0,
      Math.min(this.totalCount - 1, this.absoluteIndex + index - previousIndex));
    if (index <= 1 || index >= this.rows.length - 2) {
      return this.loadAround(selected.id);
    }
    return Promise.resolve();
  }

  retry(): Promise<void> {
    if (this.currentCaptureId.length === 0) {
      return Promise.resolve();
    }
    return this.loadAround(this.currentCaptureId);
  }

  invalidate(): void {
    this.generation += 1;
    this.loading = false;
  }
}
