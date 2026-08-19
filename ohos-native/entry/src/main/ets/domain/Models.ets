import { CaptureStatus, ProjectLifecycleStatus } from './StateMachine';

export interface ProjectInit {
  id: string;
  name: string;
  description: string;
  lifecycleStatus: ProjectLifecycleStatus;
  isPinned: boolean;
  watermarkPosition: string;
  watermarkOpacity: number;
  watermarkAccentColorArgb: number;
  watermarkFontScale: number;
  createdAt: number;
  updatedAt: number;
}

export class ProjectRecord {
  id: string;
  name: string;
  description: string;
  lifecycleStatus: ProjectLifecycleStatus;
  isPinned: boolean;
  watermarkPosition: string;
  watermarkOpacity: number;
  watermarkAccentColorArgb: number;
  watermarkFontScale: number;
  createdAt: number;
  updatedAt: number;

  constructor(value: ProjectInit) {
    this.id = value.id;
    this.name = value.name;
    this.description = value.description;
    this.lifecycleStatus = value.lifecycleStatus;
    this.isPinned = value.isPinned;
    this.watermarkPosition = value.watermarkPosition;
    this.watermarkOpacity = value.watermarkOpacity;
    this.watermarkAccentColorArgb = value.watermarkAccentColorArgb;
    this.watermarkFontScale = value.watermarkFontScale;
    this.createdAt = value.createdAt;
    this.updatedAt = value.updatedAt;
  }
}

export interface CaptureInit {
  id: string;
  projectId: string;
  projectName: string;
  photoNumber: string;
  workLocation: string;
  workContent: string;
  photographer: string;
  notes: string;
  originalPath: string;
  renderedPath: string;
  publishedUri: string;
  originalSha256: string;
  status: CaptureStatus;
  failureReason: string;
  createdAt: number;
  capturedAt: number;
  latitude: number | null;
  longitude: number | null;
  accuracyMeters: number | null;
  address: string;
  locationOutcome: string;
  processingAttempts: number;
  watermarkLocaleCode: string;
  locationResolution: string;
  originalDeletedAt: number | null;
}

export class CaptureRecord {
  id: string;
  projectId: string;
  projectName: string;
  photoNumber: string;
  workLocation: string;
  workContent: string;
  photographer: string;
  notes: string;
  originalPath: string;
  renderedPath: string;
  publishedUri: string;
  originalSha256: string;
  status: CaptureStatus;
  failureReason: string;
  createdAt: number;
  capturedAt: number;
  latitude: number | null;
  longitude: number | null;
  accuracyMeters: number | null;
  address: string;
  locationOutcome: string;
  processingAttempts: number;
  watermarkLocaleCode: string;
  locationResolution: string;
  originalDeletedAt: number | null;

  constructor(value: CaptureInit) {
    this.id = value.id;
    this.projectId = value.projectId;
    this.projectName = value.projectName;
    this.photoNumber = value.photoNumber;
    this.workLocation = value.workLocation;
    this.workContent = value.workContent;
    this.photographer = value.photographer;
    this.notes = value.notes;
    this.originalPath = value.originalPath;
    this.renderedPath = value.renderedPath;
    this.publishedUri = value.publishedUri;
    this.originalSha256 = value.originalSha256;
    this.status = value.status;
    this.failureReason = value.failureReason;
    this.createdAt = value.createdAt;
    this.capturedAt = value.capturedAt;
    this.latitude = value.latitude;
    this.longitude = value.longitude;
    this.accuracyMeters = value.accuracyMeters;
    this.address = value.address;
    this.locationOutcome = value.locationOutcome;
    this.processingAttempts = value.processingAttempts;
    this.watermarkLocaleCode = value.watermarkLocaleCode;
    this.locationResolution = value.locationResolution;
    this.originalDeletedAt = value.originalDeletedAt;
  }

  hasOriginal(): boolean {
    return this.originalDeletedAt === null && this.originalPath.length > 0;
  }
}

export interface CaptureDraft {
  id: string;
  projectId: string;
  projectName: string;
  workLocation: string;
  workContent: string;
  photographer: string;
  notes: string;
  originalPath: string;
  capturedAt: number;
  latitude: number | null;
  longitude: number | null;
  accuracyMeters: number | null;
  address: string;
  locationOutcome: string;
  watermarkLocaleCode: string;
}

export interface CaptureFilter {
  projectId: string;
  year: number;
  month: number;
  day: number;
  searchText: string;
}

export class CapturePageCursor {
  sortTime: number;
  id: string;

  constructor(sortTime: number, id: string) {
    this.sortTime = sortTime;
    this.id = id;
  }
}

export class CapturePage {
  rows: CaptureRecord[];
  nextCursor: CapturePageCursor | null;

  constructor(rows: CaptureRecord[], nextCursor: CapturePageCursor | null) {
    this.rows = rows;
    this.nextCursor = nextCursor;
  }
}

export interface CaptureTemplateInit {
  id: string;
  projectId: string;
  name: string;
  nameKey: string;
  workLocation: string;
  workContent: string;
  photographer: string;
  createdAt: number;
  updatedAt: number;
}

export class CaptureTemplateRecord {
  id: string;
  projectId: string;
  name: string;
  nameKey: string;
  workLocation: string;
  workContent: string;
  photographer: string;
  createdAt: number;
  updatedAt: number;

  constructor(value: CaptureTemplateInit) {
    this.id = value.id;
    this.projectId = value.projectId;
    this.name = value.name;
    this.nameKey = value.nameKey;
    this.workLocation = value.workLocation;
    this.workContent = value.workContent;
    this.photographer = value.photographer;
    this.createdAt = value.createdAt;
    this.updatedAt = value.updatedAt;
  }
}

export class ProjectSummary {
  project: ProjectRecord;
  captureCount: number;
  readyCount: number;
  pendingCount: number;
  latestCaptureAt: number;
  recentRenderedPaths: string[];

  constructor(project: ProjectRecord, captureCount: number, readyCount: number,
    pendingCount: number, latestCaptureAt: number, recentRenderedPaths: string[]) {
    this.project = project;
    this.captureCount = captureCount;
    this.readyCount = readyCount;
    this.pendingCount = pendingCount;
    this.latestCaptureAt = latestCaptureAt;
    this.recentRenderedPaths = recentRenderedPaths;
  }
}

export interface AppSettingsInit {
  themeMode: string;
  localeCode: string;
  defaultWatermarkPosition: string;
  defaultWatermarkOpacity: number;
  defaultWatermarkAccentColorArgb: number;
  defaultWatermarkFontScale: number;
  locationPermissionPromptDismissed: boolean;
  completionNotificationsEnabled: boolean;
  appSeedColorArgb: number;
}

export class AppSettingsRecord {
  themeMode: string;
  localeCode: string;
  defaultWatermarkPosition: string;
  defaultWatermarkOpacity: number;
  defaultWatermarkAccentColorArgb: number;
  defaultWatermarkFontScale: number;
  locationPermissionPromptDismissed: boolean;
  completionNotificationsEnabled: boolean;
  appSeedColorArgb: number;

  constructor(value: AppSettingsInit) {
    this.themeMode = value.themeMode;
    this.localeCode = value.localeCode;
    this.defaultWatermarkPosition = value.defaultWatermarkPosition;
    this.defaultWatermarkOpacity = value.defaultWatermarkOpacity;
    this.defaultWatermarkAccentColorArgb = value.defaultWatermarkAccentColorArgb;
    this.defaultWatermarkFontScale = value.defaultWatermarkFontScale;
    this.locationPermissionPromptDismissed = value.locationPermissionPromptDismissed;
    this.completionNotificationsEnabled = value.completionNotificationsEnabled;
    this.appSeedColorArgb = value.appSeedColorArgb;
  }
}
