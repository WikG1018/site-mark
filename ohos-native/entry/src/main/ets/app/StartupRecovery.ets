import { SerialCaptureQueue } from '../background/SerialCaptureQueue';
import { AppDatabase } from '../data/database/AppDatabase';
import { CaptureStatus } from '../domain/StateMachine';
import { CaptureWorkflow } from '../feature/capture/CaptureWorkflow';
import { MediaCleanup } from '../core/system/MediaCleanup';
import { SystemServices } from '../core/system/SystemServices';
import { PrivateFileCleanup } from '../core/system/PrivateFileCleanup';
import { RestoreJournalStore } from '../data/prefs/RestoreJournalStore';
import { PublishJournalEntry } from '../data/prefs/PublishJournalStore';
import { DatabaseRestorePathReferenceLookup, HarmonyRestoreFileAccess,
  RestoreFileCleanup } from '../feature/backup/RestoreFileCleanup';

export class StartupRecovery {
  private readonly database: AppDatabase;
  private readonly services: SystemServices;
  private readonly workflow: CaptureWorkflow;
  private readonly queue: SerialCaptureQueue;
  private readonly cleanup: MediaCleanup;
  private readonly privateFiles: PrivateFileCleanup;
  private readonly restoreJournal: RestoreJournalStore;
  private readonly filesDir: string;

  constructor(database: AppDatabase, services: SystemServices, workflow: CaptureWorkflow,
    queue: SerialCaptureQueue, cleanup: MediaCleanup, privateFiles: PrivateFileCleanup,
    restoreJournal: RestoreJournalStore, filesDir: string) {
    this.database = database;
    this.services = services;
    this.workflow = workflow;
    this.queue = queue;
    this.cleanup = cleanup;
    this.privateFiles = privateFiles;
    this.restoreJournal = restoreJournal;
    this.filesDir = filesDir.endsWith('/') ? filesDir : `${filesDir}/`;
  }

  async run(): Promise<void> {
    await this.recoverRestoreFiles();
    try {
      await this.workflow.recoverInterrupted();
    } catch (_) {
    }
    await this.recoverPublishJournals();
    try {
      const pending = await this.database.pendingCaptureIds();
      for (const captureId of pending) {
        this.queue.enqueue(captureId);
      }
    } catch (_) {
    }
    try {
      await this.cleanup.reconcile();
    } catch (_) {
    }
    try {
      await this.privateFiles.reconcile();
    } catch (_) {
    }
  }

  private async recoverRestoreFiles(): Promise<void> {
    try {
      await new RestoreFileCleanup(this.restoreJournal,
        new DatabaseRestorePathReferenceLookup(this.database),
        new HarmonyRestoreFileAccess(), this.filesDir).run();
    } catch (_) {
      // A later startup will retry; never block capture recovery.
    }
  }

  private async recoverPublishJournals(): Promise<void> {
    let entries: PublishJournalEntry[] = [];
    try {
      entries = await this.services.recoverPublishJournals();
    } catch (_) {
      // A preferences failure must not block queue and file reconciliation.
      return;
    }
    for (const entry of entries) {
      try {
        const capture = await this.database.captureById(entry.captureId);
        if (capture === null || capture.status === CaptureStatus.FAILED) {
          const allUris = [entry.contentUri].concat(entry.supersededUris);
          await this.database.queueMediaCleanups(entry.captureId, allUris);
          await this.services.clearPublishJournal(entry.captureId, entry.contentUri);
          continue;
        }
        if (capture.status === CaptureStatus.READY) {
          if (capture.publishedUri === entry.contentUri) {
            await this.database.queueMediaCleanups(entry.captureId, entry.supersededUris);
            await this.services.clearPublishJournal(entry.captureId, entry.contentUri);
          } else {
            const adopted = await this.database.adoptPublishedUriFromJournal(entry.captureId,
              capture.publishedUri, entry.contentUri, entry.supersededUris);
            if (adopted) {
              await this.services.clearPublishJournal(entry.captureId, entry.contentUri);
            }
          }
        }
        // Captured/rendering journals stay durable. Reprocessing merges their
        // complete stale URI set into the next journal before DB commit.
      } catch (_) {
        // One malformed/stale entry must not block the rest of startup repair.
      }
    }
  }
}
