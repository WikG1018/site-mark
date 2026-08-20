import { describe, expect, it } from '@ohos/hypium';
import { RestoreJournalStorage, RestoreJournalStore } from '../main/ets/data/prefs/RestoreJournalStore';
import { RestoreAttemptGate, RestoreFileAccess, RestoreFileCleanup, RestorePathReferenceLookup } from
  '../main/ets/feature/backup/RestoreFileCleanup';

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

class ControlledRestoreFiles implements RestoreFileAccess {
  paths: string[] = [];
  failedPath: string = '';
  deleted: string[] = [];

  exists(path: string): boolean { return this.paths.indexOf(path) >= 0; }
  delete(path: string): void {
    if (path === this.failedPath) throw new Error('controlled_delete_failure');
    this.deleted.push(path);
    const index = this.paths.indexOf(path);
    if (index >= 0) this.paths.splice(index, 1);
  }
}

class ControlledRestoreReferences implements RestorePathReferenceLookup {
  referenced: string[] = [];
  privatePathReferenced(path: string): Promise<boolean> {
    return Promise.resolve(this.referenced.indexOf(path) >= 0);
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

    it('refuses to overwrite an unfinished restore journal', 0, async () => {
      const store = new RestoreJournalStore(new MemoryRestoreJournalStorage());
      await store.begin('older');
      let rejected = false;
      try {
        await store.begin('newer');
      } catch (_) {
        rejected = true;
      }
      expect(rejected).assertTrue();
      expect((await store.recover())?.operationId).assertEqual('older');
    });

    it('treats a corrupted preference as no recoverable journal', 0, async () => {
      const storage = new MemoryRestoreJournalStorage();
      storage.value = '{not-json';
      const store = new RestoreJournalStore(storage);
      expect(await store.recover()).assertNull();
    });

    it('retains failed cleanup journal and safely converges on the next startup', 0, async () => {
      const store = new RestoreJournalStore(new MemoryRestoreJournalStorage());
      await store.begin('restore-2');
      await store.addPaths('restore-2', ['/private/a.jpg', '/private/b.jpg', '/private/committed.jpg']);
      const files = new ControlledRestoreFiles();
      files.paths = ['/private/a.jpg', '/private/b.jpg', '/private/committed.jpg'];
      files.failedPath = '/private/b.jpg';
      const references = new ControlledRestoreReferences();
      references.referenced = ['/private/committed.jpg'];
      const cleanup = new RestoreFileCleanup(store, references, files, '/private/');
      expect(await cleanup.run('restore-2')).assertFalse();
      expect((await store.recover())?.operationId).assertEqual('restore-2');
      expect(files.deleted.join(',')).assertEqual('/private/a.jpg');
      files.failedPath = '';
      expect(await cleanup.run('restore-2')).assertTrue();
      expect(await store.recover()).assertNull();
      expect(files.deleted.indexOf('/private/committed.jpg')).assertEqual(-1);
    });

    it('blocks a second restore until the previous cleanup converges', 0, async () => {
      const store = new RestoreJournalStore(new MemoryRestoreJournalStorage());
      await store.begin('older');
      await store.addPaths('older', ['/private/failed.jpg']);
      const files = new ControlledRestoreFiles();
      files.paths = ['/private/failed.jpg'];
      files.failedPath = '/private/failed.jpg';
      const cleanup = new RestoreFileCleanup(store, new ControlledRestoreReferences(), files, '/private/');
      const gate = new RestoreAttemptGate(cleanup, store);
      let rejected = false;
      try {
        await gate.begin('newer');
      } catch (_) {
        rejected = true;
      }
      expect(rejected).assertTrue();
      expect((await store.recover())?.operationId).assertEqual('older');
      files.failedPath = '';
      await gate.begin('newer');
      expect((await store.recover())?.operationId).assertEqual('newer');
    });
  });
}
