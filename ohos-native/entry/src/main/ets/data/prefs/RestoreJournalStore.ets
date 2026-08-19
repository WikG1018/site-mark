export interface RestoreJournalStorage {
  load(): Promise<string>;
  save(value: string): Promise<void>;
}
export class RestoreJournalEntry {
  operationId: string;
  paths: string[];

  constructor(operationId: string, paths: string[]) {
    this.operationId = operationId;
    this.paths = paths;
  }
}

interface RestoreJournalDocument {
  operation_id: string;
  paths: string[];
}

export class RestoreJournalStore {
  private readonly storage: RestoreJournalStorage;

  constructor(storage: RestoreJournalStorage) {
    this.storage = storage;
  }

  async begin(operationId: string): Promise<void> {
    await this.write(new RestoreJournalEntry(operationId, []));
  }

  async addPaths(operationId: string, paths: string[]): Promise<void> {
    const current = await this.recover();
    if (current === null || current.operationId !== operationId) {
      throw new Error('restore_journal_ownership_lost');
    }
    const next = current.paths.slice();
    for (const path of paths) {
      if (path.length > 0 && next.indexOf(path) < 0) next.push(path);
    }
    await this.write(new RestoreJournalEntry(operationId, next));
  }

  async recover(): Promise<RestoreJournalEntry | null> {
    const encoded = await this.storage.load();
    if (encoded.length === 0) return null;
    try {
      const value = JSON.parse(encoded) as RestoreJournalDocument;
      if (value.operation_id.length === 0 || !Array.isArray(value.paths)) return null;
      return new RestoreJournalEntry(value.operation_id, value.paths);
    } catch (_) {
      return null;
    }
  }

  async clear(operationId: string): Promise<boolean> {
    const current = await this.recover();
    if (current === null) return true;
    if (current.operationId !== operationId) return false;
    await this.storage.save('');
    return true;
  }

  private write(value: RestoreJournalEntry): Promise<void> {
    const document: RestoreJournalDocument = { operation_id: value.operationId, paths: value.paths };
    return this.storage.save(JSON.stringify(document));
  }
}
