export interface ConsentStorage {
  read(): Promise<boolean>;
  write(value: boolean): Promise<void>;
}

export class PrivacyConsentStore {
  private readonly storage: ConsentStorage;

  constructor(storage: ConsentStorage) {
    this.storage = storage;
  }

  isAccepted(): Promise<boolean> {
    return this.storage.read();
  }

  accept(): Promise<void> {
    return this.storage.write(true);
  }
}

export class InMemoryConsentStorage implements ConsentStorage {
  private accepted: boolean = false;

  read(): Promise<boolean> {
    return Promise.resolve(this.accepted);
  }

  write(value: boolean): Promise<void> {
    this.accepted = value;
    return Promise.resolve();
  }
}
