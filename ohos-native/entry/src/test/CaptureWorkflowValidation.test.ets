import { describe, expect, it } from '@ohos/hypium';
import { SerialCaptureQueue } from '../main/ets/background/SerialCaptureQueue';
import { CameraOutcome, CameraOutcomeCode, ImageInspection, LocationOutcomeCode, LocationSnapshot,
  PublishJpegOutcome, SystemServices } from '../main/ets/core/system/SystemServices';
import { CaptureSessionStore, InMemoryCaptureSessionStorage } from
  '../main/ets/data/prefs/CaptureSessionStore';
import { CaptureWorkflowDatabase } from '../main/ets/data/database/AppDatabase';
import { PublishJournalEntry } from '../main/ets/data/prefs/PublishJournalStore';
import { CaptureDraft, CaptureRecord, ProjectRecord } from '../main/ets/domain/Models';
import { CaptureWorkflow } from '../main/ets/feature/capture/CaptureWorkflow';

class RejectingWorkflowDatabase implements CaptureWorkflowDatabase {
  projectReadCount: number = 0;

  projectById(_id: string): Promise<ProjectRecord | null> {
    this.projectReadCount += 1;
    return Promise.resolve(null);
  }

  createCaptured(_draft: CaptureDraft): Promise<CaptureRecord> {
    return Promise.reject(new Error('unexpected_create'));
  }

  captureById(_id: string): Promise<CaptureRecord | null> {
    return Promise.resolve(null);
  }
}

class CountingCameraServices implements SystemServices {
  launchCount: number = 0;
  createCameraTarget(_captureId: string): Promise<string> { return Promise.resolve('/capture.jpg'); }
  launchCamera(_targetPath: string): Promise<CameraOutcome> {
    this.launchCount += 1;
    return Promise.resolve(new CameraOutcome(CameraOutcomeCode.CANCELLED));
  }
  recoverCameraCapture(_targetPath: string): Promise<CameraOutcome> {
    return Promise.resolve(new CameraOutcome(CameraOutcomeCode.CANCELLED));
  }
  finishCameraCapture(_targetPath: string, _keep: boolean): Promise<void> { return Promise.resolve(); }
  getLocationPermissionState(): Promise<boolean> { return Promise.resolve(false); }
  requestLocationPermission(): Promise<boolean> { return Promise.resolve(false); }
  requestCurrentLocation(_localeCode: string): Promise<LocationSnapshot> {
    return Promise.resolve(new LocationSnapshot(LocationOutcomeCode.UNAVAILABLE));
  }
  publishJpegInBackground(_sourcePath: string, _displayName: string, _captureId: string,
    _publishedUri: string): Promise<PublishJpegOutcome> {
    return Promise.resolve(new PublishJpegOutcome('', [], false));
  }
  saveJpegToAlbum(_sourcePath: string, _displayName: string, _captureId: string,
    _publishedUri: string): Promise<PublishJpegOutcome> {
    return Promise.resolve(new PublishJpegOutcome('', [], false));
  }
  recoverPublishJournals(): Promise<PublishJournalEntry[]> { return Promise.resolve([]); }
  clearPublishJournal(_captureId: string, _expectedContentUri: string): Promise<boolean> {
    return Promise.resolve(true);
  }
  deletePublishedImage(_uri: string): Promise<boolean> { return Promise.resolve(true); }
  inspectImage(_path: string): Promise<ImageInspection> { return Promise.resolve(new ImageInspection(false)); }
  openApplicationSettings(): Promise<void> { return Promise.resolve(); }
  openRepository(): Promise<void> { return Promise.resolve(); }
}

export default function captureWorkflowValidationTest(): void {
  describe('Capture workflow validation', () => {
    it('rejects an overlong Unicode field before database access or camera launch', 0, async () => {
      const database = new RejectingWorkflowDatabase();
      const services = new CountingCameraServices();
      const workflow = new CaptureWorkflow(database, services,
        new CaptureSessionStore(new InMemoryCaptureSessionStorage()),
        new SerialCaptureQueue(async (_captureId: string): Promise<void> => {}));
      let rejected = false;
      try {
        await workflow.capture({ projectId: 'p', projectName: 'P', workLocation: '😀'.repeat(161),
          workContent: '巡检', photographer: '王工', notes: '', localeCode: 'zh' });
      } catch (_) {
        rejected = true;
      }
      expect(rejected).assertTrue();
      expect(database.projectReadCount).assertEqual(0);
      expect(services.launchCount).assertEqual(0);
    });
  });
}
