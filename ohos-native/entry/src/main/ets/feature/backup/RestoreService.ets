import { fileIo, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { AppRuntime } from '../../app/AppRuntime';
import { captureTemplateNameKey, inspectCaptureFields, normalizeCaptureTemplateName,
  unicodeScalarLength, validateTemplateField, CAPTURE_TEMPLATE_NAME_MAX_LENGTH } from '../../domain/DomainRules';
import { RestoredCaptureInput, RestoredProjectInput,
  RestoredTemplateInput } from '../../domain/RestoreModels';
import { ProjectLifecycleStatus } from '../../domain/StateMachine';
import { tr } from '../../shared/AppText';
import { DatabaseRestorePathReferenceLookup, HarmonyRestoreFileAccess,
  RestoreAttemptGate, RestoreFileCleanup } from './RestoreFileCleanup';

interface ArchiveWatermarkPreview {
  position: string;
  opacity: number;
  accent_color_argb: number;
  font_scale: number;
}

interface ArchivePhotoPreview {
  photo_number: string;
  has_original: boolean;
  original_sha256: string;
  captured_at: string;
  work_location: string;
  work_content: string;
  photographer: string;
  address: string | null;
  notes: string | null;
  latitude: number | null;
  longitude: number | null;
  accuracy_meters: number | null;
  watermark_locale_code: string | null;
}

interface ArchiveTemplatePreview {
  name: string;
  work_location: string;
  work_content: string;
  photographer: string;
  created_at: string;
  updated_at: string;
}

interface ProjectArchivePreview {
  schema_version: number;
  project_name: string;
  project_description: string | null;
  project_created_at: string | null;
  project_lifecycle_status: string;
  project_is_pinned: boolean;
  watermark: ArchiveWatermarkPreview | null;
  photos: ArchivePhotoPreview[];
  templates: ArchiveTemplatePreview[];
  omitted_failed_count: number;
}

interface BundleProjectPreview {
  project_id: string;
  project_name: string;
  archive_path: string;
  archive_sha256: string;
}

interface ProjectBundlePreview {
  schema_version: number;
  projects: BundleProjectPreview[];
}

interface ExtractBundleRequest {
  zip_path: string;
  archive_path: string;
  output_path: string;
}

interface ExtractPhotoRequest {
  zip_path: string;
  photo_number: string;
  rendered_destination: string;
  original_destination: string | null;
}

class RestoreSource {
  path: string;
  preview: ProjectArchivePreview;

  constructor(path: string, preview: ProjectArchivePreview) {
    this.path = path;
    this.preview = preview;
  }
}

export class RestoreResult {
  projectCount: number;
  photoCount: number;
  renamedCount: number;
  projectNames: string[];

  constructor(projectCount: number, photoCount: number, renamedCount: number, projectNames: string[]) {
    this.projectCount = projectCount;
    this.photoCount = photoCount;
    this.renamedCount = renamedCount;
    this.projectNames = projectNames;
  }
}

export class ProjectRestoreService {
  private readonly runtime: AppRuntime;

  constructor(runtime: AppRuntime) {
    this.runtime = runtime;
  }

  async chooseAndRestore(): Promise<RestoreResult | null> {
    const documentPicker = new picker.DocumentViewPicker(this.runtime.context);
    const options = new picker.DocumentSelectOptions();
    options.fileSuffixFilters = ['ZIP|.zip'];
    options.maxSelectNumber = 1;
    const uris = await documentPicker.select(options);
    if (uris.length === 0) return null;
    const operationId = util.generateRandomUUID();
    const staging = `${this.runtime.context.filesDir}/restore/${operationId}`;
    this.ensureDirectory(staging);
    const sourcePath = `${staging}/selected.zip`;
    await fileIo.copyFile(uris[0], sourcePath);
    return this.restoreFromLocal(sourcePath, operationId, staging);
  }

  private async restoreFromLocal(sourcePath: string, operationId: string,
    staging: string): Promise<RestoreResult> {
    let committed = false;
    try {
      const cleanup = new RestoreFileCleanup(this.runtime.restoreJournal,
        new DatabaseRestorePathReferenceLookup(this.runtime.database),
        new HarmonyRestoreFileAccess(), this.runtime.context.filesDir);
      await new RestoreAttemptGate(cleanup, this.runtime.restoreJournal).begin(operationId);
      const sources = await this.expandSources(sourcePath, staging);
      this.preflightSources(sources);
      const settings = await this.runtime.database.settings();
      const plans: RestoredProjectInput[] = [];
      const reservedNames: string[] = [];
      let photoCount = 0;
      let renamedCount = 0;
      for (const source of sources) {
        const preview = source.preview;
        const restoredName = await this.uniqueProjectName(preview.project_name, reservedNames);
        reservedNames.push(restoredName);
        if (restoredName !== preview.project_name) renamedCount += 1;
        const projectId = util.generateRandomUUID();
        const captures: RestoredCaptureInput[] = [];
        for (const photo of preview.photos) {
          const captureId = util.generateRandomUUID();
          const renderedPath = `${this.runtime.context.filesDir}/renders/${captureId}.jpg`;
          const originalPath = photo.has_original ?
            `${this.runtime.context.filesDir}/originals/${captureId}.jpg` : '';
          const trackedPaths = originalPath.length > 0 ? [renderedPath, originalPath] : [renderedPath];
          await this.runtime.restoreJournal.addPaths(operationId, trackedPaths);
          const request: ExtractPhotoRequest = {
            zip_path: source.path,
            photo_number: photo.photo_number,
            rendered_destination: renderedPath,
            original_destination: originalPath.length > 0 ? originalPath : null
          };
          await this.runtime.pipeline.extractArchivePhoto(JSON.stringify(request));
          captures.push(new RestoredCaptureInput(captureId, photo.photo_number, photo.work_location,
            photo.work_content, photo.photographer, photo.notes ?? '', originalPath, renderedPath,
            photo.original_sha256, parseTimestamp(photo.captured_at), photo.latitude, photo.longitude,
            photo.accuracy_meters, photo.address ?? '', photo.watermark_locale_code ?? 'zh',
            !photo.has_original));
          photoCount += 1;
        }
        const templates = preview.templates.map((template: ArchiveTemplatePreview): RestoredTemplateInput =>
          new RestoredTemplateInput(util.generateRandomUUID(), template.name,
            captureTemplateNameKey(template.name), template.work_location, template.work_content,
            template.photographer, parseTimestamp(template.created_at), parseTimestamp(template.updated_at)));
        const watermark = preview.watermark;
        plans.push(new RestoredProjectInput(projectId, restoredName, preview.project_description ?? '',
          lifecycleOf(preview.project_lifecycle_status), preview.project_is_pinned,
          watermark?.position ?? settings.defaultWatermarkPosition,
          watermark?.opacity ?? settings.defaultWatermarkOpacity,
          watermark?.accent_color_argb ?? settings.defaultWatermarkAccentColorArgb,
          watermark?.font_scale ?? settings.defaultWatermarkFontScale,
          preview.project_created_at === null ? Date.now() : parseTimestamp(preview.project_created_at),
          captures, templates));
      }
      await this.runtime.database.restoreProjects(plans);
      committed = true;
      try { await this.runtime.restoreJournal.clear(operationId); } catch (_) {}
      await this.runtime.recordDiagnosticBestEffort('restore', 'success', 0);
      this.runtime.notifyDataChanged();
      return new RestoreResult(plans.length, photoCount, renamedCount,
        plans.map((project: RestoredProjectInput): string => project.name));
    } catch (error) {
      await this.runtime.recordDiagnosticBestEffort('restore', 'failure', 0);
      if (!committed) await this.rollbackFiles(operationId);
      const message = (error as Error).message;
      if (message.includes('selection archive')) {
        throw new Error(tr('所选 ZIP 是普通照片分享包，不能用于恢复',
          'The selected ZIP is a photo-sharing package and cannot be restored'));
      }
      if (message.includes('invalid_data:')) {
        throw new Error(tr('备份已损坏、校验不一致或不是有效的 SiteMark 项目备份',
          'The backup is damaged, failed validation, or is not a valid SiteMark project backup'));
      }
      if (message.includes('restore_capture_fields_invalid:')) {
        const record = message.substring(message.indexOf(':') + 1);
        throw new Error(tr(`备份中的记录“${record}”含空白、超长或不支持的字段，请使用新版应用修正后重新备份`,
          `Record “${record}” in the backup contains blank, overlong, or unsupported fields. Fix it in a current app and back up again.`));
      }
      if (message.includes('restore_template_fields_invalid:')) {
        const template = message.substring(message.indexOf(':') + 1);
        throw new Error(tr(`备份中的模板“${template}”含空白、超长或不支持的字段，请修正后重新备份`,
          `Template “${template}” in the backup contains blank, overlong, or unsupported fields. Fix it and back up again.`));
      }
      if (message.includes('restore_template_duplicate:')) {
        const template = message.substring(message.indexOf(':') + 1);
        throw new Error(tr(`备份中的模板“${template}”名称重复，请在原设备改名后重新备份`,
          `Template “${template}” is duplicated in the backup. Rename it on the source device and back up again.`));
      }
      if (message.includes('restore_preview_invalid:')) {
        const field = message.substring(message.indexOf(':') + 1);
        throw new Error(tr(`备份字段“${field}”无效，尚未解压任何照片，请修正源备份后重试`,
          `Backup field “${field}” is invalid. No photos were extracted. Fix the source backup and try again.`));
      }
      if (message.includes('restore_cleanup_pending') || message.includes('restore_journal_pending')) {
        throw new Error(tr('上次恢复仍在清理，请稍后重试',
          'The previous restore is still being cleaned up. Try again shortly.'));
      }
      throw new Error(message.length > 0 ? message : tr('恢复失败，请重新选择备份',
        'Restore failed. Choose the backup again.'));
    } finally {
      this.removeDirectory(staging);
    }
  }

  private async expandSources(sourcePath: string, staging: string): Promise<RestoreSource[]> {
    let bundle: ProjectBundlePreview | null = null;
    try {
      bundle = JSON.parse(await this.runtime.pipeline.readBundle(sourcePath)) as ProjectBundlePreview;
    } catch (_) {
      const preview = JSON.parse(await this.runtime.pipeline.readProjectArchive(sourcePath)) as ProjectArchivePreview;
      return [new RestoreSource(sourcePath, preview)];
    }
    const sources: RestoreSource[] = [];
    for (let index = 0; index < bundle.projects.length; index++) {
      const project = bundle.projects[index];
      const path = `${staging}/project-${index}.zip`;
      const request: ExtractBundleRequest = {
        zip_path: sourcePath, archive_path: project.archive_path, output_path: path
      };
      await this.runtime.pipeline.extractBundleEntry(JSON.stringify(request));
      const preview = JSON.parse(await this.runtime.pipeline.readProjectArchive(path)) as ProjectArchivePreview;
      sources.push(new RestoreSource(path, preview));
    }
    return sources;
  }

  private async uniqueProjectName(source: string, reserved: string[]): Promise<string> {
    if (reserved.indexOf(source) < 0 && await this.runtime.database.projectNameAvailable(source)) return source;
    const base = source.length > 110 ? source.substring(0, 110) : source;
    for (let sequence = 1; sequence < 1000; sequence++) {
      const suffix = sequence === 1 ? '（恢复）' : `（恢复 ${sequence}）`;
      const candidate = `${base.substring(0, Math.max(1, 120 - suffix.length))}${suffix}`;
      if (reserved.indexOf(candidate) < 0 && await this.runtime.database.projectNameAvailable(candidate)) {
        return candidate;
      }
    }
    throw new Error(tr('恢复项目名称与现有项目冲突，请先重命名现有项目',
      'A restored project name conflicts with an existing project. Rename the existing project first.'));
  }

  private preflightSources(sources: RestoreSource[]): void {
    if (sources.length === 0) throw new Error('restore_preview_invalid:no_projects');
    for (const source of sources) {
      const preview = source.preview;
      if (!Number.isFinite(preview.schema_version) || preview.schema_version < 1 ||
        preview.schema_version > 5 || typeof preview.project_is_pinned !== 'boolean' ||
        !Number.isFinite(preview.omitted_failed_count) || preview.omitted_failed_count < 0) {
        throw new Error('restore_preview_invalid:project_metadata');
      }
      const projectName = this.requiredText(preview.project_name, 'project_name', 120)
        .replace(/\s+/g, ' ');
      preview.project_name = projectName;
      this.optionalText(preview.project_description, 'project_description');
      if (preview.project_created_at !== null) this.validTimestamp(preview.project_created_at,
        `project_created_at:${projectName}`);
      if (preview.project_lifecycle_status !== 'active' && preview.project_lifecycle_status !== 'completed' &&
        preview.project_lifecycle_status !== 'archived') {
        throw new Error(`restore_preview_invalid:project_lifecycle:${projectName}`);
      }
      if (!Array.isArray(preview.photos) || !Array.isArray(preview.templates)) {
        throw new Error(`restore_preview_invalid:project_lists:${projectName}`);
      }
      if (preview.watermark !== null) {
        this.requiredText(preview.watermark.position, `watermark_position:${projectName}`, 40);
        if ((preview.watermark.position !== 'bottomLeft' && preview.watermark.position !== 'bottomRight') ||
          !Number.isFinite(preview.watermark.opacity) || preview.watermark.opacity < 0.35 ||
          preview.watermark.opacity > 1 || !Number.isFinite(preview.watermark.font_scale) ||
          preview.watermark.font_scale < 0.75 || preview.watermark.font_scale > 1.6 ||
          !Number.isFinite(preview.watermark.accent_color_argb)) {
          throw new Error(`restore_preview_invalid:watermark:${projectName}`);
        }
      }
      for (const photo of preview.photos) {
        const number = this.requiredText(photo.photo_number, 'photo_number', 255);
        if (typeof photo.has_original !== 'boolean') {
          throw new Error(`restore_preview_invalid:has_original:${number}`);
        }
        const location = this.requiredText(photo.work_location, `work_location:${number}`, 160);
        const work = this.requiredText(photo.work_content, `work_content:${number}`, 240);
        const photographer = this.requiredText(photo.photographer, `photographer:${number}`, 80);
        this.optionalText(photo.notes, `notes:${number}`);
        const fields = inspectCaptureFields(location, work, photographer, photo.notes ?? '');
        if (!fields.valid) throw new Error(`restore_capture_fields_invalid:${number}`);
        this.requiredText(photo.original_sha256, `original_sha256:${number}`, 128);
        this.optionalText(photo.address, `address:${number}`);
        this.optionalText(photo.watermark_locale_code, `watermark_locale:${number}`);
        this.validTimestamp(photo.captured_at, `captured_at:${number}`);
        for (const coordinate of [photo.latitude, photo.longitude, photo.accuracy_meters]) {
          if (coordinate !== null && !Number.isFinite(coordinate)) {
            throw new Error(`restore_preview_invalid:location:${number}`);
          }
        }
      }
      const templateKeys: string[] = [];
      for (const template of preview.templates) {
        const name = normalizeCaptureTemplateName(this.requiredText(template.name, 'template_name', 80));
        const location = this.requiredText(template.work_location, `template_location:${name}`, 160);
        const work = this.requiredText(template.work_content, `template_work:${name}`, 240);
        const photographer = this.requiredText(template.photographer, `template_photographer:${name}`, 80);
        const fields = inspectCaptureFields(location, work, photographer, '');
        if (!validateTemplateField(name, CAPTURE_TEMPLATE_NAME_MAX_LENGTH) || !fields.valid) {
          throw new Error(`restore_template_fields_invalid:${template.name}`);
        }
        const key = captureTemplateNameKey(name);
        if (templateKeys.indexOf(key) >= 0) throw new Error(`restore_template_duplicate:${name}`);
        templateKeys.push(key);
        template.name = name;
        this.validTimestamp(template.created_at, `template_created_at:${name}`);
        this.validTimestamp(template.updated_at, `template_updated_at:${name}`);
      }
    }
  }

  private requiredText(value: string, field: string, maximum: number): string {
    if (typeof value !== 'string') throw new Error(`restore_preview_invalid:${field}`);
    const normalized = value.trim();
    if (normalized.length === 0 || normalized.indexOf('\u0000') >= 0 ||
      unicodeScalarLength(normalized) > maximum) throw new Error(`restore_preview_invalid:${field}`);
    return normalized;
  }

  private optionalText(value: string | null, field: string): void {
    if (value !== null && (typeof value !== 'string' || value.indexOf('\u0000') >= 0)) {
      throw new Error(`restore_preview_invalid:${field}`);
    }
  }

  private validTimestamp(value: string, field: string): void {
    if (typeof value !== 'string' || !Number.isFinite(Date.parse(value.length === 26 ?
      `${value.substring(0, 10)}T${value.substring(11, 19)}${value.substring(20)}` : value))) {
      throw new Error(`restore_preview_invalid:${field}`);
    }
  }

  private async rollbackFiles(operationId: string): Promise<void> {
    try {
      await new RestoreFileCleanup(this.runtime.restoreJournal,
        new DatabaseRestorePathReferenceLookup(this.runtime.database),
        new HarmonyRestoreFileAccess(), this.runtime.context.filesDir).run(operationId);
    } catch (_) {}
  }

  private ensureDirectory(path: string): void {
    if (!fileIo.accessSync(path)) fileIo.mkdirSync(path, true);
  }

  private removeDirectory(path: string): void {
    if (!fileIo.accessSync(path)) return;
    let names: string[] = [];
    try { names = fileIo.listFileSync(path); } catch (_) { return; }
    for (const name of names) {
      const child = `${path}/${name}`;
      try {
        const stat = fileIo.statSync(child);
        if (stat.isDirectory()) this.removeDirectory(child); else fileIo.unlinkSync(child);
      } catch (_) {}
    }
    try { fileIo.rmdirSync(path); } catch (_) {}
  }
}

function lifecycleOf(value: string): ProjectLifecycleStatus {
  if (value === 'completed') return ProjectLifecycleStatus.COMPLETED;
  if (value === 'archived') return ProjectLifecycleStatus.ARCHIVED;
  return ProjectLifecycleStatus.ACTIVE;
}

function parseTimestamp(value: string): number {
  const normalized = value.length === 26 ? `${value.substring(0, 10)}T${value.substring(11, 19)}${
    value.substring(20)}` : value;
  const parsed = Date.parse(normalized);
  return Number.isFinite(parsed) ? parsed : Date.now();
}
