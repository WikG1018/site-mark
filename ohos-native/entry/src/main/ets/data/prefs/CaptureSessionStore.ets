export interface PendingCaptureSessionInit {
  captureId: string;
  projectId: string;
  projectName: string;
  targetPath: string;
  workLocation: string;
  workContent: string;
  photographer: string;
  notes: string;
  startedAt: number;
  watermarkLocaleCode: string;
}

export class PendingCaptureSession {
  captureId: string;
  projectId: string;
  projectName: string;
  targetPath: string;
  workLocation: string;
  workContent: string;
  photographer: string;
  notes: string;
  startedAt: number;
  watermarkLocaleCode: string;

  constructor(value: PendingCaptureSessionInit) {
    this.captureId = value.captureId;
    this.projectId = value.projectId;
    this.projectName = value.projectName;
    this.targetPath = value.targetPath;
    this.workLocation = value.workLocation;
    this.workContent = value.workContent;
    this.photographer = value.photographer;
    this.notes = value.notes;
    this.startedAt = value.startedAt;
    this.watermarkLocaleCode = value.watermarkLocaleCode;
  }
}

export interface CaptureSessionStorage {
  load(): Promise<string>;
  save(value: string): Promise<void>;
}

export class InMemoryCaptureSessionStorage implements CaptureSessionStorage {
  private value: string = '';

  load(): Promise<string> {
    return Promise.resolve(this.value);
  }

  save(value: string): Promise<void> {
    this.value = value;
    return Promise.resolve();
  }
}

export class CaptureSessionStore {
  private readonly storage: CaptureSessionStorage;

  constructor(storage: CaptureSessionStorage) {
    this.storage = storage;
  }

  save(session: PendingCaptureSession): Promise<void> {
    return this.storage.save(JSON.stringify(session));
  }

  async recover(): Promise<PendingCaptureSession | null> {
    const encoded = await this.storage.load();
    if (encoded.length === 0) {
      return null;
    }
    try {
      const value = JSON.parse(encoded) as PendingCaptureSessionInit;
      if (value.captureId.length === 0 || value.projectId.length === 0 || value.targetPath.length === 0) {
        return null;
      }
      return new PendingCaptureSession(value);
    } catch (_) {
      return null;
    }
  }

  async clear(expectedCaptureId: string): Promise<void> {
    const current = await this.recover();
    if (current !== null && current.captureId === expectedCaptureId) {
      await this.storage.save('');
    }
  }
}
