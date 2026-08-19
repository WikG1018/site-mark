import { describe, expect, it } from '@ohos/hypium';
import { MediaCleanup, MediaCleanupDatabase, MediaDeleteService } from
  '../main/ets/core/system/MediaCleanup';
import { MediaCleanupTask } from '../main/ets/data/database/AppDatabase';

class FakeCleanupDatabase implements MediaCleanupDatabase {
  referenced: boolean = false;
  completed: string[] = [];
  failed: string[] = [];

  pendingMediaCleanups(): Promise<MediaCleanupTask[]> {
    return Promise.resolve([new MediaCleanupTask('media://old', 'capture-a', 0)]);
  }

  isPublishedUriReferenced(_uri: string): Promise<boolean> {
    return Promise.resolve(this.referenced);
  }

  completeMediaCleanup(uri: string): Promise<void> {
    this.completed.push(uri);
    return Promise.resolve();
  }

  failMediaCleanup(uri: string): Promise<void> {
    this.failed.push(uri);
    return Promise.resolve();
  }
}

class FakeDeleteService implements MediaDeleteService {
  deleted: string[] = [];

  deletePublishedImage(uri: string): Promise<boolean> {
    this.deleted.push(uri);
    return Promise.resolve(true);
  }
}

export default function mediaCleanupTest(): void {
  describe('MediaCleanup', () => {
    it('keeps a cleanup task while another capture still references its URI', 0, async () => {
      const database = new FakeCleanupDatabase();
      const service = new FakeDeleteService();
      database.referenced = true;

      await new MediaCleanup(database, service).reconcile();

      expect(database.completed.length).assertEqual(0);
      expect(database.failed.length).assertEqual(0);
      expect(service.deleted.length).assertEqual(0);
    });

    it('deletes and completes an unreferenced URI', 0, async () => {
      const database = new FakeCleanupDatabase();
      const service = new FakeDeleteService();

      await new MediaCleanup(database, service).reconcile();

      expect(service.deleted.join(',')).assertEqual('media://old');
      expect(database.completed.join(',')).assertEqual('media://old');
      expect(database.failed.length).assertEqual(0);
    });
  });
}
