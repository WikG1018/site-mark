import { CaptureKillDraftSnapshot } from '../../data/prefs/CaptureKillDraftStore';
import { inspectCaptureFields, normalizeCaptureTemplateName, unicodeScalarLength } from '../../domain/DomainRules';
import { CaptureStatus, ProjectLifecycleStatus } from '../../domain/StateMachine';
import { tr } from '../../shared/AppText';

export class CaptureFormMetrics {
  static readonly TOUCH_TARGET: number = 44;
  static readonly LOCATION_MAX_LENGTH: number = 160;
  static readonly WORK_MAX_LENGTH: number = 240;
  static readonly PHOTOGRAPHER_MAX_LENGTH: number = 80;
  static readonly NOTES_MAX_LENGTH: number = 0;
  static readonly FOCUSED_SUGGESTION_COUNT: number = 3;
  static readonly ALL_SUGGESTION_COUNT: number = 20;
  static readonly TEMPLATE_ACTION_MIN_HEIGHT: number = 44;
  static readonly TEMPLATE_ACTION_MAX_LINES: number = 2;
}

export class CaptureFormCopy {
  captureBackAccessibility: string;
  editorBackAccessibility: string;
  requiredError: string;
  invalidError: string;
  locationTooLongError: string;
  workTooLongError: string;
  photographerTooLongError: string;
  notesInvalidError: string;

  constructor(english: boolean) {
    this.captureBackAccessibility = english ? 'Back to project details' : '返回项目详情';
    this.editorBackAccessibility = english ?
      'Cancel editing and return to record details' : '取消编辑并返回记录详情';
    this.requiredError = english ? 'This field is required' : '此项为必填项';
    this.invalidError = english ? 'Remove unsupported control characters' : '请移除不支持的控制字符';
    this.locationTooLongError = english ? 'Use no more than 160 characters' : '最多输入 160 个字符';
    this.workTooLongError = english ? 'Use no more than 240 characters' : '最多输入 240 个字符';
    this.photographerTooLongError = english ? 'Use no more than 80 characters' : '最多输入 80 个字符';
    this.notesInvalidError = english ? 'Remove unsupported control characters from notes' :
      '请移除备注中不支持的控制字符';
  }
}

export function captureFormCopy(english: boolean): CaptureFormCopy {
  return new CaptureFormCopy(english);
}

function fieldError(value: string, maximum: number, tooLong: string): string {
  if (value.length === 0) return tr('此项为必填项', 'This field is required');
  if (value.indexOf('\u0000') >= 0) {
    return tr('请移除不支持的控制字符', 'Remove unsupported control characters');
  }
  if (unicodeScalarLength(value) > maximum) return tooLong;
  return '';
}

export class CaptureDraftValidation {
  location: string;
  work: string;
  photographer: string;
  notes: string;
  locationError: string;
  workError: string;
  photographerError: string;
  notesError: string;
  valid: boolean;

  constructor(location: string, work: string, photographer: string, notes: string,
    locationError: string, workError: string, photographerError: string, notesError: string) {
    this.location = location;
    this.work = work;
    this.photographer = photographer;
    this.notes = notes;
    this.locationError = locationError;
    this.workError = workError;
    this.photographerError = photographerError;
    this.notesError = notesError;
    this.valid = locationError.length === 0 && workError.length === 0 &&
      photographerError.length === 0 && notesError.length === 0;
  }
}

export function validateCaptureDraft(location: string, work: string, photographer: string,
  notes: string): CaptureDraftValidation {
  const fields = inspectCaptureFields(location, work, photographer, notes);
  const normalizedLocation = fields.location;
  const normalizedWork = fields.work;
  const normalizedPhotographer = fields.photographer;
  const normalizedNotes = fields.notes;
  return new CaptureDraftValidation(
    normalizedLocation,
    normalizedWork,
    normalizedPhotographer,
    normalizedNotes,
    fieldError(normalizedLocation, CaptureFormMetrics.LOCATION_MAX_LENGTH,
      tr('最多输入 160 个字符', 'Use no more than 160 characters')),
    fieldError(normalizedWork, CaptureFormMetrics.WORK_MAX_LENGTH,
      tr('最多输入 240 个字符', 'Use no more than 240 characters')),
    fieldError(normalizedPhotographer, CaptureFormMetrics.PHOTOGRAPHER_MAX_LENGTH,
      tr('最多输入 80 个字符', 'Use no more than 80 characters')),
    normalizedNotes.indexOf('\u0000') >= 0 ?
      tr('请移除备注中不支持的控制字符', 'Remove unsupported control characters from notes') : ''
  );
}

export class TemplateDraftValidation {
  name: string;
  location: string;
  work: string;
  photographer: string;
  nameError: string;
  locationError: string;
  workError: string;
  photographerError: string;
  valid: boolean;

  constructor(name: string, location: string, work: string, photographer: string,
    nameError: string, locationError: string, workError: string, photographerError: string) {
    this.name = name;
    this.location = location;
    this.work = work;
    this.photographer = photographer;
    this.nameError = nameError;
    this.locationError = locationError;
    this.workError = workError;
    this.photographerError = photographerError;
    this.valid = nameError.length === 0 && locationError.length === 0 && workError.length === 0 &&
      photographerError.length === 0;
  }
}

export class TemplateNameValidation {
  value: string;
  error: string;
  valid: boolean;

  constructor(value: string, error: string) {
    this.value = value;
    this.error = error;
    this.valid = error.length === 0;
  }
}

export function validateTemplateName(name: string): TemplateNameValidation {
  const normalized = normalizeCaptureTemplateName(name);
  return new TemplateNameValidation(normalized,
    fieldError(normalized, CaptureFormMetrics.PHOTOGRAPHER_MAX_LENGTH,
      tr('模板名称最多输入 80 个字符', 'Use no more than 80 characters for the template name')));
}

export function validateTemplateDraft(name: string, location: string, work: string,
  photographer: string): TemplateDraftValidation {
  const nameValidation = validateTemplateName(name);
  const normalizedName = nameValidation.value;
  const capture = validateCaptureDraft(location, work, photographer, '');
  return new TemplateDraftValidation(normalizedName, capture.location, capture.work, capture.photographer,
    nameValidation.error,
    capture.locationError, capture.workError, capture.photographerError);
}

export function filterSuggestions(values: string[], query: string, limit: number): string[] {
  const normalizedQuery = query.trim().toLowerCase();
  const bounded = Math.max(0, Math.min(CaptureFormMetrics.ALL_SUGGESTION_COUNT, Math.floor(limit)));
  const result: string[] = [];
  for (const value of values) {
    if (normalizedQuery.length > 0 && !value.toLowerCase().includes(normalizedQuery)) continue;
    result.push(value);
    if (result.length >= bounded) break;
  }
  return result;
}

export class CaptureDraftSnapshot {
  location: string;
  work: string;
  photographer: string;
  notes: string;

  constructor(location: string, work: string, photographer: string, notes: string) {
    this.location = location;
    this.work = work;
    this.photographer = photographer;
    this.notes = notes;
  }
}

export class CaptureDraftApplication {
  value: CaptureDraftSnapshot;
  previous: CaptureDraftSnapshot;

  constructor(value: CaptureDraftSnapshot, previous: CaptureDraftSnapshot) {
    this.value = value;
    this.previous = previous;
  }
}

export function applyDraftSuggestion(current: CaptureDraftSnapshot, field: string,
  value: string): CaptureDraftApplication {
  const next = new CaptureDraftSnapshot(current.location, current.work, current.photographer, current.notes);
  if (field === 'location') next.location = value;
  if (field === 'work') next.work = value;
  if (field === 'photographer') next.photographer = value;
  return new CaptureDraftApplication(next, current);
}

export function applyCaptureOutcome(current: CaptureDraftSnapshot, captured: boolean): CaptureDraftSnapshot {
  return new CaptureDraftSnapshot(current.location, current.work, current.photographer,
    captured ? '' : current.notes);
}

export function restoreRequiredFields(current: CaptureDraftSnapshot,
  previous: CaptureDraftSnapshot): CaptureDraftSnapshot {
  return new CaptureDraftSnapshot(previous.location, previous.work, previous.photographer, current.notes);
}

export class CaptureUndoCoordinator {
  private snapshot: CaptureDraftSnapshot | null = null;

  arm(snapshot: CaptureDraftSnapshot): void { this.snapshot = snapshot; }
  available(): boolean { return this.snapshot !== null; }
  requiredFieldEdited(): void { this.snapshot = null; }
  consume(current: CaptureDraftSnapshot): CaptureDraftSnapshot | null {
    if (this.snapshot === null) return null;
    const restored = restoreRequiredFields(current, this.snapshot);
    this.snapshot = null;
    return restored;
  }
}

export class SingleFlightRequestCoordinator {
  private generation: number = 0;
  private busy: boolean = false;

  begin(): number {
    if (this.busy) return 0;
    this.busy = true;
    this.generation += 1;
    return this.generation;
  }

  accept(generation: number): boolean { return this.busy && generation === this.generation; }
  finish(generation: number): void { if (this.accept(generation)) this.busy = false; }
  invalidate(): void { this.generation += 1; this.busy = false; }
}

export class CaptureFormLifecycle {
  private active: boolean = false;
  private generation: number = 0;
  private saving: boolean = false;
  private transient: string = '';

  activate(): number {
    this.active = true;
    this.generation += 1;
    return this.generation;
  }

  deactivate(): void {
    this.active = false;
    this.saving = false;
    this.transient = '';
    this.generation += 1;
  }

  accept(generation: number): boolean {
    return this.active && generation === this.generation;
  }

  snapshot(): number {
    return this.generation;
  }

  openTransient(value: string): void {
    this.transient = value;
  }

  closeTransient(): void {
    this.transient = '';
  }

  consumeBack(): boolean {
    if (this.transient.length === 0) return false;
    this.transient = '';
    return true;
  }

  beginSave(): boolean {
    if (!this.active || this.saving) return false;
    this.saving = true;
    return true;
  }

  finishSave(generation: number): void {
    if (this.accept(generation)) this.saving = false;
  }
}

export function canEditCapture(projectStatus: ProjectLifecycleStatus, captureStatus: CaptureStatus,
  hasOriginal: boolean): boolean {
  return projectStatus === ProjectLifecycleStatus.ACTIVE && hasOriginal &&
    (captureStatus === CaptureStatus.READY || captureStatus === CaptureStatus.FAILED);
}

export interface RecentCaptureSeed {
  workLocation: string;
  workContent: string;
  photographer: string;
}

export class FormSeed {
  readonly workLocation: string;
  readonly workContent: string;
  readonly photographer: string;
  readonly notes: string;
  readonly fromKillDraft: boolean;

  constructor(workLocation: string, workContent: string, photographer: string, notes: string,
    fromKillDraft: boolean) {
    this.workLocation = workLocation;
    this.workContent = workContent;
    this.photographer = photographer;
    this.notes = notes;
    this.fromKillDraft = fromKillDraft;
  }
}

export function resolveFormSeed(draft: CaptureKillDraftSnapshot | null,
  recent: RecentCaptureSeed | null): FormSeed {
  if (draft !== null && (draft.workLocation.length > 0 || draft.workContent.length > 0 ||
    draft.photographer.length > 0 || draft.notes.length > 0)) {
    return new FormSeed(draft.workLocation, draft.workContent, draft.photographer, draft.notes, true);
  }
  if (recent !== null) {
    return new FormSeed(recent.workLocation, recent.workContent, recent.photographer, '', false);
  }
  return new FormSeed('', '', '', '', false);
}
