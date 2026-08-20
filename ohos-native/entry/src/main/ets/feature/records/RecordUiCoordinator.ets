import { CaptureFilter, CaptureRecord } from '../../domain/Models';

export interface RecordTimerScheduler {
  schedule(action: () => void, delayMs: number): number;
  cancel(id: number): void;
}

export class RecordRefreshGate {
  private suppressionDepth: number = 0;

  shouldRefresh(): boolean {
    return this.suppressionDepth === 0;
  }

  runSuppressed(action: () => void): void {
    this.suppressionDepth += 1;
    try {
      action();
    } finally {
      this.suppressionDepth = Math.max(0, this.suppressionDepth - 1);
    }
  }

  async runSuppressedAsync(action: () => Promise<void>): Promise<void> {
    this.suppressionDepth += 1;
    try {
      await action();
    } finally {
      this.suppressionDepth = Math.max(0, this.suppressionDepth - 1);
    }
  }
}

export class RecordNavigationSeed {
  readonly capture: CaptureRecord;
  readonly uri: string;

  constructor(capture: CaptureRecord, uri: string) {
    this.capture = capture;
    this.uri = uri;
  }
}

export class RecordNavigationSeedStore {
  private static seed: RecordNavigationSeed | null = null;

  static put(capture: CaptureRecord, uri: string): void {
    RecordNavigationSeedStore.seed = new RecordNavigationSeed(capture, uri);
  }

  static take(captureId: string): RecordNavigationSeed | null {
    const seed = RecordNavigationSeedStore.seed;
    RecordNavigationSeedStore.seed = null;
    if (seed === null || seed.capture.id !== captureId) {
      return null;
    }
    return seed;
  }

  static clear(): void {
    RecordNavigationSeedStore.seed = null;
  }
}

export class SystemRecordTimerScheduler implements RecordTimerScheduler {
  schedule(action: () => void, delayMs: number): number {
    return setTimeout(action, delayMs);
  }

  cancel(id: number): void {
    clearTimeout(id);
  }
}

export class RecordSearchCoordinator {
  private readonly scheduler: RecordTimerScheduler;
  private active: boolean = false;
  private timerId: number = -1;
  private generation: number = 0;

  constructor(scheduler: RecordTimerScheduler) {
    this.scheduler = scheduler;
  }

  activate(): boolean {
    if (this.active) {
      return false;
    }
    this.active = true;
    return true;
  }

  deactivate(): boolean {
    if (!this.active) {
      return false;
    }
    this.active = false;
    this.generation += 1;
    this.cancelTimer();
    return true;
  }

  isActive(): boolean {
    return this.active;
  }

  schedule(action: () => void): void {
    if (!this.active) {
      return;
    }
    this.cancelTimer();
    const generation = ++this.generation;
    this.timerId = this.scheduler.schedule((): void => {
      if (!this.active || generation !== this.generation) {
        return;
      }
      this.timerId = -1;
      action();
    }, 250);
  }

  private cancelTimer(): void {
    if (this.timerId < 0) {
      return;
    }
    this.scheduler.cancel(this.timerId);
    this.timerId = -1;
  }
}

export class RecordSelectionRequestToken {
  readonly generation: number;
  readonly projectId: string;
  readonly year: number;
  readonly month: number;
  readonly day: number;
  readonly searchText: string;

  constructor(generation: number, filter: CaptureFilter) {
    this.generation = generation;
    this.projectId = filter.projectId;
    this.year = filter.year;
    this.month = filter.month;
    this.day = filter.day;
    this.searchText = filter.searchText;
  }

  matches(filter: CaptureFilter): boolean {
    return this.projectId === filter.projectId && this.year === filter.year &&
      this.month === filter.month && this.day === filter.day && this.searchText === filter.searchText;
  }
}

export class RecordSelectionCoordinator {
  selectionMode: boolean = false;
  selectedIds: string[] = [];
  allSelected: boolean = false;
  confirmDelete: boolean = false;
  private requestGeneration: number = 0;

  enter(): void {
    this.invalidatePending();
    this.selectionMode = true;
  }

  exit(): void {
    this.invalidatePending();
    this.selectionMode = false;
    this.selectedIds = [];
    this.allSelected = false;
    this.confirmDelete = false;
  }

  toggle(captureId: string): void {
    this.invalidatePending();
    const index = this.selectedIds.indexOf(captureId);
    if (index >= 0) {
      const next = this.selectedIds.slice();
      next.splice(index, 1);
      this.selectedIds = next;
    } else {
      this.selectedIds = this.selectedIds.concat([captureId]);
    }
    this.allSelected = false;
    this.confirmDelete = false;
  }

  selectAll(captureIds: string[]): void {
    this.invalidatePending();
    this.selectedIds = captureIds.slice();
    this.allSelected = this.selectedIds.length > 0;
    this.confirmDelete = false;
  }

  deselectAll(): void {
    this.invalidatePending();
    this.selectedIds = [];
    this.allSelected = false;
    this.confirmDelete = false;
  }

  requestPermanentDelete(): boolean {
    if (this.selectedIds.length === 0) {
      this.confirmDelete = false;
      return false;
    }
    if (this.confirmDelete) {
      return true;
    }
    this.confirmDelete = true;
    return false;
  }

  beginSelectAll(filter: CaptureFilter): RecordSelectionRequestToken {
    this.requestGeneration += 1;
    return new RecordSelectionRequestToken(this.requestGeneration, filter);
  }

  isSelectAllCurrent(token: RecordSelectionRequestToken, filter: CaptureFilter): boolean {
    return this.selectionMode && token.generation === this.requestGeneration && token.matches(filter);
  }

  commitSelectAll(token: RecordSelectionRequestToken, filter: CaptureFilter, captureIds: string[]): boolean {
    if (!this.isSelectAllCurrent(token, filter)) {
      return false;
    }
    this.selectedIds = captureIds.slice();
    this.allSelected = this.selectedIds.length > 0;
    this.confirmDelete = false;
    this.invalidatePending();
    return true;
  }

  invalidatePending(): void {
    this.requestGeneration += 1;
  }
}

export class RecordBatchLayoutPolicy {
  static barHeight(): number {
    return 92;
  }

  static bottomMargin(): number {
    return 12;
  }

  static contentGap(): number {
    return 16;
  }

  static listBottomPadding(selectionMode: boolean): number {
    return selectionMode ? RecordBatchLayoutPolicy.barHeight() + RecordBatchLayoutPolicy.bottomMargin() +
      RecordBatchLayoutPolicy.contentGap() : 92;
  }
}

export class RecordRestorePolicy {
  static needsMoreRows(savedFirstVisibleIndex: number, loadedCount: number,
    hasMore: boolean, failed: boolean): boolean {
    return savedFirstVisibleIndex >= loadedCount && hasMore && !failed;
  }
}

export class DetailMediaSwapCoordinator {
  displayedUri: string = '';
  pendingUri: string = '';
  failed: boolean = false;
  private generation: number = 0;
  private displayedVersion: number = 0;
  private awaitingDisplayedReady: boolean = false;

  initialize(uri: string): void {
    this.generation += 1;
    this.displayedUri = uri;
    this.displayedVersion = this.generation;
    this.pendingUri = '';
    this.failed = false;
    this.awaitingDisplayedReady = false;
  }

  begin(uri: string, forceReload: boolean = false): number {
    if (uri === this.displayedUri && !forceReload) {
      this.generation += 1;
      this.pendingUri = '';
      this.failed = false;
      this.awaitingDisplayedReady = false;
      return this.generation;
    }
    this.generation += 1;
    if (this.displayedUri.length === 0) {
      this.displayedUri = uri;
      this.pendingUri = '';
      this.awaitingDisplayedReady = false;
      this.failed = false;
      return this.generation;
    }
    this.pendingUri = uri;
    this.failed = false;
    this.awaitingDisplayedReady = false;
    return this.generation;
  }

  currentGeneration(): number {
    return this.generation;
  }

  displayedRequestVersion(): number {
    return this.displayedVersion;
  }

  completePending(generation: number, uri: string): boolean {
    if (!this.acceptsPending(generation, uri)) {
      return false;
    }
    this.displayedUri = uri;
    this.displayedVersion = generation;
    this.failed = false;
    this.awaitingDisplayedReady = true;
    return true;
  }

  failPending(generation: number, uri: string): boolean {
    if (!this.acceptsPending(generation, uri)) {
      return false;
    }
    this.failed = true;
    this.awaitingDisplayedReady = false;
    return true;
  }

  completeDisplayed(uri: string): boolean {
    if (!this.awaitingDisplayedReady || uri !== this.displayedUri || uri !== this.pendingUri) {
      return false;
    }
    this.pendingUri = '';
    this.awaitingDisplayedReady = false;
    return true;
  }

  retry(): number {
    if (this.pendingUri.length === 0) {
      return this.generation;
    }
    this.generation += 1;
    this.failed = false;
    this.awaitingDisplayedReady = false;
    return this.generation;
  }

  invalidate(): void {
    this.generation += 1;
    this.pendingUri = '';
    this.failed = false;
    this.awaitingDisplayedReady = false;
  }

  private acceptsPending(generation: number, uri: string): boolean {
    return generation === this.generation && uri.length > 0 && uri === this.pendingUri;
  }
}

export class RenderedRefreshTracker {
  private expectedAttempt: number = -1;

  expectNextAttempt(currentAttempt: number): void {
    const normalized = Number.isFinite(currentAttempt) ? Math.max(0, Math.floor(currentAttempt)) : 0;
    this.expectedAttempt = normalized + 1;
  }

  consumeIfReady(ready: boolean, processingAttempts: number): boolean {
    if (!ready || this.expectedAttempt < 0 || !Number.isFinite(processingAttempts) ||
      processingAttempts < this.expectedAttempt) {
      return false;
    }
    this.expectedAttempt = -1;
    return true;
  }
}

export class PhotoViewerGestureState {
  scale: number = 1;
  private baseScale: number = 1;

  beginPinch(): void {
    this.baseScale = this.scale;
  }

  updatePinch(eventScale: number): void {
    const next = this.baseScale * eventScale;
    this.scale = Math.max(1, Math.min(5, Number.isFinite(next) ? next : 1));
  }

  canSwipe(): boolean {
    return this.scale <= 1;
  }

  resetAfterMove(): void {
    this.scale = 1;
    this.baseScale = 1;
  }
}

export class ViewerRenderedVersionTracker {
  private captureId: string = '';
  private version: number = 0;

  versionFor(captureId: string, ready: boolean, processingAttempts: number): number {
    const normalized = Number.isFinite(processingAttempts) ?
      Math.max(0, Math.floor(processingAttempts)) : 0;
    if (captureId !== this.captureId) {
      this.captureId = captureId;
      this.version = ready ? normalized : 0;
      return this.version;
    }
    if (ready && normalized > this.version) {
      this.version = normalized;
    }
    return this.version;
  }
}

export class ViewerNodePolicy {
  static decodeEdge(current: boolean): number {
    return current ? 2048 : 1024;
  }

  static key(captureId: string, current: boolean): string {
    return `${captureId}-${current ? 'full' : 'preview'}`;
  }

  static transitionDuration(reduceMotion: boolean): number {
    return reduceMotion ? 0 : 180;
  }
}
