import { common } from '@kit.AbilityKit';
import { SerialCaptureQueue } from '../background/SerialCaptureQueue';
import { ImagePipeline } from '../core/media/ImagePipeline';
import { NativeImagePipeline } from '../core/media/NativeImagePipeline';
import { PrivateFileCleanup } from '../core/system/PrivateFileCleanup';
import { HarmonySystemServices, SystemServices } from '../core/system/SystemServices';
import { AppDatabase } from '../data/database/AppDatabase';
import { CaptureKillDraftStore } from '../data/prefs/CaptureKillDraftStore';
import { CaptureSessionStore } from '../data/prefs/CaptureSessionStore';
import { PreferencesCaptureKillDraftStorage, PreferencesCaptureSessionStorage,
  PreferencesPublishJournalStorage, PreferencesRestoreJournalStorage } from '../data/prefs/PreferencesStores';
import { PublishJournalStore } from '../data/prefs/PublishJournalStore';
import { RestoreJournalStore } from '../data/prefs/RestoreJournalStore';
import { CaptureProcessor } from '../feature/capture/CaptureProcessor';
import { NasSyncService } from '../core/sync/NasSyncService';
import { CaptureWorkflow } from '../feature/capture/CaptureWorkflow';
import { StartupRecovery } from './StartupRecovery';
import { CaptureStatus } from '../domain/StateMachine';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { UiTokens } from '../shared/UiTokens';
import { CompletionNotifications } from '../core/system/CompletionNotifications';
import { AppText, tr, userFacingError } from '../shared/AppText';
import { KeyedOperationGate } from '../core/concurrency/KeyedOperationGate';
import { AsyncOnce } from '../core/concurrency/AsyncOnce';
import { ScreenStateStore } from '../shared/ScreenStateStore';
import { UiMemoryCoordinator } from '../shared/UiMemoryCoordinator';
import { cancelSystemSuspendDelay, requestSystemSuspendDelay, SuspendDelayWindow }
  from '../shared/SuspendDelayWindow';
import { StorageInspector } from '../core/system/StorageInspector';

const RUNTIME_DOMAIN = 0x0000;
const RUNTIME_TAG = 'SiteMarkRuntime';

export type RuntimeListener = () => void;

export class AppRuntime {
  static current: AppRuntime | null = null;
  private static readonly initializationOnce: AsyncOnce<AppRuntime> = new AsyncOnce<AppRuntime>();

  readonly context: common.UIAbilityContext;
  readonly database: AppDatabase;
  readonly pipeline: ImagePipeline;
  readonly services: SystemServices;
  readonly queue: SerialCaptureQueue;
  readonly suspendWindow: SuspendDelayWindow;
  readonly captureWorkflow: CaptureWorkflow;
  readonly privateFileCleanup: PrivateFileCleanup;
  readonly startupRecovery: StartupRecovery;
  readonly restoreJournal: RestoreJournalStore;
  readonly notifications: CompletionNotifications;
  readonly screenState: ScreenStateStore;
  readonly uiMemory: UiMemoryCoordinator;
  readonly captureKillDraft: CaptureKillDraftStore;
  readonly nasSync: NasSyncService;

  selectedProjectId: string = '';
  selectedCaptureId: string = '';
  rootSelectionMode: boolean = false;
  private listeners: RuntimeListener[] = [];
  private readonly republishGate: KeyedOperationGate = new KeyedOperationGate();

  private constructor(context: common.UIAbilityContext, database: AppDatabase) {
    this.context = context;
    this.database = database;
    this.pipeline = new NativeImagePipeline();
    const journals = new PublishJournalStore(new PreferencesPublishJournalStorage(context));
    this.services = new HarmonySystemServices(context, journals);
    const sessions = new CaptureSessionStore(new PreferencesCaptureSessionStorage(context));
    this.captureKillDraft = new CaptureKillDraftStore(new PreferencesCaptureKillDraftStorage(context));
    this.notifications = new CompletionNotifications(context);
    const processor = new CaptureProcessor(database, this.pipeline, this.services, context.filesDir,
      (_captureId: string, _succeeded: boolean): void => this.notifyDataChanged(), this.notifications);
    this.nasSync = new NasSyncService(database);
    // Observer pattern: the NAS queue is refreshed after every processed
    // capture. The service no-ops immediately unless sync is enabled, so
    // the capture pipeline itself stays NAS-unaware.
    this.queue = new SerialCaptureQueue((captureId: string): Promise<void> =>
      processor.process(captureId).finally(() => this.nasSync.syncNow()));
    this.suspendWindow = new SuspendDelayWindow('process captured photos', requestSystemSuspendDelay,
      cancelSystemSuspendDelay, (): boolean => this.queue.isBusy());
    this.queue.setDrainedListener((): void => this.suspendWindow.release());
    this.captureWorkflow = new CaptureWorkflow(database, this.services, sessions, this.queue);
    this.privateFileCleanup = new PrivateFileCleanup(database, context.filesDir);
    this.restoreJournal = new RestoreJournalStore(new PreferencesRestoreJournalStorage(context));
    this.screenState = new ScreenStateStore();
    this.uiMemory = new UiMemoryCoordinator();
    this.startupRecovery = new StartupRecovery(database, this.services, this.captureWorkflow,
      this.queue, this.privateFileCleanup, this.restoreJournal, context.filesDir);
  }

  static initialize(context: common.UIAbilityContext): Promise<AppRuntime> {
    if (AppRuntime.current !== null) {
      return Promise.resolve(AppRuntime.current);
    }
    return AppRuntime.initializationOnce.run((): Promise<AppRuntime> => AppRuntime.initializeFresh(context));
  }

  private static async initializeFresh(context: common.UIAbilityContext): Promise<AppRuntime> {
    if (AppRuntime.current !== null) {
      return AppRuntime.current;
    }
    StorageInspector.clearInterruptedExports(context.filesDir);
    const database = await AppDatabase.open(context);
    const runtime = new AppRuntime(context, database);
    await runtime.applyAppearance();
    await runtime.startupRecovery.run();
    // Catch-up scan + drain for the NAS queue (no-op when sync is off).
    runtime.nasSync.syncNow();
    if (AppRuntime.current === null) {
      AppRuntime.current = runtime;
    }
    return AppRuntime.current;
  }

  static require(): AppRuntime {
    if (AppRuntime.current === null) {
      throw new Error('AppRuntime is not initialized');
    }
    return AppRuntime.current;
  }

  subscribe(listener: RuntimeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unsubscribe(listener: RuntimeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  notifyDataChanged(): void {
    const snapshot = this.listeners.slice();
    for (const listener of snapshot) {
      listener();
    }
  }

  async applyAppearance(): Promise<void> {
    const settings = await this.database.settings();
    this.context.getApplicationContext().setLanguage(settings.localeCode.length === 0 ? 'default' : settings.localeCode);
    const systemLocale = this.context.resourceManager.getConfigurationSync().locale;
    AppText.apply(settings.localeCode, systemLocale);
    const systemDark = this.context.resourceManager.getConfigurationSync().colorMode === 0;
    const dark = settings.themeMode === 'dark' || (settings.themeMode === 'system' && systemDark);
    UiTokens.apply(dark, settings.appSeedColorArgb);
    try {
      const win = await window.getLastWindow(this.context);
      const contentColor = dark ? '#E7EEE9' : '#17201C';
      await win.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        navigationBarColor: '#00000000',
        statusBarContentColor: contentColor,
        navigationBarContentColor: contentColor
      });
    } catch (error) {
      hilog.error(RUNTIME_DOMAIN, RUNTIME_TAG, 'Failed to update system bar colors. Cause: %{public}s',
        JSON.stringify(error));
    }
    const mode = settings.themeMode === 'dark' ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK :
      (settings.themeMode === 'light' ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT :
        ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    this.context.getApplicationContext().setColorMode(mode);
    this.notifyDataChanged();
  }

  async clearOriginal(captureId: string): Promise<void> {
    const started = Date.now();
    try {
      await this.database.scheduleOriginalCleanup(captureId);
      await this.privateFileCleanup.reconcile();
      await this.recordDiagnosticBestEffort('original_cleanup', 'success', Date.now() - started);
      this.notifyDataChanged();
    } catch (error) {
      await this.recordDiagnosticBestEffort('original_cleanup', 'failure', Date.now() - started);
      throw new Error((error as Error).message);
    }
  }

  async deleteCapture(captureId: string): Promise<void> {
    const started = Date.now();
    try {
      await this.database.scheduleCaptureDeletion(captureId);
      await this.privateFileCleanup.reconcile();
      await this.recordDiagnosticBestEffort('capture_delete', 'success', Date.now() - started);
      this.notifyDataChanged();
    } catch (error) {
      await this.recordDiagnosticBestEffort('capture_delete', 'failure', Date.now() - started);
      throw new Error((error as Error).message);
    }
  }

  async deleteProject(projectId: string): Promise<void> {
    const started = Date.now();
    try {
      await this.database.scheduleProjectDeletion(projectId);
      await this.privateFileCleanup.reconcile();
      await this.recordDiagnosticBestEffort('project_delete', 'success', Date.now() - started);
      this.notifyDataChanged();
    } catch (error) {
      await this.recordDiagnosticBestEffort('project_delete', 'failure', Date.now() - started);
      throw new Error((error as Error).message);
    }
  }

  async republishCapture(captureId: string): Promise<void> {
    if (!this.republishGate.tryEnter(captureId)) {
      throw userFacingError(tr('正在保存到相册，请稍候', 'Saving to the gallery. Please wait.'));
    }
    try {
      const capture = await this.database.captureById(captureId);
      if (capture === null || capture.status !== CaptureStatus.READY || capture.renderedPath.length === 0) {
        throw userFacingError(tr('仅可再次保存已完成的水印照片',
          'Only completed watermarked photos can be saved again.'));
      }
      const outcome = await this.services.saveJpegToAlbum(capture.renderedPath,
        `${capture.photoNumber}.jpg`, capture.id, capture.publishedUri);
      const adopted = await this.database.adoptPublishedUriFromJournal(capture.id,
        capture.publishedUri, outcome.contentUri);
      if (!adopted) {
        throw userFacingError(tr('记录已发生变化，请重新打开后再试',
          'The record changed. Reopen it and try again.'));
      }
      try {
        await this.services.clearPublishJournal(capture.id, outcome.contentUri);
      } catch (_) {
      }
      await this.recordDiagnosticBestEffort('republish', 'success', 0);
      this.notifyDataChanged();
    } finally {
      this.republishGate.leave(captureId);
    }
  }

  async recordDiagnosticBestEffort(category: string, outcome: string, durationMs: number): Promise<void> {
    try {
      await this.database.recordDiagnostic(category, outcome, durationMs);
    } catch (_) {
    }
  }
}
