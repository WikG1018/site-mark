import { describe, expect, it } from '@ohos/hypium';
import { CaptureFilter, CaptureRecord } from '../main/ets/domain/Models';
import { CaptureStatus } from '../main/ets/domain/StateMachine';
import { BatchActionItem } from '../main/ets/shared/AppComponents';
import { DetailMediaSwapCoordinator, PhotoViewerGestureState, RecordBatchLayoutPolicy,
  RecordNavigationSeedStore, RecordRefreshGate, RecordRestorePolicy, RecordSearchCoordinator,
  RecordSelectionCoordinator, RecordTimerScheduler, RenderedRefreshTracker, ViewerRenderedVersionTracker,
  ViewerFullImageCoordinator, ViewerNavigationSeedCoordinator,
  ViewerNodePolicy } from '../main/ets/feature/records/RecordUiCoordinator';
import { ListPageCoordinator } from '../main/ets/shared/ListPageCoordinator';
import { RootShellPolicy } from '../main/ets/shared/RootShellPolicy';
import { UiTokens } from '../main/ets/shared/UiTokens';

class ScheduledTask {
  id: number;
  action: () => void;

  constructor(id: number, action: () => void) {
    this.id = id;
    this.action = action;
  }
}

class ManualTimerScheduler implements RecordTimerScheduler {
  private nextId: number = 1;
  readonly tasks: ScheduledTask[] = [];
  readonly cancelled: number[] = [];

  schedule(action: () => void, _delayMs: number): number {
    const id = this.nextId;
    this.nextId += 1;
    this.tasks.push(new ScheduledTask(id, action));
    return id;
  }

  cancel(id: number): void {
    this.cancelled.push(id);
  }

  fire(id: number): void {
    const task = this.tasks.find((candidate: ScheduledTask): boolean => candidate.id === id);
    if (task !== undefined) {
      task.action();
    }
  }
}

class DeferredCaptureIds {
  readonly promise: Promise<string[]>;
  private resolveIds: (ids: string[]) => void = (_ids: string[]): void => {};

  constructor() {
    this.promise = new Promise<string[]>((resolve: (ids: string[]) => void): void => {
      this.resolveIds = resolve;
    });
  }

  resolve(ids: string[]): void {
    this.resolveIds(ids);
  }
}

function selectionFilter(projectId: string, searchText: string = ''): CaptureFilter {
  return { projectId, year: 2026, month: 8, day: 20, searchText };
}

function seedCapture(id: string): CaptureRecord {
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
    createdAt: 1,
    capturedAt: 1,
    latitude: null,
    longitude: null,
    accuracyMeters: null,
    address: '',
    locationOutcome: '',
    processingAttempts: 1,
    watermarkLocaleCode: 'zh',
    locationResolution: 'resolved',
    originalDeletedAt: null
  });
}

export default function recordUiCoordinatorTest(): void {
  describe('Record UI coordinators', () => {
    it('submits only the final 250ms search and ignores cancelled callbacks', 0, () => {
      const scheduler = new ManualTimerScheduler();
      const coordinator = new RecordSearchCoordinator(scheduler);
      const submitted: string[] = [];

      expect(coordinator.activate()).assertTrue();
      expect(coordinator.activate()).assertFalse();
      coordinator.schedule((): void => { submitted.push('first'); });
      coordinator.schedule((): void => { submitted.push('second'); });
      expect(scheduler.cancelled.join(',')).assertEqual('1');

      scheduler.fire(1);
      scheduler.fire(2);
      expect(submitted.join(',')).assertEqual('second');
    });

    it('cancels search on hide and allows one fresh activation after reconstruction', 0, () => {
      const scheduler = new ManualTimerScheduler();
      const coordinator = new RecordSearchCoordinator(scheduler);
      const submitted: string[] = [];

      coordinator.activate();
      coordinator.schedule((): void => { submitted.push('stale'); });
      expect(coordinator.deactivate()).assertTrue();
      expect(coordinator.deactivate()).assertFalse();
      scheduler.fire(1);
      expect(submitted.length).assertEqual(0);

      expect(coordinator.activate()).assertTrue();
      coordinator.schedule((): void => { submitted.push('fresh'); });
      scheduler.fire(2);
      expect(submitted.join(',')).assertEqual('fresh');
    });

    it('tears down record page listeners once when hidden and disappearing callbacks both run', 0, () => {
      const lifecycle = new ListPageCoordinator();
      let detachCount = 0;
      const deactivate = (): void => {
        if (lifecycle.deactivate()) {
          detachCount += 1;
        }
      };

      expect(lifecycle.activate()).assertTrue();
      deactivate();
      deactivate();
      expect(detachCount).assertEqual(1);
      expect(lifecycle.isActive()).assertFalse();

      expect(lifecycle.activate()).assertTrue();
      deactivate();
      expect(detachCount).assertEqual(2);
    });

    it('clears selection and pending permanent deletion when selection mode exits', 0, () => {
      const selection = new RecordSelectionCoordinator();
      selection.enter();
      selection.toggle('a');
      selection.toggle('b');
      expect(selection.requestPermanentDelete()).assertFalse();
      expect(selection.confirmDelete).assertTrue();
      expect(selection.requestPermanentDelete()).assertTrue();

      selection.exit();
      expect(selection.selectionMode).assertFalse();
      expect(selection.selectedIds.length).assertEqual(0);
      expect(selection.allSelected).assertFalse();
      expect(selection.confirmDelete).assertFalse();
    });

    it('selects and deselects every filtered id without changing toggle semantics', 0, () => {
      const selection = new RecordSelectionCoordinator();
      selection.enter();
      selection.selectAll(['a', 'b', 'c']);
      expect(selection.allSelected).assertTrue();
      expect(selection.selectedIds.join(',')).assertEqual('a,b,c');
      selection.toggle('b');
      expect(selection.allSelected).assertFalse();
      expect(selection.selectedIds.join(',')).assertEqual('a,c');
      selection.selectAll([]);
      expect(selection.allSelected).assertFalse();
      expect(selection.selectedIds.length).assertEqual(0);
    });

    it('drops a delayed select-all result after the filter token is invalidated', 0, async () => {
      const selection = new RecordSelectionCoordinator();
      const deferred = new DeferredCaptureIds();
      const requestedFilter = selectionFilter('project-a', 'before');
      selection.enter();
      const token = selection.beginSelectAll(requestedFilter);
      const completion = deferred.promise.then((ids: string[]): boolean =>
        selection.commitSelectAll(token, selectionFilter('project-a', 'after'), ids));

      selection.invalidatePending();
      deferred.resolve(['stale-a', 'stale-b']);

      expect(await completion).assertFalse();
      expect(selection.selectedIds.length).assertEqual(0);
      expect(selection.allSelected).assertFalse();
    });

    it('drops a delayed select-all result after selection exits or a newer generation begins', 0, async () => {
      const selection = new RecordSelectionCoordinator();
      const filter = selectionFilter('project-a');
      const deferred = new DeferredCaptureIds();
      selection.enter();
      const exitedToken = selection.beginSelectAll(filter);
      const exitedCompletion = deferred.promise.then((ids: string[]): boolean =>
        selection.commitSelectAll(exitedToken, filter, ids));
      selection.exit();
      deferred.resolve(['stale']);
      expect(await exitedCompletion).assertFalse();

      selection.enter();
      const oldToken = selection.beginSelectAll(filter);
      const currentToken = selection.beginSelectAll(filter);
      expect(selection.commitSelectAll(oldToken, filter, ['old'])).assertFalse();
      expect(selection.commitSelectAll(currentToken, filter, ['current'])).assertTrue();
      expect(selection.selectedIds.join(',')).assertEqual('current');
    });

    it('clears hidden selections and permanent-delete confirmation when filters change', 0, () => {
      const selection = new RecordSelectionCoordinator();
      selection.enter();
      selection.selectAll(['visible', 'soon-hidden']);
      expect(selection.requestPermanentDelete()).assertFalse();

      selection.resetForFilterChange();

      expect(selection.selectionMode).assertTrue();
      expect(selection.selectedIds.length).assertEqual(0);
      expect(selection.allSelected).assertFalse();
      expect(selection.confirmDelete).assertFalse();
    });

    it('suppresses local root notifications without triggering record reloads', 0, async () => {
      const gate = new RecordRefreshGate();
      let loaderCalls = 0;
      const runtimeListener = (): void => {
        if (gate.shouldRefresh()) {
          loaderCalls += 1;
        }
      };

      gate.runSuppressed(runtimeListener);
      gate.runSuppressed(runtimeListener);
      expect(loaderCalls).assertEqual(0);

      await gate.runSuppressedAsync(async (): Promise<void> => { runtimeListener(); });
      expect(loaderCalls).assertEqual(0);
      runtimeListener();
      expect(loaderCalls).assertEqual(1);
    });

    it('consumes one matching navigation seed and rejects a stale destination', 0, () => {
      RecordNavigationSeedStore.clear();
      const capture = seedCapture('capture-a');
      RecordNavigationSeedStore.put(capture, 'file://rendered-a');

      expect(RecordNavigationSeedStore.take('capture-b') === null).assertTrue();
      expect(RecordNavigationSeedStore.take('capture-a') === null).assertTrue();

      RecordNavigationSeedStore.put(capture, 'file://rendered-a');
      const seed = RecordNavigationSeedStore.take('capture-a');
      expect(seed === null).assertFalse();
      expect(seed!.capture.id).assertEqual('capture-a');
      expect(seed!.uri).assertEqual('file://rendered-a');
      expect(RecordNavigationSeedStore.take('capture-a') === null).assertTrue();
    });

    it('switches data to a trusted rendered target while retaining the decoded seed as visual backing', 0, () => {
      const seed = new ViewerNavigationSeedCoordinator();
      seed.seed('capture-a', 'file://original-a', 1);

      expect(seed.sourceUriFor('capture-a', 'file://rendered-new')).assertEqual('file://original-a');
      expect(seed.acceptTrustedWindow('capture-a', 'file://rendered-new', 2, false)).assertFalse();
      expect(seed.acceptTrustedWindow('capture-a', 'file://rendered-new', 2, true)).assertTrue();
      expect(seed.sourceUriFor('capture-a', 'file://ignored')).assertEqual('file://rendered-new');
      expect(seed.backingUriFor('capture-a')).assertEqual('file://original-a');
      expect(seed.shouldRenderTarget('capture-a')).assertTrue();

      const generation = seed.targetGenerationFor('capture-a');
      expect(seed.targetFailed(generation, 'capture-a', 'file://rendered-new')).assertTrue();
      expect(seed.backingUriFor('capture-a')).assertEqual('file://original-a');
      expect(seed.targetLoaded(generation, 'capture-a', 'file://rendered-new')).assertTrue();
      expect(seed.backingUriFor('capture-a')).assertEqual('');
    });

    it('does not let an older image callback release the visual seed for a newer target', 0, () => {
      const seed = new ViewerNavigationSeedCoordinator();
      seed.seed('capture-a', 'file://original-a', 1);
      seed.acceptTrustedWindow('capture-a', 'file://rendered-v1', 2, true);
      const oldGeneration = seed.targetGenerationFor('capture-a');
      seed.acceptTrustedWindow('capture-a', 'file://rendered-v2', 3, true);

      expect(seed.targetLoaded(oldGeneration, 'capture-a', 'file://rendered-v1')).assertFalse();
      expect(seed.backingUriFor('capture-a')).assertEqual('file://original-a');
      expect(seed.targetLoaded(seed.targetGenerationFor('capture-a'), 'capture-a',
        'file://rendered-v2')).assertTrue();
      expect(seed.backingUriFor('capture-a')).assertEqual('');
    });

    it('keeps the visual seed when a target callback arrives after the viewer is hidden', 0, () => {
      const seed = new ViewerNavigationSeedCoordinator();
      seed.seed('capture-a', 'file://original-a', 1);
      seed.acceptTrustedWindow('capture-a', 'file://rendered-new', 2, true);
      const hiddenGeneration = seed.targetGenerationFor('capture-a');

      seed.invalidateCallbacks();

      expect(seed.targetLoaded(hiddenGeneration, 'capture-a', 'file://rendered-new')).assertFalse();
      expect(seed.targetFailed(hiddenGeneration, 'capture-a', 'file://rendered-new')).assertFalse();
      expect(seed.backingUriFor('capture-a')).assertEqual('file://original-a');
    });

    it('derives selected list padding from the exact batch bar height', 0, () => {
      expect(RecordBatchLayoutPolicy.listBottomPadding(true))
        .assertEqual(RecordBatchLayoutPolicy.barHeight() + RecordBatchLayoutPolicy.bottomMargin() +
          RecordBatchLayoutPolicy.contentGap());
      expect(RecordBatchLayoutPolicy.barHeight()).assertEqual(104);
      expect(RecordBatchLayoutPolicy.actionHeight()).assertEqual(68);
      expect(RecordBatchLayoutPolicy.actionLabelMaxLines()).assertEqual(2);
      expect(RecordBatchLayoutPolicy.listBottomPadding(true)).assertEqual(132);
      expect(RecordBatchLayoutPolicy.listBottomPadding(false) <
        RecordBatchLayoutPolicy.listBottomPadding(true)).assertTrue();
    });

    it('shares root dock clearance and accessible filter heights with project detail', 0, () => {
      expect(RecordBatchLayoutPolicy.listBottomPadding(false)).assertEqual(RootShellPolicy.contentBottomInset());
      expect(RecordBatchLayoutPolicy.filterControlHeight()).assertEqual(UiTokens.TOUCH_TARGET);
      expect(RecordBatchLayoutPolicy.filterControlHeight() >= 44).assertTrue();
      expect(RecordBatchLayoutPolicy.listBottomPadding(false, 1, 36))
        .assertEqual(RootShellPolicy.contentBottomInset() + 36);
      expect(RecordBatchLayoutPolicy.listBottomPadding(true, 1, 36)).assertEqual(168);
      expect(RecordBatchLayoutPolicy.listBottomPadding(true, 1.6, 36)).assertEqual(188);
      expect(RecordBatchLayoutPolicy.listBottomPadding(false, 1, Number.NaN))
        .assertEqual(RootShellPolicy.contentBottomInset());
      expect(RecordBatchLayoutPolicy.listBottomPadding(false, 1, -8))
        .assertEqual(RootShellPolicy.contentBottomInset());
    });

    it('applies list clearance as content end offset not viewport padding', 0, () => {
      expect(RecordBatchLayoutPolicy.listViewportBottomPadding()).assertEqual(0);
      expect(RecordBatchLayoutPolicy.listContentEndOffset(false))
        .assertEqual(RecordBatchLayoutPolicy.listBottomPadding(false));
      expect(RecordBatchLayoutPolicy.listContentEndOffset(true, 1, 36))
        .assertEqual(RecordBatchLayoutPolicy.listBottomPadding(true, 1, 36));
      expect(RecordBatchLayoutPolicy.listContentEndOffset(false, 1, 36))
        .assertEqual(RootShellPolicy.contentBottomInset() + 36);
    });

    it('grows the shared batch bar and its exact list clearance for 160 percent fonts', 0, () => {
      expect(RecordBatchLayoutPolicy.actionHeight(1.6)).assertEqual(84);
      expect(RecordBatchLayoutPolicy.barHeight(1.6)).assertEqual(124);
      expect(RecordBatchLayoutPolicy.listBottomPadding(true, 1.6)).assertEqual(
        RecordBatchLayoutPolicy.barHeight(1.6) + RecordBatchLayoutPolicy.bottomMargin() +
          RecordBatchLayoutPolicy.contentGap());
      expect(RecordBatchLayoutPolicy.listBottomPadding(true, 1.6)).assertEqual(152);
      expect(RecordBatchLayoutPolicy.barHeight(3) > RecordBatchLayoutPolicy.barHeight(1.6)).assertTrue();
    });

    it('keeps short batch labels separate from complete accessibility descriptions', 0, () => {
      const item = new BatchActionItem('delete', '×', 'Delete', true, false,
        'Permanently delete selected photos; this cannot be undone');

      expect(item.label).assertEqual('Delete');
      expect(item.accessibilityLabel).assertEqual(
        'Permanently delete selected photos; this cannot be undone');
    });

    it('loads enough pages to restore a saved record beyond the first page', 0, () => {
      expect(RecordRestorePolicy.needsMoreRows(75, 50, true, false)).assertTrue();
      expect(RecordRestorePolicy.needsMoreRows(49, 50, true, false)).assertFalse();
      expect(RecordRestorePolicy.needsMoreRows(75, 50, false, false)).assertFalse();
      expect(RecordRestorePolicy.needsMoreRows(75, 50, true, true)).assertFalse();
    });

    it('promotes the decoded pending detail slot without decoding it again as a base image', 0, () => {
      const media = new DetailMediaSwapCoordinator();
      media.initialize('file://watermarked');
      const originalGeneration = media.begin('file://original');

      expect(media.displayedUri).assertEqual('file://watermarked');
      expect(media.pendingUri).assertEqual('file://original');
      expect(media.frontSlot()).assertEqual('a');
      expect(media.pendingSlot()).assertEqual('b');
      expect(media.slotUri('a')).assertEqual('file://watermarked');
      expect(media.slotUri('b')).assertEqual('file://original');
      expect(media.completePending(originalGeneration - 1, 'file://original')).assertFalse();
      expect(media.displayedUri).assertEqual('file://watermarked');

      expect(media.completePending(originalGeneration, 'file://original')).assertTrue();
      expect(media.displayedUri).assertEqual('file://original');
      expect(media.pendingUri).assertEqual('');
      expect(media.frontSlot()).assertEqual('b');
      expect(media.slotUri('b')).assertEqual('file://original');
      expect(media.slotVersion('b')).assertEqual(originalGeneration);
      expect(media.slotUri('a')).assertEqual('');
    });

    it('keeps the current detail image after failure and retries with a new generation', 0, () => {
      const media = new DetailMediaSwapCoordinator();
      media.initialize('file://watermarked');
      const failedGeneration = media.begin('file://original');
      expect(media.failPending(failedGeneration, 'file://original')).assertTrue();
      expect(media.displayedUri).assertEqual('file://watermarked');
      expect(media.failed).assertTrue();

      const retryGeneration = media.retry();
      expect(retryGeneration > failedGeneration).assertTrue();
      expect(media.failed).assertFalse();
      expect(media.failPending(failedGeneration, 'file://original')).assertFalse();
      expect(media.completePending(failedGeneration, 'file://original')).assertFalse();
      expect(media.completePending(retryGeneration, 'file://original')).assertTrue();
      expect(media.frontSlot()).assertEqual('b');
      expect(media.slotUri('a')).assertEqual('');
    });

    it('cancels an in-flight detail swap when the user selects the displayed source again', 0, () => {
      const media = new DetailMediaSwapCoordinator();
      media.initialize('file://watermarked');
      const originalGeneration = media.begin('file://original');
      const cancelledGeneration = media.begin('file://watermarked');

      expect(cancelledGeneration > originalGeneration).assertTrue();
      expect(media.displayedUri).assertEqual('file://watermarked');
      expect(media.pendingUri).assertEqual('');
      expect(media.failed).assertFalse();
      expect(media.completePending(originalGeneration, 'file://original')).assertFalse();
      expect(media.slotUri('b')).assertEqual('');
    });

    it('double-buffers a forced reload when the rendered file keeps the same uri', 0, () => {
      const media = new DetailMediaSwapCoordinator();
      media.initialize('file://rendered');
      const previousVersion = media.displayedRequestVersion();
      const generation = media.begin('file://rendered', true);

      expect(media.displayedUri).assertEqual('file://rendered');
      expect(media.pendingUri).assertEqual('file://rendered');
      expect(media.displayedRequestVersion()).assertEqual(previousVersion);
      expect(media.completePending(generation, 'file://rendered')).assertTrue();
      expect(media.displayedRequestVersion()).assertEqual(generation);
      expect(media.pendingUri).assertEqual('');
    });

    it('retries a failed full-resolution viewer layer with a new request version over its preview', 0, () => {
      const full = new ViewerFullImageCoordinator();
      const initial = full.prepare('capture-a', 'file://rendered-new', 4);
      expect(initial.requestVersion > 0).assertTrue();
      expect(full.fail(initial.generation, initial.captureId, initial.uri)).assertTrue();
      expect(full.failed).assertTrue();

      const retry = full.retry();
      expect(retry === null).assertFalse();
      expect(retry!.requestVersion > initial.requestVersion).assertTrue();
      expect(full.complete(initial.generation, initial.captureId, initial.uri)).assertFalse();
      expect(full.complete(retry!.generation, retry!.captureId, retry!.uri)).assertTrue();
      expect(full.failed).assertFalse();
      expect(full.loaded).assertTrue();
    });

    it('invalidates late full-resolution success and failure callbacks while the page is hidden', 0, () => {
      const full = new ViewerFullImageCoordinator();
      const hiddenRequest = full.prepare('capture-a', 'file://rendered-new', 4);

      full.invalidate();

      expect(full.current() === null).assertTrue();
      expect(full.complete(hiddenRequest.generation, hiddenRequest.captureId, hiddenRequest.uri)).assertFalse();
      expect(full.fail(hiddenRequest.generation, hiddenRequest.captureId, hiddenRequest.uri)).assertFalse();
      expect(full.loaded).assertFalse();
      expect(full.failed).assertFalse();

      const shownRequest = full.prepare('capture-a', 'file://rendered-new', 4);
      expect(shownRequest.generation > hiddenRequest.generation).assertTrue();
      expect(full.complete(hiddenRequest.generation, hiddenRequest.captureId, hiddenRequest.uri)).assertFalse();
      expect(full.complete(shownRequest.generation, shownRequest.captureId, shownRequest.uri)).assertTrue();
    });

    it('refreshes a rewritten same-uri render only after the next processing attempt is ready', 0, () => {
      const refresh = new RenderedRefreshTracker();
      refresh.expectNextAttempt(3);

      expect(refresh.consumeIfReady(true, 3)).assertFalse();
      expect(refresh.consumeIfReady(false, 4)).assertFalse();
      expect(refresh.consumeIfReady(true, 4)).assertTrue();
      expect(refresh.consumeIfReady(true, 4)).assertFalse();
    });

    it('blocks horizontal paging while zoomed and resets zoom after a photo change', 0, () => {
      const gesture = new PhotoViewerGestureState();
      gesture.beginPinch();
      gesture.updatePinch(2.5);
      expect(gesture.scale).assertEqual(2.5);
      expect(gesture.canSwipe()).assertFalse();
      gesture.resetAfterMove();
      expect(gesture.scale).assertEqual(1);
      expect(gesture.canSwipe()).assertTrue();
    });

    it('gives the viewer swipe a dedicated slower duration than generic UI motion', 0, () => {
      expect(ViewerNodePolicy.SWIPE_DURATION > UiTokens.MOTION_STANDARD).assertTrue();
    });

    it('creates one 2048 node and bounded 1024 neighbors with stable keys', 0, () => {
      const ids = ['a', 'b', 'c', 'd', 'e'];
      const edges = ids.map((id: string): number => ViewerNodePolicy.decodeEdge(id === 'c'));
      expect(edges.filter((edge: number): boolean => edge === 2048).length).assertEqual(1);
      expect(edges.filter((edge: number): boolean => edge === 1024).length).assertEqual(4);
      expect(ViewerNodePolicy.key('c', true)).assertEqual('c-full');
      expect(ViewerNodePolicy.key('c', false)).assertEqual('c-preview');
    });

    it('changes the viewer request version only when a new ready render is available', 0, () => {
      const versions = new ViewerRenderedVersionTracker();

      expect(versions.versionFor('a', true, 3)).assertEqual(3);
      expect(versions.versionFor('a', true, 3)).assertEqual(3);
      expect(versions.versionFor('a', false, 3)).assertEqual(3);
      expect(versions.versionFor('a', false, 4)).assertEqual(3);
      expect(versions.versionFor('a', true, 4)).assertEqual(4);
      expect(versions.versionFor('b', true, 2)).assertEqual(2);
    });
  });
}
