import { CaptureFilter, CapturePage, CapturePageCursor, CaptureRecord } from '../../domain/Models';
import { LazyListDataSource } from '../../shared/LazyListDataSource';

export const CAPTURE_PAGE_SIZE: number = 50;

export interface CapturePageLoader {
  load(filter: CaptureFilter, cursor: CapturePageCursor | null, pageSize: number): Promise<CapturePage>;
}

export class CapturePageRetryPolicy {
  static canLoadNext(failed: boolean, explicitRetry: boolean): boolean {
    return !failed || explicitRetry;
  }
}

export class CapturePagedController {
  readonly data: LazyListDataSource<CaptureRecord> =
    new LazyListDataSource<CaptureRecord>((row: CaptureRecord): string => row.id);
  loadingInitial: boolean = false;
  loadingMore: boolean = false;
  hasMore: boolean = true;
  failed: boolean = false;
  private generation: number = 0;
  private cursor: CapturePageCursor | null = null;
  private filter: CaptureFilter = { projectId: '', year: 0, month: 0, day: 0, searchText: '' };
  private failedInitial: boolean = false;
  private readonly loader: CapturePageLoader;
  private readonly changed: () => void;

  constructor(loader: CapturePageLoader, changed: () => void) {
    this.loader = loader;
    this.changed = changed;
  }

  async reset(filter: CaptureFilter): Promise<void> {
    const generation = ++this.generation;
    this.filter = this.copyFilter(filter);
    this.cursor = null;
    this.hasMore = true;
    this.failed = false;
    this.failedInitial = false;
    this.loadingInitial = true;
    this.loadingMore = false;
    this.changed();
    await this.fetch(generation, true);
  }

  async loadNext(): Promise<void> {
    await this.loadNextInternal(false);
  }

  private async loadNextInternal(explicitRetry: boolean): Promise<void> {
    if (this.loadingInitial || this.loadingMore || !this.hasMore ||
      !CapturePageRetryPolicy.canLoadNext(this.failed, explicitRetry)) {
      return;
    }
    this.loadingMore = true;
    this.failed = false;
    const generation = this.generation;
    this.changed();
    await this.fetch(generation, false);
  }

  async retry(): Promise<void> {
    if (!this.failed) {
      return;
    }
    if (this.failedInitial) {
      await this.reset(this.filter);
      return;
    }
    await this.loadNextInternal(true);
  }

  invalidate(): void {
    this.generation += 1;
    this.loadingInitial = false;
    this.loadingMore = false;
    this.changed();
  }

  private async fetch(generation: number, initial: boolean): Promise<void> {
    const requestCursor = initial ? null : this.cursor;
    const requestFilter = this.copyFilter(this.filter);
    try {
      const page = await this.loader.load(requestFilter, requestCursor, CAPTURE_PAGE_SIZE);
      if (generation !== this.generation) {
        return;
      }
      if (initial) {
        this.data.replace(page.rows);
      } else {
        this.data.appendUnique(page.rows);
      }
      this.cursor = page.nextCursor;
      this.hasMore = page.nextCursor !== null;
      this.failed = false;
      this.failedInitial = false;
      this.changed();
    } catch (_) {
      if (generation === this.generation) {
        this.failed = true;
        this.failedInitial = initial;
        this.changed();
      }
    } finally {
      if (generation === this.generation) {
        if (initial) {
          this.loadingInitial = false;
        } else {
          this.loadingMore = false;
        }
        this.changed();
      }
    }
  }

  private copyFilter(filter: CaptureFilter): CaptureFilter {
    return {
      projectId: filter.projectId,
      year: filter.year,
      month: filter.month,
      day: filter.day,
      searchText: filter.searchText
    };
  }
}
