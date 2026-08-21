import { fileIo } from '@kit.CoreFileKit';
import { RestoreJournalStore } from '../../data/prefs/RestoreJournalStore';
import { AppDatabase } from '../../data/database/AppDatabase';

export interface RestorePathReferenceLookup {
  privatePathReferenced(path: string): Promise<boolean>;
}

export interface RestoreFileAccess {
  exists(path: string): boolean;
  delete(path: string): void;
}

export class DatabaseRestorePathReferenceLookup implements RestorePathReferenceLookup {
  private readonly database: AppDatabase;
  constructor(database: AppDatabase) { this.database = database; }
  privatePathReferenced(path: string): Promise<boolean> {
    return this.database.privatePathReferenced(path);
  }
}

export class HarmonyRestoreFileAccess implements RestoreFileAccess {
  exists(path: string): boolean { return fileIo.accessSync(path); }
  delete(path: string): void { fileIo.unlinkSync(path); }
}

export class RestoreFileCleanup {
  private readonly journal: RestoreJournalStore;
  private readonly references: RestorePathReferenceLookup;
  private readonly files: RestoreFileAccess;
  private readonly ownedRoot: string;

  constructor(journal: RestoreJournalStore, references: RestorePathReferenceLookup,
    files: RestoreFileAccess, ownedRoot: string) {
    this.journal = journal;
    this.references = references;
    this.files = files;
    this.ownedRoot = ownedRoot.endsWith('/') ? ownedRoot : `${ownedRoot}/`;
  }

  async run(expectedOperationId: string = ''): Promise<boolean> {
    const pending = await this.journal.recover();
    if (pending === null) return true;
    if (expectedOperationId.length > 0 && pending.operationId !== expectedOperationId) return false;
    let complete = true;
    for (const path of pending.paths) {
      if (!path.startsWith(this.ownedRoot)) continue;
      try {
        if (await this.references.privatePathReferenced(path)) continue;
        if (this.files.exists(path)) this.files.delete(path);
      } catch (_) {
        complete = false;
      }
    }
    if (!complete) return false;
    return this.journal.clear(pending.operationId);
  }
}

export class RestoreAttemptGate {
  private readonly cleanup: RestoreFileCleanup;
  private readonly journal: RestoreJournalStore;

  constructor(cleanup: RestoreFileCleanup, journal: RestoreJournalStore) {
    this.cleanup = cleanup;
    this.journal = journal;
  }

  async begin(operationId: string): Promise<void> {
    try {
      if (await this.cleanup.run()) {
        await this.journal.begin(operationId);
        return;
      }
    } catch (_) {
      // The caller maps this stable boundary error to a bilingual retry message.
    }
    throw new Error('restore_cleanup_pending');
  }
}
