import { fileIo, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { AppRuntime } from '../../app/AppRuntime';
import { CaptureFilter, CapturePage, CapturePageCursor, CaptureRecord, ProjectRecord } from '../../domain/Models';
import { CaptureStatus } from '../../domain/StateMachine';
import { tr } from '../../shared/AppText';
import { safeProjectFileNameKey } from '../../domain/DomainRules';
import { ArchiveDeliveryCoordinator, ExportDeliveryOutcome } from './ExportDeliveryPolicy';
import { SystemSharePanel } from '../../core/system/SystemSharePanel';

interface ExportPhotoRecordJson {
  photo_number: string;
  watermarked_path: string;
  original_path: string | null;
  original_sha256: string;
  captured_at: string;
  work_location: string;
  work_content: string;
  photographer: string;
  address: string | null;
  coordinates: string | null;
  notes: string | null;
  latitude: number | null;
  longitude: number | null;
  accuracy_meters: number | null;
  watermark_locale_code: string | null;
}

interface ExportTemplateJson {
  name: string;
  work_location: string;
  work_content: string;
  photographer: string;
  created_at: string;
  updated_at: string;
}

interface ExportProjectJson {
  project_id: string;
  project_name: string;
  project_description: string | null;
  project_created_at: string;
  snapshot_at: string;
  omitted_processing_count: number;
  omitted_failed_count: number;
  output_zip_path: string;
  include_originals: boolean;
  project_lifecycle_status: string;
  project_is_pinned: boolean;
  watermark: ExportWatermarkJson;
  photos: ExportPhotoRecordJson[];
  templates: ExportTemplateJson[];
}

interface ExportWatermarkJson {
  position: string;
  opacity: number;
  accent_color_argb: number;
  font_scale: number;
}

interface BundleSourceJson {
  project_id: string;
  project_name: string;
  archive_path: string;
}

interface ExportBundleJson {
  output_zip_path: string;
  projects: BundleSourceJson[];
}

interface SelectionProjectJson {
  project_id: string;
  project_name: string;
  photos: ExportPhotoRecordJson[];
}

interface ExportSelectionJson {
  output_zip_path: string;
  include_originals: boolean;
  projects: SelectionProjectJson[];
}

export class BackupResult {
  path: string;
  fileName: string;
  projectCount: number;
  photoCount: number;
  omittedFailed: number;

  constructor(path: string, fileName: string, projectCount: number,
    photoCount: number, omittedFailed: number) {
    this.path = path;
    this.fileName = fileName;
    this.projectCount = projectCount;
    this.photoCount = photoCount;
    this.omittedFailed = omittedFailed;
  }
}

export class ProjectBackupService {
  private readonly runtime: AppRuntime;

  constructor(runtime: AppRuntime) {
    this.runtime = runtime;
  }

  async create(projectIds: string[], includeOriginals: boolean,
    allowSkipFailed: boolean): Promise<BackupResult> {
    if (projectIds.length === 0) {
      throw new Error(tr('请选择至少一个项目', 'Select at least one project'));
    }
    const exportsDir = `${this.runtime.context.filesDir}/exports`;
    this.ensureDirectory(exportsDir);
    const operationId = util.generateRandomUUID();
    const workDir = `${exportsDir}/work-${operationId}`;
    this.ensureDirectory(workDir);
    const sources: BundleSourceJson[] = [];
    let photoCount = 0;
    let omittedFailed = 0;
    try {
      for (const projectId of projectIds) {
        const project = await this.runtime.database.projectById(projectId);
        if (project === null) {
          throw new Error(tr('所选项目已不存在，请刷新后重试',
            'A selected project no longer exists. Refresh and try again.'));
        }
        const captures = await this.projectCaptures(projectId);
        const processing = captures.filter((capture: CaptureRecord): boolean =>
          capture.status === CaptureStatus.CAPTURED || capture.status === CaptureStatus.RENDERING ||
          capture.status === CaptureStatus.PENDING_CAMERA).length;
        const failed = captures.filter((capture: CaptureRecord): boolean =>
          capture.status === CaptureStatus.FAILED).length;
        if (processing > 0) {
          throw new Error(tr(`项目“${project.name}”有 ${processing} 张照片仍在处理中，请处理完成后再备份`,
            `Project “${project.name}” has ${processing} photo(s) still processing. Wait before backing up.`));
        }
        if (failed > 0 && !allowSkipFailed) {
          throw new Error(tr(`项目“${project.name}”有 ${failed} 条失败记录。请先重新处理，或勾选“仅备份已完成记录”`,
            `Project “${project.name}” has ${failed} failed record(s). Reprocess them or enable “Back up completed records only”.`));
        }
        const ready = captures.filter((capture: CaptureRecord): boolean =>
          capture.status === CaptureStatus.READY);
        if (includeOriginals) {
          const missing = ready.filter((capture: CaptureRecord): boolean => !capture.hasOriginal());
          if (missing.length > 0) {
            throw new Error(tr(`项目“${project.name}”有 ${missing.length} 张原图已清理，请关闭“包含私有原图”后重试`,
              `Project “${project.name}” has ${missing.length} cleared original(s). Disable “Include private originals” and try again.`));
          }
        }
        const archivePath = `${workDir}/${project.id}.zip`;
        await this.exportProject(project, ready, includeOriginals, failed, archivePath);
        sources.push({ project_id: project.id, project_name: project.name, archive_path: archivePath });
        photoCount += ready.length;
        omittedFailed += failed;
      }
      let outputPath: string;
      let fileName: string;
      const stamp = this.fileStamp(Date.now());
      if (sources.length === 1) {
        const project = await this.runtime.database.projectById(projectIds[0]);
        fileName = `SiteMark-${safeProjectFileNameKey(project?.name ?? 'project')}-${stamp}.zip`;
        outputPath = `${exportsDir}/${fileName}`;
        fileIo.moveFileSync(sources[0].archive_path, outputPath);
      } else {
        fileName = `SiteMark-Projects-${stamp}.zip`;
        outputPath = `${exportsDir}/${fileName}`;
        const request: ExportBundleJson = { output_zip_path: outputPath, projects: sources };
        await this.runtime.pipeline.exportBundle(JSON.stringify(request));
      }
      await this.runtime.recordDiagnosticBestEffort('backup', 'success', 0);
      return new BackupResult(outputPath, fileName, projectIds.length, photoCount, omittedFailed);
    } catch (error) {
      await this.runtime.recordDiagnosticBestEffort('backup', 'failure', 0);
      throw new Error((error as Error).message);
    } finally {
      this.removeDirectory(workDir);
    }
  }

  async saveAs(result: BackupResult): Promise<ExportDeliveryOutcome> {
    const delivery = new ArchiveDeliveryCoordinator(
      (): Promise<boolean> => new SystemSharePanel().show(this.runtime.context, result.path),
      async (): Promise<boolean> => {
        const documentPicker = new picker.DocumentViewPicker(this.runtime.context);
        const options = new picker.DocumentSaveOptions();
        options.newFileNames = [result.fileName];
        options.fileSuffixChoices = ['ZIP|.zip'];
        const uris = await documentPicker.save(options);
        if (uris.length === 0) {
          return false;
        }
        await fileIo.copyFile(result.path, uris[0]);
        return true;
      });
    return delivery.deliver();
  }

  async exportSelection(captureIds: string[], includeOriginals: boolean): Promise<BackupResult> {
    if (captureIds.length === 0) throw new Error(tr('请先选择照片', 'Select photos first'));
    const captures: CaptureRecord[] = [];
    for (const id of captureIds) {
      const capture = await this.runtime.database.captureById(id);
      if (capture === null || capture.status !== CaptureStatus.READY) {
        throw new Error(tr('仅可导出已完成的照片', 'Only completed photos can be exported'));
      }
      if (includeOriginals && !capture.hasOriginal()) {
        throw new Error(tr('所选照片中有原图已清理，请关闭包含原图后重试',
          'Some selected originals were cleared. Disable original inclusion and try again.'));
      }
      captures.push(capture);
    }
    const byProject = new Map<string, CaptureRecord[]>();
    for (const capture of captures) {
      const existing = byProject.get(capture.projectId) ?? [];
      existing.push(capture);
      byProject.set(capture.projectId, existing);
    }
    const projects: SelectionProjectJson[] = [];
    for (const projectId of byProject.keys()) {
      const project = await this.runtime.database.projectById(projectId);
      if (project === null) throw new Error(tr('所选照片所属项目已不存在',
        'The project for a selected photo no longer exists'));
      const photos = (byProject.get(projectId) ?? []).map((capture: CaptureRecord): ExportPhotoRecordJson => ({
        photo_number: capture.photoNumber,
        watermarked_path: capture.renderedPath,
        original_path: includeOriginals ? capture.originalPath : null,
        original_sha256: capture.originalSha256,
        captured_at: localTimestamp(capture.capturedAt),
        work_location: capture.workLocation,
        work_content: capture.workContent,
        photographer: capture.photographer,
        address: capture.address.length > 0 ? capture.address : null,
        coordinates: coordinates(capture),
        notes: capture.notes.length > 0 ? capture.notes : null,
        latitude: capture.latitude,
        longitude: capture.longitude,
        accuracy_meters: capture.accuracyMeters,
        watermark_locale_code: capture.watermarkLocaleCode
      }));
      projects.push({ project_id: project.id, project_name: project.name, photos: photos });
    }
    const exportsDir = `${this.runtime.context.filesDir}/exports`;
    this.ensureDirectory(exportsDir);
    const fileName = `SiteMark-Selection-${this.fileStamp(Date.now())}.zip`;
    const outputPath = `${exportsDir}/${fileName}`;
    const request: ExportSelectionJson = {
      output_zip_path: outputPath, include_originals: includeOriginals, projects: projects
    };
    await this.runtime.pipeline.exportSelection(JSON.stringify(request));
    return new BackupResult(outputPath, fileName, projects.length, captures.length, 0);
  }

  private async exportProject(project: ProjectRecord, captures: CaptureRecord[],
    includeOriginals: boolean, omittedFailed: number, outputPath: string): Promise<void> {
    const templates = await this.runtime.database.listTemplates(project.id);
    const photos = captures.map((capture: CaptureRecord): ExportPhotoRecordJson => ({
      photo_number: capture.photoNumber,
      watermarked_path: capture.renderedPath,
      original_path: includeOriginals ? capture.originalPath : null,
      original_sha256: capture.originalSha256,
      captured_at: localTimestamp(capture.capturedAt),
      work_location: capture.workLocation,
      work_content: capture.workContent,
      photographer: capture.photographer,
      address: capture.address.length > 0 ? capture.address : null,
      coordinates: coordinates(capture),
      notes: capture.notes.length > 0 ? capture.notes : null,
      latitude: capture.latitude,
      longitude: capture.longitude,
      accuracy_meters: capture.accuracyMeters,
      watermark_locale_code: capture.watermarkLocaleCode
    }));
    const request: ExportProjectJson = {
      project_id: project.id,
      project_name: project.name,
      project_description: project.description.length > 0 ? project.description : null,
      project_created_at: localTimestamp(project.createdAt),
      snapshot_at: localTimestamp(Date.now()),
      omitted_processing_count: 0,
      omitted_failed_count: omittedFailed,
      output_zip_path: outputPath,
      include_originals: includeOriginals,
      project_lifecycle_status: project.lifecycleStatus,
      project_is_pinned: project.isPinned,
      watermark: {
        position: project.watermarkPosition,
        opacity: project.watermarkOpacity,
        accent_color_argb: project.watermarkAccentColorArgb,
        font_scale: project.watermarkFontScale
      },
      photos: photos,
      templates: templates.map((template): ExportTemplateJson => ({
        name: template.name,
        work_location: template.workLocation,
        work_content: template.workContent,
        photographer: template.photographer,
        created_at: localTimestamp(template.createdAt),
        updated_at: localTimestamp(template.updatedAt)
      }))
    };
    await this.runtime.pipeline.exportProject(JSON.stringify(request));
  }

  private async projectCaptures(projectId: string): Promise<CaptureRecord[]> {
    const filter: CaptureFilter = { projectId: projectId, year: 0, month: 0, day: 0, searchText: '' };
    const result: CaptureRecord[] = [];
    let cursor: CapturePageCursor | null = null;
    do {
      const page: CapturePage = await this.runtime.database.listCaptures(filter, cursor, 100);
      for (const row of page.rows) {
        result.push(row);
      }
      cursor = page.nextCursor;
    } while (cursor !== null);
    return result;
  }

  private ensureDirectory(path: string): void {
    if (!fileIo.accessSync(path)) {
      fileIo.mkdirSync(path, true);
    }
  }

  private removeDirectory(path: string): void {
    if (!fileIo.accessSync(path)) return;
    for (const name of fileIo.listFileSync(path)) {
      const child = `${path}/${name}`;
      try {
        const stat = fileIo.statSync(child);
        if (stat.isDirectory()) this.removeDirectory(child); else fileIo.unlinkSync(child);
      } catch (_) {
      }
    }
    try { fileIo.rmdirSync(path); } catch (_) {}
  }

  private fileStamp(value: number): string {
    const date = new Date(value);
    return `${date.getFullYear()}${two(date.getMonth() + 1)}${two(date.getDate())}-${
      two(date.getHours())}${two(date.getMinutes())}`;
  }
}

function coordinates(capture: CaptureRecord): string | null {
  if (capture.latitude === null || capture.longitude === null) return null;
  return `${capture.latitude.toFixed(6)}, ${capture.longitude.toFixed(6)}`;
}

function localTimestamp(value: number): string {
  const date = new Date(value);
  const offset = -date.getTimezoneOffset();
  const sign = offset >= 0 ? '+' : '-';
  const absolute = Math.abs(offset);
  return `${date.getFullYear()}-${two(date.getMonth() + 1)}-${two(date.getDate())} ` +
    `${two(date.getHours())}:${two(date.getMinutes())}:${two(date.getSeconds())} ` +
    `${sign}${two(Math.floor(absolute / 60))}:${two(absolute % 60)}`;
}

function two(value: number): string { return value.toString().padStart(2, '0'); }
