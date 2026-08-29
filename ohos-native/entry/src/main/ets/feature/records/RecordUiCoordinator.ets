import { CaptureFilter, CaptureRecord } from '../../domain/Models';
import { RootShellPolicy } from '../../shared/RootShellPolicy';
import { UiTokens } from '../../shared/UiTokens';

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

  resetForFilterChange(): void {
    this.deselectAll();
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
  private static normalizedFontScale(fontScale: number): number {
    if (!Number.isFinite(fontScale) || fontScale < 1) {
      return 1;
    }
    return Math.min(fontScale, 3);
  }

  static barHeight(fontScale: number = 1): number {
    const scale = RecordBatchLayoutPolicy.normalizedFontScale(fontScale);
    return Math.max(104, Math.ceil(RecordBatchLayoutPolicy.actionHeight(scale) + 15 * scale + 16));
  }

  static bottomMargin(): number {
    return 12;
  }

  static contentGap(): number {
    return 16;
  }

  static actionHeight(fontScale: number = 1): number {
    const scale = RecordBatchLayoutPolicy.normalizedFontScale(fontScale);
    return Math.max(68, Math.ceil(42 * scale + 16));
  }

  static actionLabelMaxLines(): number {
    return 2;
  }

  static filterControlHeight(): number {
    return UiTokens.TOUCH_TARGET;
  }

  static listBottomPadding(selectionMode: boolean, fontScale: number = 1,
    safeAreaBottomVp: number = 0): number {
    const inset = Number.isFinite(safeAreaBottomVp) && safeAreaBottomVp > 0 ? safeAreaBottomVp : 0;
    const base = selectionMode ? RecordBatchLayoutPolicy.barHeight(fontScale) +
      RecordBatchLayoutPolicy.bottomMargin() + RecordBatchLayoutPolicy.contentGap() :
      RootShellPolicy.contentBottomInset();
    return base + inset;
  }

  static listViewportBottomPadding(): number {
    return RootShellPolicy.overlayListViewportBottomPadding();
  }

  static listContentEndOffset(selectionMode: boolean, fontScale: number = 1,
    safeAreaBottomVp: number = 0): number {
    return RecordBatchLayoutPolicy.listBottomPadding(selectionMode, fontScale, safeAreaBottomVp);
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
  private frontSlotId: string = 'a';
  private pendingSlotId: string = '';
  private slotAUri: string = '';
  private slotBUri: string = '';
  private slotAVersion: number = 0;
  private slotBVersion: number = 0;

  initialize(uri: string): void {
    this.generation += 1;
    this.displayedUri = uri;
    this.displayedVersion = this.generation;
    this.pendingUri = '';
    this.failed = false;
    this.frontSlotId = 'a';
    this.pendingSlotId = '';
    this.slotAUri = uri;
    this.slotAVersion = this.generation;
    this.slotBUri = '';
    this.slotBVersion = 0;
  }

  begin(uri: string, forceReload: boolean = false): number {
    if (uri === this.displayedUri && !forceReload) {
      this.generation += 1;
      this.clearPending();
      return this.generation;
    }
    this.generation += 1;
    if (this.displayedUri.length === 0) {
      this.displayedUri = uri;
      this.displayedVersion = this.generation;
      this.pendingUri = '';
      this.failed = false;
      this.frontSlotId = 'a';
      this.pendingSlotId = '';
      this.slotAUri = uri;
      this.slotAVersion = this.generation;
      this.slotBUri = '';
      this.slotBVersion = 0;
      return this.generation;
    }
    this.pendingSlotId = this.frontSlotId === 'a' ? 'b' : 'a';
    this.setSlot(this.pendingSlotId, uri, this.generation);
    this.pendingUri = uri;
    this.failed = false;
    return this.generation;
  }

  currentGeneration(): number {
    return this.generation;
  }

  displayedRequestVersion(): number {
    return this.displayedVersion;
  }

  frontSlot(): string {
    return this.frontSlotId;
  }

  pendingSlot(): string {
    return this.pendingSlotId;
  }

  slotUri(slot: string): string {
    return slot === 'a' ? this.slotAUri : this.slotBUri;
  }

  slotVersion(slot: string): number {
    return slot === 'a' ? this.slotAVersion : this.slotBVersion;
  }

  isPendingSlot(slot: string): boolean {
    return this.pendingSlotId === slot;
  }

  completePending(generation: number, uri: string): boolean {
    if (!this.acceptsPending(generation, uri)) {
      return false;
    }
    const previousFront = this.frontSlotId;
    this.frontSlotId = this.pendingSlotId;
    this.displayedUri = uri;
    this.displayedVersion = this.slotVersion(this.frontSlotId);
    this.pendingSlotId = '';
    this.pendingUri = '';
    this.failed = false;
    this.setSlot(previousFront, '', 0);
    return true;
  }

  failPending(generation: number, uri: string): boolean {
    if (!this.acceptsPending(generation, uri)) {
      return false;
    }
    this.failed = true;
    return true;
  }

  retry(): number {
    if (this.pendingUri.length === 0) {
      return this.generation;
    }
    this.generation += 1;
    this.setSlot(this.pendingSlotId, this.pendingUri, this.generation);
    this.failed = false;
    return this.generation;
  }

  invalidate(): void {
    this.generation += 1;
    this.clearPending();
  }

  private acceptsPending(generation: number, uri: string): boolean {
    return generation === this.generation && this.pendingSlotId.length > 0 && uri.length > 0 &&
      uri === this.pendingUri && this.slotVersion(this.pendingSlotId) === generation;
  }

  private setSlot(slot: string, uri: string, version: number): void {
    if (slot === 'a') {
      this.slotAUri = uri;
      this.slotAVersion = version;
    } else {
      this.slotBUri = uri;
      this.slotBVersion = version;
    }
  }

  private clearPending(): void {
    if (this.pendingSlotId.length > 0) {
      this.setSlot(this.pendingSlotId, '', 0);
    }
    this.pendingSlotId = '';
    this.pendingUri = '';
    this.failed = false;
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

  zoomTo(scale: number): void {
    this.scale = Math.max(1, Math.min(5, Number.isFinite(scale) ? scale : 1));
    this.baseScale = this.scale;
  }

  resetAfterMove(): void {
    this.scale = 1;
    this.baseScale = 1;
  }
}

/**
 * Tracks the single finger that pans a zoomed photo.
 *
 * A finger that is already on screen never emits a fresh Down event, so when
 * a two-finger pinch ends with one finger still resting on the display, the
 * pan must adopt that finger on its next Move instead of waiting for a new
 * Down — otherwise the pinch-to-pan handoff kills panning entirely and the
 * corners of the zoomed photo are unreachable. Touch types mirror ArkUI's
 * TouchType (Down=0, Up=1, Move=2, Cancel=3) so host tests need no UI SDK.
 */
export class PhotoViewerPanTracker {
  static readonly TOUCH_DOWN: number = 0;
  static readonly TOUCH_UP: number = 1;
  static readonly TOUCH_MOVE: number = 2;
  static readonly TOUCH_CANCEL: number = 3;

  private touchId: number = -1;
  private startX: number = 0;
  private startY: number = 0;
  sessionBegan: boolean = false;
  deltaX: number = 0;
  deltaY: number = 0;

  onTouch(zoomed: boolean, type: number, touchCount: number, touchId: number,
    x: number, y: number): boolean {
    this.sessionBegan = false;
    if (!zoomed || touchCount !== 1) {
      this.touchId = -1;
      return false;
    }
    if (type === PhotoViewerPanTracker.TOUCH_DOWN) {
      return this.adopt(touchId, x, y);
    }
    if (type === PhotoViewerPanTracker.TOUCH_MOVE) {
      if (touchId === this.touchId) {
        this.deltaX = x - this.startX;
        this.deltaY = y - this.startY;
        return true;
      }
      return this.adopt(touchId, x, y);
    }
    // Up/Cancel end the session; a finger still resting re-adopts on Move.
    this.touchId = -1;
    return false;
  }

  private adopt(touchId: number, x: number, y: number): boolean {
    this.touchId = touchId;
    this.startX = x;
    this.startY = y;
    this.deltaX = 0;
    this.deltaY = 0;
    this.sessionBegan = true;
    return false;
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

export class ViewerNavigationSeedCoordinator {
  private captureId: string = '';
  private seedUri: string = '';
  private seedContentVersion: number = 0;
  private sourceUri: string = '';
  private sourceContentVersion: number = 0;
  private backingUri: string = '';
  private backingContentVersion: number = 0;
  private generation: number = 0;
  private trusted: boolean = false;
  private replacementTarget: boolean = false;

  seed(captureId: string, uri: string, contentVersion: number = 0): void {
    this.generation += 1;
    this.captureId = captureId;
    this.seedUri = uri;
    this.seedContentVersion = contentVersion;
    this.sourceUri = uri;
    this.sourceContentVersion = contentVersion;
    this.backingUri = uri;
    this.backingContentVersion = contentVersion;
    this.trusted = false;
    this.replacementTarget = false;
  }

  acceptTrustedWindow(captureId: string, currentUri: string, contentVersion: number,
    trusted: boolean): boolean {
    if (!trusted || captureId !== this.captureId) {
      return false;
    }
    const nextUri = currentUri.length > 0 ? currentUri : this.sourceUri;
    const changed = !this.trusted || nextUri !== this.sourceUri ||
      contentVersion !== this.sourceContentVersion;
    this.trusted = true;
    if (!changed) {
      return false;
    }
    this.generation += 1;
    this.sourceUri = nextUri;
    this.sourceContentVersion = contentVersion;
    this.replacementTarget = this.backingUri.length > 0 &&
      (this.sourceUri !== this.seedUri || this.sourceContentVersion !== this.seedContentVersion);
    return true;
  }

  sourceUriFor(captureId: string, currentUri: string): string {
    return this.captureId === captureId && this.sourceUri.length > 0 ? this.sourceUri : currentUri;
  }

  sourceContentVersionFor(captureId: string, currentVersion: number): number {
    return this.captureId === captureId ? this.sourceContentVersion : currentVersion;
  }

  backingUriFor(captureId: string): string {
    return this.captureId === captureId ? this.backingUri : '';
  }

  backingContentVersionFor(captureId: string): number {
    return this.captureId === captureId ? this.backingContentVersion : 0;
  }

  shouldRenderTarget(captureId: string): boolean {
    return this.captureId !== captureId || this.backingUri.length === 0 || this.replacementTarget;
  }

  targetGenerationFor(captureId: string): number {
    return this.captureId === captureId ? this.generation : 0;
  }

  targetRequestVersionFor(captureId: string, currentVersion: number): number {
    return this.captureId === captureId ? this.generation : currentVersion;
  }

  targetLoaded(generation: number, captureId: string, uri: string): boolean {
    if (!this.acceptsTarget(generation, captureId, uri) || !this.replacementTarget ||
      this.backingUri.length === 0) {
      return false;
    }
    this.backingUri = '';
    this.backingContentVersion = 0;
    this.replacementTarget = false;
    return true;
  }

  targetFailed(generation: number, captureId: string, uri: string): boolean {
    return this.acceptsTarget(generation, captureId, uri) && this.replacementTarget;
  }

  invalidateCallbacks(): void {
    if (this.captureId.length > 0) {
      this.generation += 1;
    }
  }

  private acceptsTarget(generation: number, captureId: string, uri: string): boolean {
    return this.trusted && generation === this.generation && captureId === this.captureId &&
      uri.length > 0 && uri === this.sourceUri;
  }
}

export class ViewerFullImageRequest {
  readonly captureId: string;
  readonly uri: string;
  readonly contentVersion: number;
  readonly generation: number;
  readonly requestVersion: number;

  constructor(captureId: string, uri: string, contentVersion: number, generation: number,
    requestVersion: number) {
    this.captureId = captureId;
    this.uri = uri;
    this.contentVersion = contentVersion;
    this.generation = generation;
    this.requestVersion = requestVersion;
  }
}

export class ViewerFullImageCoordinator {
  failed: boolean = false;
  loaded: boolean = false;
  private generation: number = 0;
  private requestVersion: number = 0;
  private request: ViewerFullImageRequest | null = null;

  prepare(captureId: string, uri: string, contentVersion: number): ViewerFullImageRequest {
    if (this.request !== null && this.request.captureId === captureId && this.request.uri === uri &&
      this.request.contentVersion === contentVersion) {
      return this.request;
    }
    this.generation += 1;
    this.requestVersion += 1;
    this.request = new ViewerFullImageRequest(captureId, uri, contentVersion, this.generation,
      this.requestVersion);
    this.failed = false;
    this.loaded = false;
    return this.request;
  }

  current(): ViewerFullImageRequest | null {
    return this.request;
  }

  fail(generation: number, captureId: string, uri: string): boolean {
    if (!this.accepts(generation, captureId, uri)) {
      return false;
    }
    this.failed = true;
    this.loaded = false;
    return true;
  }

  complete(generation: number, captureId: string, uri: string): boolean {
    if (!this.accepts(generation, captureId, uri)) {
      return false;
    }
    this.failed = false;
    this.loaded = true;
    return true;
  }

  retry(): ViewerFullImageRequest | null {
    if (this.request === null || !this.failed) {
      return null;
    }
    this.generation += 1;
    this.requestVersion += 1;
    this.request = new ViewerFullImageRequest(this.request.captureId, this.request.uri,
      this.request.contentVersion, this.generation, this.requestVersion);
    this.failed = false;
    this.loaded = false;
    return this.request;
  }

  invalidate(): void {
    this.generation += 1;
    this.request = null;
    this.failed = false;
    this.loaded = false;
  }

  isFailedFor(captureId: string, uri: string): boolean {
    return this.failed && this.request !== null && this.request.captureId === captureId &&
      this.request.uri === uri;
  }

  private accepts(generation: number, captureId: string, uri: string): boolean {
    return this.request !== null && this.request.generation === generation &&
      this.request.captureId === captureId && this.request.uri === uri;
  }
}

export class ViewerNodePolicy {
  // 查看器左右切换比通用 UI 动效慢：图片切换需要更稳的过渡。
  static readonly SWIPE_DURATION: number = 320;

  static decodeEdge(current: boolean): number {
    return current ? 2048 : 1024;
  }

  static key(captureId: string, current: boolean): string {
    return `${captureId}-${current ? 'full' : 'preview'}`;
  }
}
