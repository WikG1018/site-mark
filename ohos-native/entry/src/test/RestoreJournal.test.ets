import { describe, expect, it } from '@ohos/hypium';
import { RestoreJournalStorage, RestoreJournalStore } from '../main/ets/data/prefs/RestoreJournalStore';

class MemoryRestoreJournalStorage implements RestoreJournalStorage {
  value: string = '';

  load(): Promise<string> {
    return Promise.resolve(this.value);
  }

  save(value: string): Promise<void> {
    this.value = value;
    return Promise.resolve();
  }
}

export default function restoreJournalTest(): void {
  describe('RestoreJournalStore', () => {
    it('keeps every owned path and deduplicates retry writes', 0, async () => {
      const store = new RestoreJournalStore(new MemoryRestoreJournalStorage());
      await store.begin('restore-1');
      await store.addPaths('restore-1', ['/data/a.jpg', '/data/b.jpg']);
      await store.addPaths('restore-1', ['/data/b.jpg', '/data/c.jpg']);
      const value = await store.recover();
      expect(value?.operationId).assertEqual('restore-1');
      expect(value?.paths.join(',')).assertEqual('/data/a.jpg,/data/b.jpg,/data/c.jpg');
    });

    it('does not allow an older restore to clear or append to a newer journal', 0, async () => {
      const store = new RestoreJournalStore(new MemoryRestoreJournalStorage());
      await store.begin('newer');
      expect(await store.clear('older')).assertFalse();
      let rejected = false;
      try {
        await store.addPaths('older', ['/data/unsafe.jpg']);
      } catch (_) {
        rejected = true;
      }
      expect(rejected).assertTrue();
      expect((await store.recover())?.operationId).assertEqual('newer');
    });

    it('treats a corrupted preference as no recoverable journal', 0, async () => {
      const storage = new MemoryRestoreJournalStorage();
      storage.value = '{not-json';
      const store = new RestoreJournalStore(storage);
      expect(await store.recover()).assertNull();
    });
  });
}
