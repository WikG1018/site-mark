import { fileIo } from '@kit.CoreFileKit';
import { AppDatabase } from '../../data/database/AppDatabase';

export class PrivateFileCleanup {
  private readonly database: AppDatabase;
  private readonly filesRoot: string;

  constructor(database: AppDatabase, filesRoot: string) {
    this.database = database;
    this.filesRoot = filesRoot.endsWith('/') ? filesRoot : `${filesRoot}/`;
  }

  async reconcile(): Promise<void> {
    const tasks = await this.database.pendingFileCleanups();
    for (const task of tasks) {
      try {
        if (!this.isOwnedPath(task.path)) {
          await this.database.failFileCleanup(task.path, 1);
          continue;
        }
        if (fileIo.accessSync(task.path)) {
          fileIo.unlinkSync(task.path);
        }
        await this.database.completeFileCleanup(task.path);
      } catch (_) {
        await this.database.failFileCleanup(task.path);
      }
    }
  }

  private isOwnedPath(path: string): boolean {
    return path.startsWith(this.filesRoot) && !path.includes('/../') && !path.endsWith('/..');
  }
}

