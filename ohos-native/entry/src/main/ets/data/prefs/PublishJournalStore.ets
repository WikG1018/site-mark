export interface PublishJournalEntryInit {
  captureId: string;
  contentUri: string;
  supersededUris: string[];
  recordedAt: number;
}

export class PublishJournalEntry {
  captureId: string;
  contentUri: string;
  supersededUris: string[];
  recordedAt: number;

  constructor(value: PublishJournalEntryInit) {
    this.captureId = value.captureId;
    this.contentUri = value.contentUri;
    this.supersededUris = value.supersededUris;
    this.recordedAt = value.recordedAt;
  }
}

interface JournalDocument {
  version: number;
  entries: PublishJournalEntryInit[];
}

export interface PublishJournalStorage {
  load(): Promise<string>;
  save(value: string): Promise<void>;
}

export class InMemoryPublishJournalStorage implements PublishJournalStorage {
  private value: string = '';

  load(): Promise<string> {
    return Promise.resolve(this.value);
  }

  save(value: string): Promise<void> {
    this.value = value;
    return Promise.resolve();
  }
}

function uniqueUris(values: string[], excluded: string): string[] {
  const result: string[] = [];
  for (const value of values) {
    const uri = value.trim();
    if (uri.length > 0 && uri !== excluded && result.indexOf(uri) < 0) {
      result.push(uri);
    }
  }
  return result;
}

export class PublishJournalStore {
  private readonly storage: PublishJournalStorage;
  private mutationTail: Promise<void> = Promise.resolve();

  constructor(storage: PublishJournalStorage) {
    this.storage = storage;
  }

  async record(captureId: string, contentUri: string, supersededUris: string[]): Promise<void> {
    await this.withMutation(async (): Promise<void> => {
      const entries = await this.readEntries();
      const next = entries.filter((entry: PublishJournalEntry): boolean => entry.captureId !== captureId);
      next.push(new PublishJournalEntry({
        captureId: captureId,
        contentUri: contentUri,
        supersededUris: uniqueUris(supersededUris, contentUri),
        recordedAt: Date.now()
      }));
      await this.writeEntries(next);
    });
  }

  async recover(): Promise<PublishJournalEntry[]> {
    await this.mutationTail;
    return this.readEntries();
  }

  async peek(captureId: string): Promise<PublishJournalEntry | null> {
    const entries = await this.recover();
    const matching = entries.filter((entry: PublishJournalEntry): boolean => entry.captureId === captureId);
    return matching.length === 0 ? null : matching[matching.length - 1];
  }

  async clear(captureId: string, expectedContentUri: string): Promise<boolean> {
    return this.withMutation(async (): Promise<boolean> => {
      const entries = await this.readEntries();
      const matching = entries.filter((entry: PublishJournalEntry): boolean =>
        entry.captureId === captureId && entry.contentUri === expectedContentUri);
      if (matching.length === 0) {
        return false;
      }
      const next = entries.filter((entry: PublishJournalEntry): boolean =>
        !(entry.captureId === captureId && entry.contentUri === expectedContentUri));
      await this.writeEntries(next);
      return true;
    });
  }

  private async withMutation<T>(action: () => Promise<T>): Promise<T> {
    const previous = this.mutationTail;
    let unlock: () => void = (): void => {};
    this.mutationTail = new Promise<void>((resolve: () => void): void => {
      unlock = resolve;
    });
    await previous;
    try {
      return await action();
    } finally {
      unlock();
    }
  }

  private async readEntries(): Promise<PublishJournalEntry[]> {
    const encoded = await this.storage.load();
    if (encoded.length === 0) {
      return [];
    }
    try {
      const document = JSON.parse(encoded) as JournalDocument;
      if (document.version !== 1 || !Array.isArray(document.entries)) {
        return [];
      }
      const result: PublishJournalEntry[] = [];
      for (const entry of document.entries) {
        if (typeof entry.captureId === 'string' && typeof entry.contentUri === 'string' &&
          entry.captureId.length > 0 && entry.contentUri.length > 0) {
          const superseded = Array.isArray(entry.supersededUris) ? entry.supersededUris : [];
          result.push(new PublishJournalEntry({
            captureId: entry.captureId,
            contentUri: entry.contentUri,
            supersededUris: uniqueUris(superseded, entry.contentUri),
            recordedAt: typeof entry.recordedAt === 'number' ? entry.recordedAt : 0
          }));
        }
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  private async writeEntries(entries: PublishJournalEntry[]): Promise<void> {
    const document: JournalDocument = {
      version: 1,
      entries: entries
    };
    await this.storage.save(JSON.stringify(document));
  }
}
