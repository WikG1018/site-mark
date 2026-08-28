import { AppDatabase } from '../../data/database/AppDatabase';
import { CaptureRecord, ProjectRecord } from '../../domain/Models';
import { CaptureStatus } from '../../domain/StateMachine';
import { ImagePipeline, RenderPhotoRequest } from '../../core/media/ImagePipeline';
import { SystemServices } from '../../core/system/SystemServices';
import { CompletionNotifications } from '../../core/system/CompletionNotifications';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { tr } from '../../shared/AppText';
import { needsExifLookup, resolveFinalCaptureLocation } from '../../shared/ExifLocationPolicy';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'SiteMarkCapture';

export type ProcessingListener = (captureId: string, succeeded: boolean) => void;

function pad2(value: number): string {
  return value.toString().padStart(2, '0');
}

function localTimestamp(epochMillis: number): string {
  const value = new Date(epochMillis);
  const offsetMinutes = -value.getTimezoneOffset();
  const sign = offsetMinutes >= 0 ? '+' : '-';
  const absolute = Math.abs(offsetMinutes);
  return `${value.getFullYear()}-${pad2(value.getMonth() + 1)}-${pad2(value.getDate())} ` +
    `${pad2(value.getHours())}:${pad2(value.getMinutes())}:${pad2(value.getSeconds())} ` +
    `${sign}${pad2(Math.floor(absolute / 60))}:${pad2(absolute % 60)}`;
}

function coordinatesOf(capture: CaptureRecord): string {
  if (capture.latitude === null || capture.longitude === null) {
    return '';
  }
  const accuracy = capture.accuracyMeters === null ? '' : ` · ±${Math.round(capture.accuracyMeters)}m`;
  return `${capture.latitude.toFixed(6)}, ${capture.longitude.toFixed(6)}${accuracy}`;
}

export class CaptureProcessor {
  private readonly database: AppDatabase;
  private readonly pipeline: ImagePipeline;
  private readonly services: SystemServices;
  private readonly filesDir: string;
  private readonly listener: ProcessingListener;
  private readonly notifications: CompletionNotifications;

  constructor(database: AppDatabase, pipeline: ImagePipeline, services: SystemServices,
    filesDir: string, listener: ProcessingListener, notifications: CompletionNotifications) {
    this.database = database;
    this.pipeline = pipeline;
    this.services = services;
    this.filesDir = filesDir;
    this.listener = listener;
    this.notifications = notifications;
  }

  async process(captureId: string): Promise<void> {
    let succeeded = false;
    let stage = 'load';
    try {
      let capture = await this.database.captureById(captureId);
      if (capture === null || capture.status === CaptureStatus.READY) {
        succeeded = capture !== null;
        return;
      }
      if (capture.status === CaptureStatus.PENDING_CAMERA) {
        throw new Error('pending_camera_not_processable');
      }
      if (capture.processingAttempts >= 3 && capture.status !== CaptureStatus.FAILED) {
        await this.database.markFailed(captureId, tr('处理失败次数过多，请检查原图后重试',
          'Processing failed too many times. Check the original and try again.'));
        return;
      }
      stage = 'mark_rendering';
      hilog.info(LOG_DOMAIN, LOG_TAG, 'capture stage %{public}s', stage);
      await this.database.markRendering(captureId);
      stage = 'reload';
      hilog.info(LOG_DOMAIN, LOG_TAG, 'capture stage %{public}s', stage);
      capture = await this.database.captureById(captureId);
      if (capture === null) {
        return;
      }
      const project = await this.database.projectById(capture.projectId);
      if (project === null) {
        throw new Error('project_missing');
      }
      stage = 'inspect_original';
      hilog.info(LOG_DOMAIN, LOG_TAG, 'capture stage %{public}s', stage);
      const original = await this.services.inspectImage(capture.originalPath);
      if (!original.exists || original.sizeBytes < 1) {
        throw new Error('原图不存在或为空');
      }
      const originalSha = await this.pipeline.sha256(capture.originalPath);
      stage = 'prefer_exif_location';
      hilog.info(LOG_DOMAIN, LOG_TAG, 'capture stage %{public}s', stage);
      capture = await this.preferExifLocation(capture);
      const outputPath = `${this.filesDir}/renders/${capture.id}.jpg`;
      const request = this.renderRequest(capture, project, outputPath);
      stage = 'render';
      hilog.info(LOG_DOMAIN, LOG_TAG, 'capture stage %{public}s', stage);
      await this.pipeline.render(request);
      stage = 'publish';
      hilog.info(LOG_DOMAIN, LOG_TAG, 'capture stage %{public}s', stage);
      const published = await this.services.publishJpegInBackground(outputPath, `${capture.photoNumber}.jpg`,
        capture.id, capture.publishedUri);
      stage = 'commit_ready';
      hilog.info(LOG_DOMAIN, LOG_TAG, 'capture stage %{public}s', stage);
      await this.database.markReady(capture.id, outputPath, originalSha, published.contentUri);
      // Older builds could be killed after the system album accepted a JPEG
      // but before the RDB commit. The new non-interactive background path
      // does not create another journal, so adopt any durable predecessor now
      // instead of waiting for a second process restart.
      try {
        const entries = await this.services.recoverPublishJournals();
        for (const entry of entries) {
          if (entry.captureId !== capture.id) {
            continue;
          }
          const adopted = await this.database.adoptPublishedUriFromJournal(capture.id,
            published.contentUri, entry.contentUri);
          if (adopted) {
            await this.services.clearPublishJournal(capture.id, entry.contentUri);
          }
          break;
        }
      } catch (_) {
        // Startup recovery will retry the same captureId-scoped CAS later.
      }
      succeeded = true;
      hilog.info(LOG_DOMAIN, LOG_TAG, 'capture processing completed');
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'capture processing failed at %{public}s', stage);
      const current = await this.database.captureById(captureId);
      if (current !== null && current.status !== CaptureStatus.READY && current.status !== CaptureStatus.FAILED) {
        try {
          await this.database.markFailed(captureId, this.userMessage(error as Error));
        } catch (_) {
          // Without this trail a persistently failing database would leave the
          // record stuck in captured/rendering with zero visibility until
          // startup recovery retries the same give-up path.
          hilog.error(LOG_DOMAIN, LOG_TAG,
            'markFailed failed for %{public}s after stage %{public}s; startup recovery will retry',
            captureId, stage);
        }
      }
    } finally {
      this.listener(captureId, succeeded);
      try {
        if ((await this.database.settings()).completionNotificationsEnabled) {
          await this.notifications.publish(captureId, succeeded);
        }
      } catch (_) {
      }
    }
  }

  private async preferExifLocation(capture: CaptureRecord): Promise<CaptureRecord> {
    if (!needsExifLookup(capture.locationResolution)) {
      return capture;
    }
    const reading = await this.services.readExifGps(capture.originalPath);
    const final = resolveFinalCaptureLocation(reading, capture.latitude, capture.longitude,
      capture.accuracyMeters, capture.locationResolution);
    if (final.resolution === capture.locationResolution) {
      return capture;
    }
    await this.database.updateCaptureLocation(capture.id, final);
    const updated = await this.database.captureById(capture.id);
    return updated ?? capture;
  }

  private renderRequest(capture: CaptureRecord, project: ProjectRecord, outputPath: string): RenderPhotoRequest {
    return {
      sourcePath: capture.originalPath,
      outputPath: outputPath,
      projectName: project.name,
      workLocation: capture.workLocation,
      workContent: capture.workContent,
      photographer: capture.photographer,
      photoNumber: capture.photoNumber,
      capturedAt: localTimestamp(capture.capturedAt),
      address: capture.address,
      coordinates: coordinatesOf(capture),
      notes: capture.notes,
      position: project.watermarkPosition,
      opacity: project.watermarkOpacity,
      accentColorArgb: project.watermarkAccentColorArgb,
      fontScale: project.watermarkFontScale,
      localeCode: capture.watermarkLocaleCode === 'en' ? 'en' : 'zh'
    };
  }

  private userMessage(error: Error): string {
    const message = error.message;
    if (message.indexOf('album_save_cancelled') >= 0) {
      return tr('水印图已生成，但未保存到系统相册；点击重试可再次保存',
        'The watermark was generated but not saved to the gallery. Retry to save it again.');
    }
    if (message.indexOf('invalid_data:') >= 0) {
      return tr('照片数据不符合处理要求，请检查原图后重试',
        'The photo data cannot be processed. Check the original and try again.');
    }
    if (message.indexOf('原图不存在') >= 0) {
      return tr('原图不存在或为空，请重新拍摄', 'The original is missing or empty. Capture it again.');
    }
    return tr('照片处理失败，请稍后重试', 'Photo processing failed. Try again later.');
  }
}
