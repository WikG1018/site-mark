import { MediaCleanupTask } from '../../data/database/AppDatabase';

export interface MediaCleanupDatabase {
  pendingMediaCleanups(): Promise<MediaCleanupTask[]>;
  isPublishedUriReferenced(uri: string): Promise<boolean>;
  completeMediaCleanup(uri: string): Promise<void>;
  failMediaCleanup(uri: string): Promise<void>;
}

export interface MediaDeleteService {
  deletePublishedImage(uri: string): Promise<boolean>;
}

export class MediaCleanup {
  private readonly database: MediaCleanupDatabase;
  private readonly services: MediaDeleteService;

  constructor(database: MediaCleanupDatabase, services: MediaDeleteService) {
    this.database = database;
    this.services = services;
  }

  async reconcile(): Promise<void> {
    const tasks = await this.database.pendingMediaCleanups();
    for (const task of tasks) {
      try {
        if (await this.database.isPublishedUriReferenced(task.publishedUri)) {
          // Keep the durable task while any record still owns this URI. A
          // shared legacy URI can become unreferenced after a later republish;
          // dropping the task here would leave that gallery row orphaned.
          continue;
        }
        if (await this.services.deletePublishedImage(task.publishedUri)) {
          await this.database.completeMediaCleanup(task.publishedUri);
        } else {
          await this.database.failMediaCleanup(task.publishedUri);
        }
      } catch (_) {
        await this.database.failMediaCleanup(task.publishedUri);
      }
    }
  }
}
