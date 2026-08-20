import { ProjectLifecycleStatus } from './StateMachine';

export class RestoredCaptureInput {
  id: string;
  photoNumber: string;
  workLocation: string;
  workContent: string;
  photographer: string;
  notes: string;
  originalPath: string;
  renderedPath: string;
  originalSha256: string;
  capturedAt: number;
  latitude: number | null;
  longitude: number | null;
  accuracyMeters: number | null;
  address: string;
  watermarkLocaleCode: string;
  originalMissing: boolean;

  constructor(id: string, photoNumber: string, workLocation: string, workContent: string,
    photographer: string, notes: string, originalPath: string, renderedPath: string,
    originalSha256: string, capturedAt: number, latitude: number | null,
    longitude: number | null, accuracyMeters: number | null, address: string,
    watermarkLocaleCode: string, originalMissing: boolean) {
    this.id = id;
    this.photoNumber = photoNumber;
    this.workLocation = workLocation;
    this.workContent = workContent;
    this.photographer = photographer;
    this.notes = notes;
    this.originalPath = originalPath;
    this.renderedPath = renderedPath;
    this.originalSha256 = originalSha256;
    this.capturedAt = capturedAt;
    this.latitude = latitude;
    this.longitude = longitude;
    this.accuracyMeters = accuracyMeters;
    this.address = address;
    this.watermarkLocaleCode = watermarkLocaleCode;
    this.originalMissing = originalMissing;
  }
}
export class RestoredTemplateInput {
  id: string;
  name: string;
  nameKey: string;
  workLocation: string;
  workContent: string;
  photographer: string;
  createdAt: number;
  updatedAt: number;

  constructor(id: string, name: string, nameKey: string, workLocation: string,
    workContent: string, photographer: string, createdAt: number, updatedAt: number) {
    this.id = id;
    this.name = name;
    this.nameKey = nameKey;
    this.workLocation = workLocation;
    this.workContent = workContent;
    this.photographer = photographer;
    this.createdAt = createdAt;
    this.updatedAt = updatedAt;
  }
}

export class RestoredProjectInput {
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
  captures: RestoredCaptureInput[];
  templates: RestoredTemplateInput[];

  constructor(id: string, name: string, description: string,
    lifecycleStatus: ProjectLifecycleStatus, isPinned: boolean, watermarkPosition: string,
    watermarkOpacity: number, watermarkAccentColorArgb: number, watermarkFontScale: number,
    createdAt: number, captures: RestoredCaptureInput[], templates: RestoredTemplateInput[]) {
    this.id = id;
    this.name = name;
    this.description = description;
    this.lifecycleStatus = lifecycleStatus;
    this.isPinned = isPinned;
    this.watermarkPosition = watermarkPosition;
    this.watermarkOpacity = watermarkOpacity;
    this.watermarkAccentColorArgb = watermarkAccentColorArgb;
    this.watermarkFontScale = watermarkFontScale;
    this.createdAt = createdAt;
    this.captures = captures;
    this.templates = templates;
  }
}
