import { util } from '@kit.ArkTS';
import { SerialCaptureQueue } from '../../background/SerialCaptureQueue';
import { CaptureWorkflowDatabase } from '../../data/database/AppDatabase';
import { CaptureSessionStore, PendingCaptureSession } from '../../data/prefs/CaptureSessionStore';
import { CaptureDraft } from '../../domain/Models';
import { CameraOutcomeCode, LocationOutcomeCode, LocationSnapshot,
  SystemServices } from '../../core/system/SystemServices';
import { tr, userFacingError } from '../../shared/AppText';
import { validateCaptureDraft } from './CaptureFormPolicy';

export interface CaptureFormInput {
  projectId: string;
  projectName: string;
  workLocation: string;
  workContent: string;
  photographer: string;
  notes: string;
  localeCode: string;
}

export class CaptureWorkflowResult {
  captured: boolean;
  captureId: string;
  debugInjected: boolean;
  message: string;

  constructor(captured: boolean, captureId: string = '', debugInjected: boolean = false,
    message: string = '') {
    this.captured = captured;
    this.captureId = captureId;
    this.debugInjected = debugInjected;
    this.message = message;
  }
}

export class CaptureWorkflow {
  private readonly database: CaptureWorkflowDatabase;
  private readonly services: SystemServices;
  private readonly sessions: CaptureSessionStore;
  private readonly queue: SerialCaptureQueue;

  constructor(database: CaptureWorkflowDatabase, services: SystemServices, sessions: CaptureSessionStore,
    queue: SerialCaptureQueue) {
    this.database = database;
    this.services = services;
    this.sessions = sessions;
    this.queue = queue;
  }

  async capture(input: CaptureFormInput): Promise<CaptureWorkflowResult> {
    this.validate(input);
    const project = await this.database.projectById(input.projectId);
    if (project === null || project.lifecycleStatus !== 'active') {
      throw userFacingError(tr('该项目当前只读，无法继续拍摄',
        'This project is read-only, so capture is unavailable'));
    }
    const hasLocationPermission = await this.services.getLocationPermissionState();
    const locationPromise = hasLocationPermission ?
      this.services.requestCurrentLocation(input.localeCode) :
      Promise.resolve(new LocationSnapshot(LocationOutcomeCode.PERMISSION_DENIED));
    const captureId = util.generateRandomUUID();
    const targetPath = await this.services.createCameraTarget(captureId);
    const session = new PendingCaptureSession({
      captureId: captureId,
      projectId: input.projectId,
      projectName: input.projectName,
      targetPath: targetPath,
      workLocation: input.workLocation.trim(),
      workContent: input.workContent.trim(),
      photographer: input.photographer.trim(),
      notes: input.notes.trim(),
      startedAt: Date.now(),
      watermarkLocaleCode: input.localeCode === 'en' ? 'en' : 'zh'
    });
    await this.sessions.save(session);
    const camera = await this.services.launchCamera(targetPath);
    if (camera.code !== CameraOutcomeCode.CAPTURED) {
      await this.services.finishCameraCapture(targetPath, false);
      await this.sessions.clear(captureId);
      return new CaptureWorkflowResult(false, '', false,
        camera.code === CameraOutcomeCode.CANCELLED ? tr('已取消拍摄', 'Capture cancelled') :
        tr('无法打开系统相机，请稍后重试', 'The system camera could not be opened. Try again later.'));
    }
    const location = await locationPromise;
    const draft = this.draftFromSession(session, location);
    await this.database.createCaptured(draft);
    await this.sessions.clear(captureId);
    await this.services.finishCameraCapture(targetPath, true);
    this.queue.enqueue(captureId);
    return new CaptureWorkflowResult(true, captureId, camera.debugInjected, camera.message);
  }

  async recoverInterrupted(): Promise<string> {
    const session = await this.sessions.recover();
    if (session === null) {
      return '';
    }
    const camera = await this.services.recoverCameraCapture(session.targetPath);
    if (camera.code !== CameraOutcomeCode.CAPTURED) {
      await this.services.finishCameraCapture(session.targetPath, false);
      await this.sessions.clear(session.captureId);
      return '';
    }
    if (await this.database.captureById(session.captureId) === null) {
      const unavailable = new LocationSnapshot(LocationOutcomeCode.UNAVAILABLE);
      await this.database.createCaptured(this.draftFromSession(session, unavailable));
    }
    await this.sessions.clear(session.captureId);
    this.queue.enqueue(session.captureId);
    return session.captureId;
  }

  private draftFromSession(session: PendingCaptureSession, location: LocationSnapshot): CaptureDraft {
    return {
      id: session.captureId,
      projectId: session.projectId,
      projectName: session.projectName,
      workLocation: session.workLocation,
      workContent: session.workContent,
      photographer: session.photographer,
      notes: session.notes,
      originalPath: session.targetPath,
      capturedAt: Date.now(),
      latitude: location.latitude,
      longitude: location.longitude,
      accuracyMeters: location.accuracyMeters,
      address: location.address,
      locationOutcome: location.outcome,
      watermarkLocaleCode: session.watermarkLocaleCode
    };
  }

  private validate(input: CaptureFormInput): void {
    const validation = validateCaptureDraft(input.workLocation, input.workContent, input.photographer, input.notes);
    if (!validation.valid) throw new Error('capture_form_invalid');
  }
}
