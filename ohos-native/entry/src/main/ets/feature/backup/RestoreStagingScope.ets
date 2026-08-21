export type RestoreStagingAction<T> = () => Promise<T>;
export type RestoreStagingCleanup = () => void;

export class RestoreStagingScope {
  async run<T>(action: RestoreStagingAction<T>, cleanup: RestoreStagingCleanup): Promise<T> {
    try {
      return await action();
    } finally {
      cleanup();
    }
  }
}
