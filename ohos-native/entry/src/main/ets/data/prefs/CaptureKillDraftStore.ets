export interface CaptureKillDraftDocument {
  projectId: string;
  workLocation: string;
  workContent: string;
  photographer: string;
  notes: string;
}

export class CaptureKillDraftSnapshot {
  readonly projectId: string;
  readonly workLocation: string;
  readonly workContent: string;
  readonly photographer: string;
  readonly notes: string;

  constructor(value: CaptureKillDraftDocument) {
    this.projectId = value.projectId;
    this.workLocation = value.workLocation;
    this.workContent = value.workContent;
    this.photographer = value.photographer;
    this.notes = value.notes;
  }
}

export interface CaptureKillDraftStorage {
  load(): Promise<string>;
  save(value: string): Promise<void>;
}

export class InMemoryCaptureKillDraftStorage implements CaptureKillDraftStorage {
  private value: string = '';

  load(): Promise<string> {
    return Promise.resolve(this.value);
  }

  save(value: string): Promise<void> {
    this.value = value;
    return Promise.resolve();
  }
}

export class CaptureKillDraftStore {
  private readonly storage: CaptureKillDraftStorage;

  constructor(storage: CaptureKillDraftStorage) {
    this.storage = storage;
  }

  save(snapshot: CaptureKillDraftSnapshot): Promise<void> {
    return this.storage.save(JSON.stringify(snapshot));
  }

  async recover(projectId: string): Promise<CaptureKillDraftSnapshot | null> {
    const encoded = await this.storage.load();
    if (encoded.length === 0) {
      return null;
    }
    try {
      const value = JSON.parse(encoded) as CaptureKillDraftDocument;
      if (typeof value.projectId !== 'string' || value.projectId !== projectId) {
        return null;
      }
      return new CaptureKillDraftSnapshot({
        projectId: value.projectId,
        workLocation: typeof value.workLocation === 'string' ? value.workLocation : '',
        workContent: typeof value.workContent === 'string' ? value.workContent : '',
        photographer: typeof value.photographer === 'string' ? value.photographer : '',
        notes: typeof value.notes === 'string' ? value.notes : ''
      });
    } catch (_) {
      return null;
    }
  }

  async clear(projectId: string): Promise<void> {
    const current = await this.recover(projectId);
    if (current !== null) {
      await this.storage.save('');
    }
  }
}
