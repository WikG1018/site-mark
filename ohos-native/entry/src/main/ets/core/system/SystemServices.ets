import { common, Permissions, Want } from '@kit.AbilityKit';
import { abilityAccessCtrl } from '@kit.AbilityKit';
import { camera, cameraPicker } from '@kit.CameraKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { geoLocationManager } from '@kit.LocationKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { PublishJournalEntry, PublishJournalStore } from '../../data/prefs/PublishJournalStore';
import { ExifGpsReading, exifGpsReading } from '../../shared/ExifLocationPolicy';
import { AppSettingsLaunchPolicy, SettingsLaunchWant } from '../../shared/AppSettingsLaunchPolicy';

export enum CameraOutcomeCode {
  CAPTURED = 0,
  CANCELLED = 1,
  FAILED = 2
}

export class CameraOutcome {
  code: CameraOutcomeCode;
  path: string;
  debugInjected: boolean;
  message: string;

  constructor(code: CameraOutcomeCode, path: string = '', debugInjected: boolean = false,
    message: string = '') {
    this.code = code;
    this.path = path;
    this.debugInjected = debugInjected;
    this.message = message;
  }
}

export enum LocationOutcomeCode {
  RESOLVED = 'resolved',
  PERMISSION_DENIED = 'permissionDenied',
  SERVICE_DISABLED = 'serviceDisabled',
  TIMEOUT = 'timeout',
  UNAVAILABLE = 'unavailable'
}

export class LocationSnapshot {
  outcome: LocationOutcomeCode;
  latitude: number | null;
  longitude: number | null;
  accuracyMeters: number | null;
  address: string;

  constructor(outcome: LocationOutcomeCode, latitude: number | null = null,
    longitude: number | null = null, accuracyMeters: number | null = null, address: string = '') {
    this.outcome = outcome;
    this.latitude = latitude;
    this.longitude = longitude;
    this.accuracyMeters = accuracyMeters;
    this.address = address;
  }
}

export class PublishJpegOutcome {
  contentUri: string;
  enteredSystemAlbum: boolean;

  constructor(contentUri: string, enteredSystemAlbum: boolean) {
    this.contentUri = contentUri;
    this.enteredSystemAlbum = enteredSystemAlbum;
  }
}

export function backgroundPublishOutcome(publishedUri: string): PublishJpegOutcome {
  return new PublishJpegOutcome(publishedUri, publishedUri.length > 0);
}

export class ImageInspection {
  exists: boolean;
  sizeBytes: number;
  modifiedAt: number;

  constructor(exists: boolean, sizeBytes: number = 0, modifiedAt: number = 0) {
    this.exists = exists;
    this.sizeBytes = sizeBytes;
    this.modifiedAt = modifiedAt;
  }
}

export interface SystemServices {
  createCameraTarget(captureId: string): Promise<string>;
  launchCamera(targetPath: string): Promise<CameraOutcome>;
  recoverCameraCapture(targetPath: string): Promise<CameraOutcome>;
  finishCameraCapture(targetPath: string, keep: boolean): Promise<void>;
  getLocationPermissionState(): Promise<boolean>;
  requestLocationPermission(): Promise<boolean>;
  requestCurrentLocation(localeCode: string): Promise<LocationSnapshot>;
  publishJpegInBackground(sourcePath: string, displayName: string, captureId: string,
    publishedUri: string): Promise<PublishJpegOutcome>;
  saveJpegToAlbum(sourcePath: string, displayName: string, captureId: string,
    publishedUri: string): Promise<PublishJpegOutcome>;
  recoverPublishJournals(): Promise<PublishJournalEntry[]>;
  clearPublishJournal(captureId: string, expectedContentUri: string): Promise<boolean>;
  inspectImage(path: string): Promise<ImageInspection>;
  readExifGps(imagePath: string): Promise<ExifGpsReading | null>;
  openApplicationSettings(): Promise<boolean>;
  openRepository(): Promise<void>;
}

function safeError(error: BusinessError | Error): string {
  const business = error as BusinessError;
  return `${business.code ?? 'unknown'} ${business.message ?? String(error)}`;
}

function validCaptureId(value: string): boolean {
  return /^[A-Za-z0-9][A-Za-z0-9_-]{0,95}$/.test(value);
}

function stripJpegExtension(value: string): string {
  return value.toLowerCase().endsWith('.jpg') ? value.substring(0, value.length - 4) : value;
}

export class HarmonySystemServices implements SystemServices {
  private readonly context: common.UIAbilityContext;
  private readonly journals: PublishJournalStore;

  constructor(context: common.UIAbilityContext, journals: PublishJournalStore) {
    this.context = context;
    this.journals = journals;
  }

  async createCameraTarget(captureId: string): Promise<string> {
    if (!validCaptureId(captureId)) {
      throw new Error('invalid_data:invalid capture id');
    }
    const directory = `${this.context.filesDir}/originals`;
    if (!fileIo.accessSync(directory)) {
      fileIo.mkdirSync(directory, true);
    }
    const targetPath = `${directory}/${captureId}.jpg`;
    const target = fileIo.openSync(targetPath,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    fileIo.closeSync(target);
    return targetPath;
  }

  async launchCamera(targetPath: string): Promise<CameraOutcome> {
    try {
      const profile: cameraPicker.PickerProfile = {
        cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK
      };
      const result = await cameraPicker.pick(this.context, [cameraPicker.PickerMediaType.PHOTO], profile);
      if (result !== undefined && result.resultUri.length > 0) {
        const incomingPath = this.cameraIncomingPath(targetPath);
        if (fileIo.accessSync(incomingPath)) {
          fileIo.unlinkSync(incomingPath);
        }
        await fileIo.copyFile(result.resultUri, incomingPath);
        if (await this.commitIncomingCameraFile(targetPath)) {
          return new CameraOutcome(CameraOutcomeCode.CAPTURED, targetPath);
        }
      }
      if (this.context.applicationInfo.debug) {
        await this.writeDebugSample(targetPath);
        return new CameraOutcome(CameraOutcomeCode.CAPTURED, targetPath, true,
          '模拟器相机不可用，已使用调试样图完成链路验证');
      }
      return new CameraOutcome(CameraOutcomeCode.CANCELLED);
    } catch (error) {
      if (this.context.applicationInfo.debug) {
        try {
          await this.writeDebugSample(targetPath);
          return new CameraOutcome(CameraOutcomeCode.CAPTURED, targetPath, true,
            '模拟器相机不可用，已使用调试样图完成链路验证');
        } catch (fallbackError) {
          return new CameraOutcome(CameraOutcomeCode.FAILED, '', false,
            safeError(fallbackError as BusinessError));
        }
      }
      return new CameraOutcome(CameraOutcomeCode.FAILED, '', false, safeError(error as BusinessError));
    }
  }

  async recoverCameraCapture(targetPath: string): Promise<CameraOutcome> {
    let inspection = await this.inspectImage(targetPath);
    if ((!inspection.exists || inspection.sizeBytes < 1) &&
      await this.commitIncomingCameraFile(targetPath)) {
      inspection = await this.inspectImage(targetPath);
    }
    return inspection.exists && inspection.sizeBytes > 0 ?
      new CameraOutcome(CameraOutcomeCode.CAPTURED, targetPath) :
      new CameraOutcome(CameraOutcomeCode.CANCELLED);
  }

  async finishCameraCapture(targetPath: string, keep: boolean): Promise<void> {
    const incomingPath = this.cameraIncomingPath(targetPath);
    if (fileIo.accessSync(incomingPath)) {
      fileIo.unlinkSync(incomingPath);
    }
    if (!keep && fileIo.accessSync(targetPath)) {
      fileIo.unlinkSync(targetPath);
    }
  }

  private cameraIncomingPath(targetPath: string): string {
    return `${targetPath}.incoming`;
  }

  private async commitIncomingCameraFile(targetPath: string): Promise<boolean> {
    const incomingPath = this.cameraIncomingPath(targetPath);
    const incoming = await this.inspectImage(incomingPath);
    if (!incoming.exists || incoming.sizeBytes < 1) {
      return false;
    }
    if (fileIo.accessSync(targetPath)) {
      fileIo.unlinkSync(targetPath);
    }
    fileIo.moveFileSync(incomingPath, targetPath);
    return true;
  }

  async getLocationPermissionState(): Promise<boolean> {
    try {
      const manager = abilityAccessCtrl.createAtManager();
      const tokenId = this.context.applicationInfo.accessTokenId;
      const precise: Permissions = 'ohos.permission.LOCATION';
      const approximate: Permissions = 'ohos.permission.APPROXIMATELY_LOCATION';
      return manager.verifyAccessTokenSync(tokenId, precise) ===
        abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED ||
        manager.verifyAccessTokenSync(tokenId, approximate) ===
        abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (_) {
      return false;
    }
  }

  async requestLocationPermission(): Promise<boolean> {
    const manager = abilityAccessCtrl.createAtManager();
    const permissions: Permissions[] = [
      'ohos.permission.LOCATION',
      'ohos.permission.APPROXIMATELY_LOCATION'
    ];
    try {
      const result = await manager.requestPermissionsFromUser(this.context, permissions);
      for (const value of result.authResults) {
        if (value === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  async requestCurrentLocation(localeCode: string): Promise<LocationSnapshot> {
    if (!await this.getLocationPermissionState()) {
      return new LocationSnapshot(LocationOutcomeCode.PERMISSION_DENIED);
    }
    return new Promise<LocationSnapshot>((resolve: (value: LocationSnapshot) => void): void => {
      let settled = false;
      const timer = setTimeout((): void => {
        if (!settled) {
          settled = true;
          resolve(new LocationSnapshot(LocationOutcomeCode.TIMEOUT));
        }
      }, 8000);
      geoLocationManager.getCurrentLocation().then(async (location: geoLocationManager.Location): Promise<void> => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timer);
        let address = '';
        try {
          const addresses = await geoLocationManager.getAddressesFromLocation({
            latitude: location.latitude,
            longitude: location.longitude,
            locale: localeCode === 'en' ? 'en' : 'zh',
            maxItems: 1
          });
          if (addresses.length > 0) {
            address = addresses[0].placeName ?? '';
          }
        } catch (_) {
          // Coordinates remain valid when reverse geocoding is unavailable.
        }
        resolve(new LocationSnapshot(LocationOutcomeCode.RESOLVED, location.latitude,
          location.longitude, location.accuracy, address));
      }).catch((): void => {
        if (!settled) {
          settled = true;
          clearTimeout(timer);
          resolve(new LocationSnapshot(LocationOutcomeCode.UNAVAILABLE));
        }
      });
    });
  }

  async publishJpegInBackground(_sourcePath: string, _displayName: string, _captureId: string,
    publishedUri: string): Promise<PublishJpegOutcome> {
    // HarmonyOS currently requires an interactive system confirmation before
    // an application can add a generated JPEG to the user's Photos library.
    // A background queue must never open that panel: it would suspend the
    // serial processor and prevent the user from continuing to shoot. Keep an
    // existing published reference, finish the private render immediately,
    // and let an explicit user action call saveJpegToAlbum().
    return backgroundPublishOutcome(publishedUri);
  }

  async saveJpegToAlbum(sourcePath: string, displayName: string, captureId: string,
    _publishedUri: string): Promise<PublishJpegOutcome> {
    const sourceUri = fileUri.getUriFromPath(sourcePath);
    const helper = photoAccessHelper.getPhotoAccessHelper(this.context);
    const config: photoAccessHelper.PhotoCreationConfig = {
      title: stripJpegExtension(displayName),
      fileNameExtension: 'jpg',
      photoType: photoAccessHelper.PhotoType.IMAGE
    };
    const uris = await helper.showAssetsCreationDialog([sourceUri], [config]);
    if (uris.length === 0 || uris[0].length === 0) {
      throw new Error('album_save_cancelled');
    }
    const contentUri = uris[0];
    let source: fileIo.File | null = null;
    let destination: fileIo.File | null = null;
    try {
      source = fileIo.openSync(sourcePath, fileIo.OpenMode.READ_ONLY);
      destination = fileIo.openSync(contentUri,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
      fileIo.copyFileSync(source.fd, destination.fd);
    } catch (_) {
      throw new Error('album_copy_failed');
    } finally {
      if (source !== null) {
        try {
          fileIo.closeSync(source);
        } catch (_) {
        }
      }
      if (destination !== null) {
        try {
          fileIo.closeSync(destination);
        } catch (_) {
        }
      }
    }
    try {
      await this.journals.record(captureId, contentUri);
    } catch (_) {
      // The system-album copy belongs to the user once written. Keep it even
      // when the recovery journal cannot be committed and report the failure.
      throw new Error('album_journal_failed');
    }
    return new PublishJpegOutcome(contentUri, true);
  }

  recoverPublishJournals(): Promise<PublishJournalEntry[]> {
    return this.journals.recover();
  }

  clearPublishJournal(captureId: string, expectedContentUri: string): Promise<boolean> {
    return this.journals.clear(captureId, expectedContentUri);
  }

  inspectImage(path: string): Promise<ImageInspection> {
    try {
      const stat = fileIo.statSync(path);
      return Promise.resolve(new ImageInspection(true, stat.size, stat.mtime));
    } catch (_) {
      return Promise.resolve(new ImageInspection(false));
    }
  }

  async openApplicationSettings(): Promise<boolean> {
    const policy = new AppSettingsLaunchPolicy((want: SettingsLaunchWant): Promise<boolean> =>
      this.startSettingsAbility(want));
    return policy.openApplicationSettings('com.huawei.hmos.settings',
      this.context.abilityInfo.bundleName);
  }

  private async startSettingsAbility(want: SettingsLaunchWant): Promise<boolean> {
    const request: Want = {};
    if (want.bundleName.length > 0) {
      request.bundleName = want.bundleName;
    }
    if (want.abilityName.length > 0) {
      request.abilityName = want.abilityName;
    }
    if (want.uri.length > 0) {
      request.uri = want.uri;
    }
    if (want.action.length > 0) {
      request.action = want.action;
    }
    if (want.parameters !== null) {
      request.parameters = want.parameters;
    }
    try {
      await this.context.startAbility(request);
      return true;
    } catch (_) {
      return false;
    }
  }

  async readExifGps(imagePath: string): Promise<ExifGpsReading | null> {
    try {
      const source: image.ImageSource = image.createImageSource(imagePath);
      const properties = await source.getImageProperties([
        image.PropertyKey.GPS_LATITUDE, image.PropertyKey.GPS_LATITUDE_REF,
        image.PropertyKey.GPS_LONGITUDE, image.PropertyKey.GPS_LONGITUDE_REF]);
      try {
        await source.release();
      } catch (_) {
      }
      return exifGpsReading(this.exifText(properties[image.PropertyKey.GPS_LATITUDE]),
        this.exifText(properties[image.PropertyKey.GPS_LATITUDE_REF]),
        this.exifText(properties[image.PropertyKey.GPS_LONGITUDE]),
        this.exifText(properties[image.PropertyKey.GPS_LONGITUDE_REF]));
    } catch (_) {
      return null;
    }
  }

  private exifText(value: string | null): string {
    return value === null ? '' : value;
  }

  openRepository(): Promise<void> {
    return this.context.openLink('https://github.com/WikG1018/site-mark');
  }

  private async writeDebugSample(targetPath: string): Promise<void> {
    const source = await this.context.resourceManager.getRawFileContent('probe.jpg');
    const target = fileIo.openSync(targetPath,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(target.fd, source.buffer);
    } finally {
      fileIo.closeSync(target);
    }
  }
}
