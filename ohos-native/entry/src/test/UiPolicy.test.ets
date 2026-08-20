import { describe, expect, it } from '@ohos/hypium';
import { CaptureFilter } from '../main/ets/domain/Models';
import { ProjectLifecycleStatus } from '../main/ets/domain/StateMachine';
import { ImageDecodePolicy, ImageRequestState } from '../main/ets/shared/AppImage';
import { MotionPolicy, ReduceMotionQueryPolicy } from '../main/ets/shared/MotionPolicy';
import { ScreenStateStore } from '../main/ets/shared/ScreenStateStore';
import { forwardUiMemoryLevel, UiMemoryBroadcaster, UiMemoryCoordinator } from '../main/ets/shared/UiMemoryCoordinator';

function filter(projectId: string, searchText: string): CaptureFilter {
  return {
    projectId: projectId,
    year: 2026,
    month: 8,
    day: 20,
    searchText: searchText,
  };
}

class RecordingUiMemory implements UiMemoryBroadcaster {
  levels: number[] = [];

  broadcast(level: number): void {
    this.levels.push(level);
  }
}

export default function uiPolicyTest(): void {
  describe('Ui policies', () => {
    it('bounds image decoding for thumbnails detail and viewer neighbors', 0, () => {
      expect(ImageDecodePolicy.thumbnail(1, 0.1)).assertEqual(256);
      expect(ImageDecodePolicy.thumbnail(56, 2.5)).assertEqual(256);
      expect(ImageDecodePolicy.thumbnail(500, 1.5)).assertEqual(750);
      expect(ImageDecodePolicy.thumbnail(10000, 3)).assertEqual(1024);
      expect(ImageDecodePolicy.thumbnail(Number.NaN, 1)).assertEqual(256);
      expect(ImageDecodePolicy.thumbnail(100, Number.POSITIVE_INFINITY)).assertEqual(256);
      expect(ImageDecodePolicy.detail()).assertEqual(2048);
      expect(ImageDecodePolicy.viewer(true)).assertEqual(2048);
      expect(ImageDecodePolicy.viewer(false)).assertEqual(1024);
    });

    it('normalizes every component decode edge to a finite positive integer no greater than 2048', 0, () => {
      expect(ImageDecodePolicy.sourceSizeEdge(511.01)).assertEqual(512);
      expect(ImageDecodePolicy.sourceSizeEdge(2048.01)).assertEqual(2048);
      expect(ImageDecodePolicy.sourceSizeEdge(0)).assertEqual(256);
      expect(ImageDecodePolicy.sourceSizeEdge(-1)).assertEqual(256);
      expect(ImageDecodePolicy.sourceSizeEdge(Number.NaN)).assertEqual(256);
      expect(ImageDecodePolicy.sourceSizeEdge(Number.POSITIVE_INFINITY)).assertEqual(256);
    });

    it('resets an image request from loaded A to an unloaded B', 0, () => {
      let state = ImageRequestState.initial().forUri('file://A');
      const generationA = state.generation;
      state = state.complete(generationA);
      expect(state.loaded).assertTrue();

      state = state.forUri('file://B');
      expect(state.uri).assertEqual('file://B');
      expect(state.loaded).assertFalse();
      expect(state.failed).assertFalse();
    });

    it('resets an image request from failed A to an unloaded B', 0, () => {
      let state = ImageRequestState.initial().forUri('file://A');
      const generationA = state.generation;
      state = state.fail(generationA);
      expect(state.failed).assertTrue();

      state = state.forUri('file://B');
      expect(state.uri).assertEqual('file://B');
      expect(state.loaded).assertFalse();
      expect(state.failed).assertFalse();
    });

    it('ignores late callbacks from A after B starts and gives retry a fresh generation', 0, () => {
      let state = ImageRequestState.initial().forUri('file://A');
      const generationA = state.generation;
      state = state.forUri('file://B');
      const generationB = state.generation;

      state = state.complete(generationA);
      expect(state.loaded).assertFalse();
      state = state.fail(generationA);
      expect(state.failed).assertFalse();
      state = state.complete(generationB);
      expect(state.loaded).assertTrue();
      const retry = state.retry();
      expect(retry.generation).assertEqual(generationB + 1);
      expect(retry.loaded).assertFalse();
      expect(retry.failed).assertFalse();
    });

    it('removes motion duration and blur only when reduce motion is enabled', 0, () => {
      MotionPolicy.reduceMotion = false;
      expect(MotionPolicy.duration(180)).assertEqual(180);
      expect(MotionPolicy.blur(20)).assertEqual(20);

      MotionPolicy.reduceMotion = true;
      expect(MotionPolicy.duration(180)).assertEqual(0);
      expect(MotionPolicy.blur(20)).assertEqual(0);
      MotionPolicy.reduceMotion = false;
    });

    it('does not query reduce motion below API 23', 0, async () => {
      let calls: number = 0;
      await MotionPolicy.refreshFor(22, async (): Promise<boolean> => {
        calls += 1;
        return true;
      });

      expect(calls).assertEqual(0);
      expect(MotionPolicy.reduceMotion).assertFalse();
    });

    it('uses true and false reduce motion values at API 23', 0, async () => {
      const trueValue = await ReduceMotionQueryPolicy.read(23, async (): Promise<boolean> => true);
      const falseValue = await ReduceMotionQueryPolicy.read(23, async (): Promise<boolean> => false);

      expect(trueValue).assertTrue();
      expect(falseValue).assertFalse();
    });

    it('reads reduce motion without committing until the caller accepts the result', 0, async () => {
      MotionPolicy.reduceMotion = false;
      const value = await MotionPolicy.readFor(23, async (): Promise<boolean> => true);

      expect(value).assertTrue();
      expect(MotionPolicy.reduceMotion).assertFalse();
      MotionPolicy.commit(value);
      expect(MotionPolicy.reduceMotion).assertTrue();

      MotionPolicy.reduceMotion = false;
      await MotionPolicy.refreshFor(23, async (): Promise<boolean> => true);
      expect(MotionPolicy.reduceMotion).assertTrue();
      MotionPolicy.reduceMotion = false;
    });

    it('falls back to false when the reduce motion query throws', 0, async () => {
      const value = await ReduceMotionQueryPolicy.read(23, async (): Promise<boolean> => {
        throw new Error('expected_reduce_motion_failure');
      });

      expect(value).assertFalse();
    });

    it('copies root and capture state so callers cannot mutate cached state', 0, () => {
      const store = new ScreenStateStore();
      const rootFilter = filter('', 'before');
      const captureFilter = filter('project-a', 'capture-before');
      store.saveProject(ProjectLifecycleStatus.ACTIVE, { searchText: 'project-before', firstVisibleIndex: 4 });
      store.saveCaptures({ filter: rootFilter, filterOpen: true, firstVisibleIndex: 7 });
      store.saveProjectDetail('project-a', { filter: captureFilter, firstVisibleIndex: 9 });

      rootFilter.searchText = 'outside-change';
      captureFilter.searchText = 'outside-change';
      const projectState = store.project(ProjectLifecycleStatus.ACTIVE);
      const capturesState = store.captures();
      const detailState = store.projectDetail('project-a');
      projectState.searchText = 'returned-change';
      capturesState.filter.searchText = 'returned-change';
      detailState.filter.searchText = 'returned-change';

      expect(store.project(ProjectLifecycleStatus.ACTIVE).searchText).assertEqual('project-before');
      expect(store.captures().filter.searchText).assertEqual('before');
      expect(store.projectDetail('project-a').filter.searchText).assertEqual('capture-before');
    });

    it('keeps at most eight project detail states and refreshes LRU access', 0, () => {
      const store = new ScreenStateStore();
      for (let index = 1; index <= 8; index += 1) {
        const id = `project-${index}`;
        store.saveProjectDetail(id, { filter: filter(id, id), firstVisibleIndex: index });
      }
      store.projectDetail('project-1');
      store.saveProjectDetail('project-9', { filter: filter('project-9', 'project-9'), firstVisibleIndex: 9 });

      expect(store.projectDetailCount()).assertEqual(8);
      expect(store.hasProjectDetail('project-1')).assertTrue();
      expect(store.hasProjectDetail('project-2')).assertFalse();
      expect(store.hasProjectDetail('project-9')).assertTrue();
    });

    it('forwards memory levels only to the UI memory broadcaster', 0, () => {
      const memory = new RecordingUiMemory();
      forwardUiMemoryLevel(7, memory);
      forwardUiMemoryLevel(8, null);

      expect(memory.levels.join(',')).assertEqual('7');
    });

    it('continues UI memory broadcasts after listener failure', 0, () => {
      const coordinator = new UiMemoryCoordinator();
      let receivedLevel: number = 0;
      coordinator.register((_level: number): void => {
        throw new Error('listener_failure');
      });
      const listener = (level: number): void => {
        receivedLevel = level;
      };
      coordinator.register(listener);
      coordinator.register(listener);

      coordinator.broadcast(7);
      expect(receivedLevel).assertEqual(7);
      coordinator.unregister(listener);
      coordinator.broadcast(8);
      expect(receivedLevel).assertEqual(7);
    });
  });
}
