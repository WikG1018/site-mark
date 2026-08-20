import { describe, expect, it } from '@ohos/hypium';
import { SerialCaptureQueue } from '../main/ets/background/SerialCaptureQueue';
import { CaptureFilter } from '../main/ets/domain/Models';
import { ProjectLifecycleStatus } from '../main/ets/domain/StateMachine';
import { ImageDecodePolicy } from '../main/ets/shared/AppImage';
import { MotionPolicy } from '../main/ets/shared/MotionPolicy';
import { ScreenStateStore } from '../main/ets/shared/ScreenStateStore';
import { UiMemoryCoordinator } from '../main/ets/shared/UiMemoryCoordinator';

function filter(projectId: string, searchText: string): CaptureFilter {
  return {
    projectId: projectId,
    year: 2026,
    month: 8,
    day: 20,
    searchText: searchText,
  };
}

export default function uiPolicyTest(): void {
  describe('Ui policies', () => {
    it('bounds image decoding for thumbnails detail and viewer neighbors', 0, () => {
      expect(ImageDecodePolicy.thumbnail(1, 0.1)).assertEqual(256);
      expect(ImageDecodePolicy.thumbnail(56, 2.5)).assertEqual(256);
      expect(ImageDecodePolicy.thumbnail(500, 1.5)).assertEqual(750);
      expect(ImageDecodePolicy.thumbnail(10000, 3)).assertEqual(1024);
      expect(ImageDecodePolicy.detail()).assertEqual(2048);
      expect(ImageDecodePolicy.viewer(true)).assertEqual(2048);
      expect(ImageDecodePolicy.viewer(false)).assertEqual(1024);
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

    it('continues memory broadcasts after listener failure without touching capture processing', 0, async () => {
      const coordinator = new UiMemoryCoordinator();
      let receivedLevel: number = 0;
      const releases: Array<() => void> = [];
      const queue = new SerialCaptureQueue(async (_captureId: string): Promise<void> => {
        await new Promise<void>((resolve: () => void): void => {
          releases.push(resolve);
        });
      });
      coordinator.register((_level: number): void => {
        throw new Error('listener_failure');
      });
      const listener = (level: number): void => {
        receivedLevel = level;
      };
      coordinator.register(listener);
      coordinator.register(listener);
      queue.enqueue('capture-a');
      await Promise.resolve();

      coordinator.broadcast(7);
      expect(receivedLevel).assertEqual(7);
      expect(queue.isBusy()).assertTrue();
      coordinator.unregister(listener);
      coordinator.broadcast(8);
      expect(receivedLevel).assertEqual(7);

      if (releases.length !== 1) {
        throw new Error('queue_processor_not_started');
      }
      releases[0]();
      await queue.drain();
    });
  });
}
