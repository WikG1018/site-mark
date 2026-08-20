import { common, Want, abilityAccessCtrl, Permissions, wantAgent } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { camera, cameraPicker } from '@kit.CameraKit';
import { fileIo as fs, fileUri, picker } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { geoLocationManager } from '@kit.LocationKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { notificationManager } from '@kit.NotificationKit';
import { preferences } from '@kit.ArkData';
import { systemShare } from '@kit.ShareKit';
import UIAbility from '@ohos.app.ability.UIAbility';

interface PermissionAskResult {
  authResults: Array<number>;
  dialogShownResults?: Array<boolean>;
}

interface CameraCaptureResult {
  outcome: number;
  outputPath: string;
  errorMessage: string | null;
}

interface RecoveredCapture {
  captureId: string;
  outputPath: string;
  hasContent: boolean;
}

interface LocationFixResult {
  outcome: number;
  latitude: number | null;
  longitude: number | null;
  accuracyMeters: number | null;
  address: string | null;
  errorMessage: string | null;
}

interface PublishJpegResult {
  contentUri: string;
  supersededUris: Array<string>;
}

interface GpsPair {
  latitude: number | null;
  longitude: number | null;
}

interface PublishJournalSnapshot {
  captureId: string;
  contentUri: string;
  supersededUris: Array<string>;
}

interface JpegCreateOptions {
  title: string;
}

interface CameraPickerSaveProfile {
  cameraPosition: camera.CameraPosition;
  saveUri: string;
}

const CAPTURE_PREFERENCES = 'sitemark_capture_recovery';
const PUBLISH_PREFERENCES = 'sitemark_publish_journal';
const JOURNAL_PREFIX = 'journal.';
const JOURNAL_EXISTS = 'exists';
const JOURNAL_NEW_URI = 'newUri';
const JOURNAL_STALE_COUNT = 'staleCount';
const JOURNAL_STALE_PREFIX = 'stale.';
const BASE64URL_TABLE = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
const KEY_CAPTURE_ID = 'capture_id';
const KEY_CAPTURE_PATH = 'capture_path';
const KEY_LOCATION_PERMISSION_REQUESTED = 'location_permission_requested';
const SAFE_CAPTURE_ID = /^[A-Za-z0-9][A-Za-z0-9_-]{0,95}$/;

const CAMERA_OUTCOME_CAPTURED = 0;
const CAMERA_OUTCOME_CANCELLED = 1;
const CAMERA_OUTCOME_FAILED = 2;
const LOCATION_PRECISE = 0;
const LOCATION_APPROXIMATE = 1;
const LOCATION_PERMISSION_DENIED = 2;
const LOCATION_SERVICES_DISABLED = 3;
const LOCATION_TIMEOUT = 4;
const LOCATION_UNAVAILABLE = 5;
const PERMISSION_GRANTED = 0;
const PERMISSION_DENIED = 1;
const PERMISSION_PERMANENTLY_DENIED = 2;

const PERMISSION_CAMERA = 'ohos.permission.CAMERA';
const PERMISSION_APPROXIMATE = 'ohos.permission.APPROXIMATELY_LOCATION';
const PERMISSION_LOCATION = 'ohos.permission.LOCATION';
const PERMISSION_READ_MEDIA = 'ohos.permission.READ_IMAGEVIDEO';
const PERMISSION_WRITE_MEDIA = 'ohos.permission.WRITE_IMAGEVIDEO';
const ARCHIVE_SAVE_SAVED = 0;

export default class OhosSystemHost {
  private context: common.Context;
  private ability: UIAbility | null = null;
  private captureStore: preferences.Preferences | null = null;
  private publishStore: preferences.Preferences | null = null;
  private cameraBusy: boolean = false;
  private locationBusy: boolean = false;

  constructor(context: common.Context) {
    this.context = context;
  }

  attachAbility(ability: UIAbility): void {
    this.ability = ability;
  }

  detachAbility(): void {
    this.ability = null;
  }

  async handle(method: string, args: Record<string, Object | null | undefined> | null): Promise<Object | null> {
    switch (method) {
      case 'createCameraTarget':
        return await this.createCameraTarget(this.requiredString(args, 'captureId'));
      case 'launchCamera':
        return await this.launchCamera(this.requiredString(args, 'captureId'));
      case 'recoverCameraCapture':
        return await this.recoverCameraCapture();
      case 'finishCameraCapture':
        await this.finishCameraCapture(
          this.requiredString(args, 'captureId'),
          this.boolArg(args, 'keepOriginal'),
        );
        return null;
      case 'getLocationPermissionState':
        return await this.getLocationPermissionState();
      case 'requestLocationPermission':
        return await this.requestLocationPermission();
      case 'openApplicationSettings':
        await this.openApplicationSettings();
        return null;
      case 'requestCurrentLocation':
        return await this.requestCurrentLocation(this.numberArg(args, 'timeoutMillis', 10000));
      case 'detectGalleryAccess':
        return await this.detectGalleryAccess();
      case 'getTemporaryDirectory':
      case 'getApplicationSupportDirectory':
      case 'getApplicationDocumentsDirectory':
      case 'getApplicationCacheDirectory':
        return this.resolveAppDirectory(method);
      case 'publishJpeg':
        return await this.publishJpeg(
          this.requiredString(args, 'sourcePath'),
          this.requiredString(args, 'displayName'),
          this.requiredString(args, 'captureId'),
          this.optionalString(args, 'publishedUri'),
        );
      case 'recoverPublishJournals':
        return await this.recoverPublishJournals();
      case 'clearPublishJournal':
        await this.clearPublishJournal(
          this.requiredString(args, 'captureId'),
          this.requiredString(args, 'expectedContentUri'),
        );
        return null;
      case 'deletePublishedImage':
        await this.deletePublishedImage(this.requiredString(args, 'contentUri'));
        return null;
      case 'inspectImage':
        return await this.inspectImage(this.requiredString(args, 'path'));
      case 'saveArchive':
        return await this.saveArchive(
          this.requiredString(args, 'sourcePath'),
          this.requiredString(args, 'suggestedName'),
        );
      case 'pickArchive':
        return await this.pickArchive();
      case 'shareFile':
        await this.shareFile(this.requiredString(args, 'path'));
        return null;
      case 'openLink':
        return await this.openLink(this.requiredString(args, 'url'));
      case 'requestEnableNotification':
        return await this.requestEnableNotification();
      case 'publishCaptureReady':
        await this.publishCaptureReady(
          this.requiredString(args, 'title'),
          this.requiredString(args, 'text'),
          this.requiredString(args, 'deepLink'),
        );
        return null;
      case 'getAll':
        return this.packageInfo();
      default:
        throw new Error(`unimplemented:${method}`);
    }
  }

  private async createCameraTarget(captureId: string): Promise<string> {
    this.assertCaptureId(captureId);
    const directory = `${this.context.filesDir}/originals`;
    await this.ensureDir(directory);
    const target = `${directory}/${captureId}.jpg`;
    this.recreateEmptyFile(target);
    const store = await this.capturePreferences();
    await store.put(KEY_CAPTURE_ID, captureId);
    await store.put(KEY_CAPTURE_PATH, target);
    await store.flush();
    return target;
  }

  private async launchCamera(captureId: string): Promise<CameraCaptureResult> {
    if (this.cameraBusy) {
      throw new Error('A camera capture is already active');
    }
    const target = await this.preparedTarget(captureId);
    const abilityContext = this.ability?.context as common.UIAbilityContext | undefined;
    if (abilityContext === undefined) {
      return this.cameraFailed(target);
    }
    const cameraState = await this.ensurePermission(abilityContext, PERMISSION_CAMERA);
    if (cameraState !== PERMISSION_GRANTED) {
      return this.cameraFailed(target);
    }
    this.cameraBusy = true;
    try {
      this.ensureWritableFile(target);
      try {
        const pickerProfile: CameraPickerPositionProfile = {
          cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK,
        };
        const pickerResult = await cameraPicker.pick(
          abilityContext,
          [cameraPicker.PickerMediaType.PHOTO],
          pickerProfile as cameraPicker.PickerProfile,
        );
        if (pickerResult === undefined || pickerResult.resultCode !== 0) {
          return this.cameraCancelled(target);
        }
        const resultUri = pickerResult.resultUri ?? '';
        if (resultUri.length === 0) {
          return this.cameraFailed(target);
        }
        return await this.materializeCapture(resultUri, target);
      } catch (_pickerError) {
        return this.cameraFailed(target);
      }
    } catch (_error) {
      return this.cameraFailed(target);
    } finally {
      this.cameraBusy = false;
    }
  }

  private async recoverCameraCapture(): Promise<RecoveredCapture | null> {
    const store = await this.capturePreferences();
    const captureId = await store.get(KEY_CAPTURE_ID, '') as string;
    const outputPath = await store.get(KEY_CAPTURE_PATH, '') as string;
    if (captureId.length === 0 || outputPath.length === 0) {
      return null;
    }
    const recovered: RecoveredCapture = {
      captureId: captureId,
      outputPath: outputPath,
      hasContent: this.hasCaptureContent(outputPath),
    };
    return recovered;
  }

  private async finishCameraCapture(captureId: string, keepOriginal: boolean): Promise<void> {
    const store = await this.capturePreferences();
    const pendingId = await store.get(KEY_CAPTURE_ID, '') as string;
    if (pendingId !== captureId) {
      return;
    }
    const path = await store.get(KEY_CAPTURE_PATH, '') as string;
    await store.delete(KEY_CAPTURE_ID);
    await store.delete(KEY_CAPTURE_PATH);
    await store.flush();
    if (!keepOriginal && path.length > 0 && fs.accessSync(path)) {
      fs.unlinkSync(path);
    }
  }

  private async getLocationPermissionState(): Promise<number> {
    if (await this.hasAnyLocationPermission()) {
      return PERMISSION_GRANTED;
    }
    const store = await this.capturePreferences();
    const asked = await store.get(KEY_LOCATION_PERMISSION_REQUESTED, false) as boolean;
    return asked ? PERMISSION_PERMANENTLY_DENIED : PERMISSION_DENIED;
  }

  private async requestLocationPermission(): Promise<number> {
    if (await this.hasAnyLocationPermission()) {
      return PERMISSION_GRANTED;
    }
    const abilityContext = this.requireAbilityContext('Location permission requires a foreground ability');
    const store = await this.capturePreferences();
    await store.put(KEY_LOCATION_PERMISSION_REQUESTED, true);
    await store.flush();
    const result = await this.requestPermissions(abilityContext, [PERMISSION_APPROXIMATE, PERMISSION_LOCATION]);
    if (this.anyGranted(result.authResults)) {
      return PERMISSION_GRANTED;
    }
    if (this.dialogWasHidden(result)) {
      return PERMISSION_PERMANENTLY_DENIED;
    }
    return PERMISSION_DENIED;
  }

  private async openApplicationSettings(): Promise<void> {
    const context = this.abilityContextOrApp();
    const settingsParams: Record<string, Object> = {
      'pushParams': context.applicationInfo.name,
    };
    const want: Want = {
      bundleName: 'com.huawei.hmos.settings',
      abilityName: 'com.huawei.hmos.settings.MainAbility',
      uri: 'application_info_entry',
      parameters: settingsParams,
    };
    await this.requireAbilityContext('Opening settings requires a foreground ability').startAbility(want);
  }

  private async requestCurrentLocation(timeoutMillis: number): Promise<LocationFixResult> {
    if (this.locationBusy) {
      throw new Error('A location request is already active');
    }
    this.locationBusy = true;
    try {
      if (!(await this.hasAnyLocationPermission())) {
        return this.locationResult(LOCATION_PERMISSION_DENIED);
      }
      if (!geoLocationManager.isLocationEnabled()) {
        return this.locationResult(LOCATION_SERVICES_DISABLED);
      }
      const request: geoLocationManager.CurrentLocationRequest = {
        timeoutMs: Math.min(Math.max(timeoutMillis, 1000), 30000),
        priority: (await this.hasPermission(PERMISSION_LOCATION))
          ? geoLocationManager.LocationRequestPriority.ACCURACY
          : geoLocationManager.LocationRequestPriority.FIRST_FIX,
      };
      try {
        const location = await geoLocationManager.getCurrentLocation(request);
        const fix: LocationFixResult = {
          outcome: (await this.hasPermission(PERMISSION_LOCATION)) ? LOCATION_PRECISE : LOCATION_APPROXIMATE,
          latitude: location.latitude,
          longitude: location.longitude,
          accuracyMeters: location.accuracy,
          address: null,
          errorMessage: null,
        };
        return fix;
      } catch (error) {
        const code = (error as BusinessError).code;
        if (code === 3301100) {
          return this.locationResult(LOCATION_SERVICES_DISABLED);
        }
        if (code === 3301200 || code === 3301800) {
          return this.locationResult(LOCATION_TIMEOUT);
        }
        if (code === 201) {
          return this.locationResult(LOCATION_PERMISSION_DENIED);
        }
        return this.locationResult(LOCATION_UNAVAILABLE);
      }
    } finally {
      this.locationBusy = false;
    }
  }

  private async detectGalleryAccess(): Promise<string> {
    if (await this.hasPermission(PERMISSION_READ_MEDIA) && await this.hasPermission(PERMISSION_WRITE_MEDIA)) {
      return 'acl';
    }
    return 'pickerFallback';
  }

  private async publishJpeg(
    sourcePath: string,
    displayName: string,
    captureId: string,
    publishedUri: string | null,
  ): Promise<PublishJpegResult> {
    this.assertCaptureId(captureId);
    const source = this.validatedPrivateFile(sourcePath);
    this.normalizedJpegName(displayName);
    const leftover = await this.peekPublishJournal(captureId);
    const contentUri = await this.writePublishedJpeg(source, captureId, displayName);
    const superseded = this.collectSuperseded(publishedUri, leftover, contentUri);
    const recorded = await this.recordPublishJournal(captureId, contentUri, superseded);
    if (!recorded) {
      throw new Error('Failed to persist the publish journal');
    }
    const published: PublishJpegResult = {
      contentUri: contentUri,
      supersededUris: superseded,
    };
    return published;
  }

  private async writePublishedJpeg(
    sourcePath: string,
    captureId: string,
    displayName: string,
  ): Promise<string> {
    if (await this.detectGalleryAccess() === 'acl') {
      try {
        return await this.writeAclJpeg(sourcePath, displayName);
      } catch (_error) {
        return await this.writePickerOrSandboxJpeg(sourcePath, captureId, displayName);
      }
    }
    return await this.writePickerOrSandboxJpeg(sourcePath, captureId, displayName);
  }

  private async writeAclJpeg(sourcePath: string, displayName: string): Promise<string> {
    const helper = photoAccessHelper.getPhotoAccessHelper(this.context);
    const title = this.normalizedJpegName(displayName).replace(/\.jpe?g$/i, '');
    const createOptions: JpegCreateOptions = {
      title: title,
    };
    const created = await helper.createAsset(
      photoAccessHelper.PhotoType.IMAGE,
      'jpg',
      createOptions,
    );
    const uri = typeof created === 'string' ? created : (created as photoAccessHelper.PhotoAsset).uri;
    await this.copyFileToUri(sourcePath, uri);
    return uri;
  }

  private async writePickerOrSandboxJpeg(
    sourcePath: string,
    captureId: string,
    displayName: string,
  ): Promise<string> {
    const abilityContext = this.ability?.context as common.UIAbilityContext | undefined;
    if (abilityContext === undefined) {
      return await this.writeSandboxJpeg(sourcePath, captureId);
    }
    const documentPicker = new picker.DocumentViewPicker(abilityContext);
    const destinations = await documentPicker.save({
      newFileNames: [this.normalizedJpegName(displayName)],
      fileSuffixChoices: ['jpg'],
    });
    if (destinations === undefined || destinations.length === 0) {
      throw new Error('User cancelled the save picker');
    }
    const destination = this.stringAt(destinations, 0);
    if (destination.startsWith('file://')) {
      this.copyFile(sourcePath, this.pathFromUri(destination));
      return destination;
    }
    await this.copyFileToUri(sourcePath, destination);
    return destination;
  }

  private async writeSandboxJpeg(sourcePath: string, captureId: string): Promise<string> {
    const directory = `${this.context.filesDir}/published`;
    await this.ensureDir(directory);
    const destination = `${directory}/${captureId}.jpg`;
    this.copyFile(sourcePath, destination);
    return fileUri.getUriFromPath(destination);
  }

  private async saveArchive(sourcePath: string, suggestedName: string): Promise<number> {
    const source = this.validatedArchiveSource(sourcePath);
    const name = this.normalizedZipName(suggestedName);
    const abilityContext = this.ability?.context as common.UIAbilityContext | undefined;
    if (abilityContext !== undefined) {
      try {
        const documentPicker = new picker.DocumentViewPicker(abilityContext);
        const destinations = await documentPicker.save({
          newFileNames: [name],
          fileSuffixChoices: ['zip'],
        });
        if (destinations !== undefined && destinations.length > 0) {
          const destination = this.stringAt(destinations, 0);
          if (destination.startsWith('file://')) {
            this.copyFile(source, this.pathFromUri(destination));
          } else {
            await this.copyFileToUri(source, destination);
          }
          return ARCHIVE_SAVE_SAVED;
        }
      } catch (_error) {
      }
    }
    return await this.writeSandboxZip(source, name);
  }

  private async pickArchive(): Promise<string> {
    const abilityContext = this.ability?.context as common.UIAbilityContext | undefined;
    if (abilityContext === undefined) {
      throw new Error('ability context unavailable');
    }
    const documentPicker = new picker.DocumentViewPicker(abilityContext);
    const uris = await documentPicker.select({
      maxSelectNumber: 1,
      fileSuffixFilters: ['.zip'],
    });
    if (uris === undefined || uris.length === 0) {
      return '';
    }
    const uri = this.stringAt(uris, 0);
    const directory = `${this.context.filesDir}/imports`;
    await this.ensureDir(directory);
    const destination = `${directory}/sitemark-restore-${Date.now()}.zip`;
    await this.copyUriToPath(uri, destination);
    if (!this.hasCaptureContent(destination)) {
      throw new Error('picked archive is empty');
    }
    return destination;
  }

  private async openLink(url: string): Promise<boolean> {
    if (!url.startsWith('https://') && !url.startsWith('http://')) {
      return false;
    }
    const abilityContext = this.ability?.context as common.UIAbilityContext | undefined;
    if (abilityContext === undefined) {
      return false;
    }
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: url,
    };
    try {
      await abilityContext.startAbility(want);
      return true;
    } catch (_error) {
      return false;
    }
  }

  private async shareFile(path: string): Promise<void> {
    if (!this.hasCaptureContent(path)) {
      throw new Error('share source is empty or missing');
    }
    const abilityContext = this.requireAbilityContext('ability context unavailable');
    const record: systemShare.SharedRecord = {
      utd: this.shareUtdForPath(path),
      uri: fileUri.getUriFromPath(path),
      title: this.fileNameFromPath(path),
      label: 'SiteMark',
    };
    const controller = new systemShare.ShareController(new systemShare.SharedData(record));
    await controller.show(abilityContext, {
      previewMode: systemShare.SharePreviewMode.DEFAULT,
      selectionMode: systemShare.SelectionMode.SINGLE,
    });
  }

  private shareUtdForPath(path: string): string {
    const lower = path.toLowerCase();
    if (lower.endsWith('.zip')) {
      return 'general.zip-archive';
    }
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'general.jpeg';
    }
    if (lower.endsWith('.png')) {
      return 'general.png';
    }
    return 'general.file';
  }

  private fileNameFromPath(path: string): string {
    const slash = Math.max(path.lastIndexOf('/'), path.lastIndexOf('\\'));
    if (slash < 0 || slash + 1 >= path.length) {
      return path;
    }
    return path.substring(slash + 1);
  }

  private async writeSandboxZip(sourcePath: string, fileName: string): Promise<number> {
    const directory = `${this.context.filesDir}/exports`;
    await this.ensureDir(directory);
    const destination = `${directory}/${fileName}`;
    if (sourcePath !== destination) {
      this.copyFile(sourcePath, destination);
    }
    return ARCHIVE_SAVE_SAVED;
  }

  private validatedArchiveSource(sourcePath: string): string {
    if (!sourcePath.startsWith(`${this.context.filesDir}/`) ||
        !sourcePath.toLowerCase().endsWith('.zip') ||
        !this.hasCaptureContent(sourcePath)) {
      throw new Error('Backup source is empty, missing, or outside private storage');
    }
    return sourcePath;
  }

  private normalizedZipName(suggestedName: string): string {
    const trimmed = suggestedName.trim();
    if (!trimmed.toLowerCase().endsWith('.zip') || trimmed.length <= 4) {
      throw new Error('Backup filename must end with .zip');
    }
    if (/[\u0000-\u001f\/\\:*?"<>|]/.test(trimmed)) {
      throw new Error('Invalid backup filename');
    }
    return trimmed;
  }

  private collectSuperseded(
    publishedUri: string | null,
    leftover: PublishJournalSnapshot | null,
    contentUri: string,
  ): Array<string> {
    const uris: Array<string> = [];
    const seen: Record<string, boolean> = {};
    seen[contentUri] = true;
    const add = (uri: string | null | undefined): void => {
      if (uri === undefined || uri === null || uri.length === 0 || seen[uri]) {
        return;
      }
      seen[uri] = true;
      uris.push(uri);
    };
    add(publishedUri);
    if (leftover !== null) {
      add(leftover.contentUri);
      leftover.supersededUris.forEach((uri: string) => add(uri));
    }
    return uris;
  }

  private async peekPublishJournal(captureId: string): Promise<PublishJournalSnapshot | null> {
    const store = await this.publishPreferences();
    const prefix = this.journalPrefix(captureId);
    const exists = await store.get(`${prefix}${JOURNAL_EXISTS}`, '') as string;
    if (exists.length === 0) {
      return null;
    }
    const contentUri = await store.get(`${prefix}${JOURNAL_NEW_URI}`, '') as string;
    if (contentUri.length === 0) {
      return null;
    }
    const snapshot: PublishJournalSnapshot = {
      captureId: captureId,
      contentUri: contentUri,
      supersededUris: await this.readStaleUris(store, prefix),
    };
    return snapshot;
  }

  private async recordPublishJournal(
    captureId: string,
    contentUri: string,
    supersededUris: Array<string>,
  ): Promise<boolean> {
    const store = await this.publishPreferences();
    const prefix = this.journalPrefix(captureId);
    const previousCount = Number.parseInt(await store.get(`${prefix}${JOURNAL_STALE_COUNT}`, '0') as string, 10) || 0;
    await store.put(`${prefix}${JOURNAL_NEW_URI}`, contentUri);
    await store.put(`${prefix}${JOURNAL_STALE_COUNT}`, `${supersededUris.length}`);
    await store.put(`${prefix}${JOURNAL_EXISTS}`, 'true');
    for (let index = 0; index < supersededUris.length; index++) {
      await store.put(`${prefix}${JOURNAL_STALE_PREFIX}${index}`, this.stringAt(supersededUris, index));
    }
    for (let index = supersededUris.length; index < previousCount; index++) {
      await store.delete(`${prefix}${JOURNAL_STALE_PREFIX}${index}`);
    }
    try {
      await store.flush();
      return true;
    } catch (_error) {
      return false;
    }
  }

  private async recoverPublishJournals(): Promise<Array<PublishJournalSnapshot>> {
    const store = await this.publishPreferences();
    const keys = await this.publishJournalKeys(store);
    const recovered: Array<PublishJournalSnapshot> = [];
    for (const key of keys) {
      if (!key.endsWith(`.${JOURNAL_EXISTS}`)) {
        continue;
      }
      const prefix = `${key.substring(0, key.length - `.${JOURNAL_EXISTS}`.length)}.`;
      const contentUri = await store.get(`${prefix}${JOURNAL_NEW_URI}`, '') as string;
      if (contentUri.length === 0) {
        continue;
      }
      const captureId = this.decodeJournalCaptureId(prefix);
      if (captureId === null) {
        continue;
      }
      const item: PublishJournalSnapshot = {
        captureId: captureId,
        contentUri: contentUri,
        supersededUris: await this.readStaleUris(store, prefix),
      };
      recovered.push(item);
    }
    return recovered;
  }

  private async clearPublishJournal(captureId: string, expectedContentUri: string): Promise<void> {
    const store = await this.publishPreferences();
    const prefix = this.journalPrefix(captureId);
    const exists = await store.get(`${prefix}${JOURNAL_EXISTS}`, '') as string;
    if (exists.length === 0) {
      return;
    }
    const current = await store.get(`${prefix}${JOURNAL_NEW_URI}`, '') as string;
    if (current.length > 0 && current !== expectedContentUri) {
      return;
    }
    const keys = await this.publishJournalKeys(store);
    for (const key of keys) {
      if (key.startsWith(prefix)) {
        await store.delete(key);
      }
    }
    await store.flush();
  }

  private async deletePublishedImage(contentUri: string): Promise<void> {
    if (contentUri.length === 0) {
      return;
    }
    if (contentUri.startsWith('file://')) {
      try {
        const path = this.pathFromUri(contentUri);
        if (this.pathExists(path)) {
          fs.unlinkSync(path);
        }
      } catch (_error) {
        return;
      }
      return;
    }
    if (await this.detectGalleryAccess() !== 'acl') {
      return;
    }
    try {
      await photoAccessHelper.MediaAssetChangeRequest.deleteAssets(this.context, [contentUri]);
    } catch (_error) {
      return;
    }
  }

  private async readStaleUris(
    store: preferences.Preferences,
    prefix: string,
  ): Promise<Array<string>> {
    const count = Number.parseInt(await store.get(`${prefix}${JOURNAL_STALE_COUNT}`, '0') as string, 10) || 0;
    const uris: Array<string> = [];
    for (let index = 0; index < count; index++) {
      const uri = await store.get(`${prefix}${JOURNAL_STALE_PREFIX}${index}`, '') as string;
      if (uri.length > 0) {
        uris.push(uri);
      }
    }
    return uris;
  }

  private async publishPreferences(): Promise<preferences.Preferences> {
    if (this.publishStore === null) {
      this.publishStore = await preferences.getPreferences(this.context, PUBLISH_PREFERENCES);
    }
    return this.publishStore;
  }

  private async publishJournalKeys(store: preferences.Preferences): Promise<Array<string>> {
    const values = await store.getAll();
    return Object.keys(values);
  }

  private journalPrefix(captureId: string): string {
    return `${JOURNAL_PREFIX}${this.encodeJournalCaptureId(captureId)}.`;
  }

  private encodeJournalCaptureId(captureId: string): string {
    const bytes = this.utf8Bytes(captureId);
    let bits = '';
    for (let index = 0; index < bytes.length; index++) {
      bits += this.numberAt(bytes, index).toString(2).padStart(8, '0');
    }
    let encoded = '';
    for (let index = 0; index < bits.length; index += 6) {
      const chunk = bits.substring(index, index + 6).padEnd(6, '0');
      encoded += this.charAt(BASE64URL_TABLE, Number.parseInt(chunk, 2));
    }
    return encoded;
  }

  private decodeJournalCaptureId(keyPrefix: string): string | null {
    if (!keyPrefix.startsWith(JOURNAL_PREFIX) || !keyPrefix.endsWith('.')) {
      return null;
    }
    const encoded = keyPrefix.substring(JOURNAL_PREFIX.length, keyPrefix.length - 1);
    if (encoded.length === 0) {
      return null;
    }
    try {
      let bits = '';
      for (let index = 0; index < encoded.length; index++) {
        const tableIndex = BASE64URL_TABLE.indexOf(this.charAt(encoded, index));
        if (tableIndex < 0) {
          return null;
        }
        bits += tableIndex.toString(2).padStart(6, '0');
      }
      const byteLength = Math.floor(bits.length / 8);
      const bytes: Array<number> = [];
      for (let index = 0; index < byteLength; index++) {
        bytes.push(Number.parseInt(bits.substring(index * 8, index * 8 + 8), 2));
      }
      return this.utf8String(bytes);
    } catch (_error) {
      return null;
    }
  }

  private utf8Bytes(value: string): Array<number> {
    const bytes: Array<number> = [];
    for (let index = 0; index < value.length; index++) {
      let code = value.charCodeAt(index);
      if (code >= 0xd800 && code <= 0xdbff && index + 1 < value.length) {
        const next = value.charCodeAt(index + 1);
        if (next >= 0xdc00 && next <= 0xdfff) {
          code = ((code - 0xd800) << 10) + (next - 0xdc00) + 0x10000;
          index += 1;
        }
      }
      if (code <= 0x7f) {
        bytes.push(code);
      } else if (code <= 0x7ff) {
        bytes.push(0xc0 | (code >> 6), 0x80 | (code & 0x3f));
      } else if (code <= 0xffff) {
        bytes.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
      } else {
        bytes.push(
          0xf0 | (code >> 18),
          0x80 | ((code >> 12) & 0x3f),
          0x80 | ((code >> 6) & 0x3f),
          0x80 | (code & 0x3f),
        );
      }
    }
    return bytes;
  }

  private utf8String(bytes: Array<number>): string {
    let result = '';
    let index = 0;
    while (index < bytes.length) {
      const lead = this.numberAt(bytes, index);
      let code = 0;
      let size = 1;
      if (lead <= 0x7f) {
        code = lead;
      } else if ((lead & 0xe0) === 0xc0 && index + 1 < bytes.length) {
        code = ((lead & 0x1f) << 6) | (this.numberAt(bytes, index + 1) & 0x3f);
        size = 2;
      } else if ((lead & 0xf0) === 0xe0 && index + 2 < bytes.length) {
        code = ((lead & 0x0f) << 12) | ((this.numberAt(bytes, index + 1) & 0x3f) << 6) | (this.numberAt(bytes, index + 2) & 0x3f);
        size = 3;
      } else if ((lead & 0xf8) === 0xf0 && index + 3 < bytes.length) {
        code = ((lead & 0x07) << 18) |
          ((this.numberAt(bytes, index + 1) & 0x3f) << 12) |
          ((this.numberAt(bytes, index + 2) & 0x3f) << 6) |
          (this.numberAt(bytes, index + 3) & 0x3f);
        size = 4;
      } else {
        throw new Error('invalid utf8');
      }
      if (code > 0xffff) {
        const extra = code - 0x10000;
        result += String.fromCharCode(0xd800 + (extra >> 10), 0xdc00 + (extra & 0x3ff));
      } else {
        result += String.fromCharCode(code);
      }
      index += size;
    }
    return result;
  }

  private validatedPrivateFile(sourcePath: string): string {
    if (!sourcePath.startsWith(`${this.context.filesDir}/`) || !this.hasCaptureContent(sourcePath)) {
      throw new Error('Publish source is outside private storage');
    }
    return sourcePath;
  }

  private normalizedJpegName(displayName: string): string {
    const trimmed = displayName.trim();
    if (trimmed.length === 0) {
      throw new Error('Display name is empty');
    }
    const base = trimmed.toLowerCase().endsWith('.jpg') || trimmed.toLowerCase().endsWith('.jpeg')
      ? trimmed
      : `${trimmed}.jpg`;
    if (!/^[A-Za-z0-9._-]+$/.test(base)) {
      throw new Error('Display name is invalid');
    }
    return base;
  }

  private async copyFileToUri(sourcePath: string, destinationUri: string): Promise<void> {
    const input = fs.openSync(sourcePath, fs.OpenMode.READ_ONLY);
    const output = fs.openSync(destinationUri, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      const stat = fs.statSync(sourcePath);
      const buffer = new ArrayBuffer(stat.size);
      fs.readSync(input.fd, buffer);
      fs.writeSync(output.fd, buffer);
    } finally {
      fs.closeSync(input);
      fs.closeSync(output);
    }
  }

  private async preparedTarget(captureId: string): Promise<string> {
    const store = await this.capturePreferences();
    const pendingId = await store.get(KEY_CAPTURE_ID, '') as string;
    if (pendingId !== captureId) {
      throw new Error('Capture target has not been prepared');
    }
    const path = await store.get(KEY_CAPTURE_PATH, '') as string;
    if (path.length === 0) {
      throw new Error('Capture target path is missing');
    }
    const expected = `${this.context.filesDir}/originals/${captureId}.jpg`;
    if (path !== expected) {
      throw new Error('Capture target is outside private storage');
    }
    return path;
  }

  private async capturePreferences(): Promise<preferences.Preferences> {
    if (this.captureStore === null) {
      this.captureStore = await preferences.getPreferences(this.context, CAPTURE_PREFERENCES);
    }
    return this.captureStore;
  }

  private async hasAnyLocationPermission(): Promise<boolean> {
    return await this.hasPermission(PERMISSION_LOCATION) || await this.hasPermission(PERMISSION_APPROXIMATE);
  }

  private async hasPermission(permission: string): Promise<boolean> {
    const tokenId = this.context.applicationInfo.accessTokenId;
    const status = await abilityAccessCtrl.createAtManager().checkAccessToken(
      tokenId,
      permission as Permissions,
    );
    return status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
  }

  private async ensurePermission(abilityContext: common.UIAbilityContext, permission: string): Promise<number> {
    if (await this.hasPermission(permission)) {
      return PERMISSION_GRANTED;
    }
    const result = await this.requestPermissions(abilityContext, [permission]);
    if (this.anyGranted(result.authResults)) {
      return PERMISSION_GRANTED;
    }
    return this.dialogWasHidden(result) ? PERMISSION_PERMANENTLY_DENIED : PERMISSION_DENIED;
  }

  private anyGranted(authResults: Array<number>): boolean {
    return authResults.some((value: number) => value === 0);
  }

  private dialogWasHidden(result: PermissionAskResult): boolean {
    const shown = result.dialogShownResults;
    return shown !== undefined && shown.length > 0 && shown.every((value: boolean) => !value);
  }

  private async requestPermissions(
    abilityContext: common.UIAbilityContext,
    permissions: Array<string>,
  ): Promise<PermissionAskResult> {
    const permissionList: Array<Permissions> = [];
    for (let index = 0; index < permissions.length; index++) {
      permissionList.push(this.stringAt(permissions, index) as Permissions);
    }
    return await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(
      abilityContext,
      permissionList,
    ) as PermissionAskResult;
  }

  private pathFromUri(uri: string): string {
    return new fileUri.FileUri(uri).path;
  }

  private requireAbilityContext(message: string): common.UIAbilityContext {
    const context = this.ability?.context as common.UIAbilityContext | undefined;
    if (context === undefined) {
      throw new Error(message);
    }
    return context;
  }

  private abilityContextOrApp(): common.UIAbilityContext | common.Context {
    return (this.ability?.context as common.UIAbilityContext | undefined) ?? this.context;
  }

  private assertCaptureId(captureId: string): void {
    if (!SAFE_CAPTURE_ID.test(captureId)) {
      throw new Error('Invalid capture id');
    }
  }

  private hasCaptureContent(path: string): boolean {
    if (!this.pathExists(path)) {
      return false;
    }
    return fs.statSync(path).size > 0;
  }

  private pathExists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (_error) {
      return false;
    }
  }

  private async ensureDir(path: string): Promise<void> {
    if (!this.pathExists(path)) {
      fs.mkdirSync(path, true);
    }
  }

  private packageInfo(): Record<string, Object | null> {
    this.markPackageInfoBridge();
    const info: Record<string, Object | null> = {};
    info['appName'] = 'SiteMark';
    info['packageName'] = 'io.github.wikg1018.sitemark';
    info['version'] = '1.0.8';
    info['buildNumber'] = '23';
    info['buildSignature'] = '';
    info['installerStore'] = null;
    info['installTime'] = null;
    info['updateTime'] = null;
    return info;
  }

  private markPackageInfoBridge(): void {
    try {
      const path = `${this.context.filesDir}/sitemark_package_info.log`;
      const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, 'SITEMARK_PKG_INFO getAll 1.0.8 23\n');
      fs.closeSync(file);
    } catch (_error) {
    }
  }

  private recreateEmptyFile(path: string): void {
    if (this.pathExists(path)) {
      fs.unlinkSync(path);
    }
    this.ensureWritableFile(path);
  }

  private ensureWritableFile(path: string): void {
    const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
    fs.closeSync(file);
  }

  private copyFile(source: string, destination: string): void {
    const input = fs.openSync(source, fs.OpenMode.READ_ONLY);
    const output = fs.openSync(destination, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      const stat = fs.statSync(source);
      const buffer = new ArrayBuffer(stat.size);
      fs.readSync(input.fd, buffer);
      fs.writeSync(output.fd, buffer);
    } finally {
      fs.closeSync(input);
      fs.closeSync(output);
    }
  }

  private async materializeCapture(resultUri: string, target: string): Promise<CameraCaptureResult> {
    if (this.isSandboxCapturePath(resultUri, target) && this.hasCaptureContent(target)) {
      return this.cameraCaptured(target);
    }
    try {
      await this.copyUriToPath(resultUri, target);
    } catch (_copyError) {
      return this.cameraFailed(target);
    }
    if (this.hasCaptureContent(target)) {
      return this.cameraCaptured(target);
    }
    return this.cameraFailed(target);
  }

  private isSandboxCapturePath(uri: string, target: string): boolean {
    if (uri === target) {
      return true;
    }
    if (!uri.startsWith('file://') || this.isMediaLibraryUri(uri)) {
      return false;
    }
    return this.pathFromUri(uri) === target;
  }

  private isMediaLibraryUri(uri: string): boolean {
    return uri.startsWith('file://media/') ||
      uri.startsWith('datashare://') ||
      uri.indexOf('/media/') >= 0;
  }

  private async copyUriToPath(uri: string, destination: string): Promise<void> {
    if (uri === destination) {
      return;
    }
    if (this.isMediaLibraryUri(uri) || !uri.startsWith('file://')) {
      this.copyOpenedUri(uri, destination);
      return;
    }
    const source = this.pathFromUri(uri);
    if (source === destination) {
      return;
    }
    if (source.startsWith('/') && this.pathExists(source)) {
      this.copyFile(source, destination);
      return;
    }
    this.copyOpenedUri(uri, destination);
  }

  private copyOpenedUri(uri: string, destination: string): void {
    const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    const output = fs.openSync(destination, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      const stat = fs.statSync(file.fd);
      const buffer = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buffer);
      fs.writeSync(output.fd, buffer);
    } finally {
      fs.closeSync(file);
      fs.closeSync(output);
    }
  }

  private async inspectImage(path: string): Promise<Record<string, Object | null>> {
    if (!this.hasCaptureContent(path)) {
      throw new Error('image not found');
    }
    const source = image.createImageSource(path);
    try {
      const info = await source.getImageInfo();
      const orientationText = await this.readImageProperty(source, image.PropertyKey.ORIENTATION);
      const latitudeText = await this.readImageProperty(source, image.PropertyKey.GPS_LATITUDE);
      const longitudeText = await this.readImageProperty(source, image.PropertyKey.GPS_LONGITUDE);
      const latitudeRef = await this.readImageProperty(source, image.PropertyKey.GPS_LATITUDE_REF);
      const longitudeRef = await this.readImageProperty(source, image.PropertyKey.GPS_LONGITUDE_REF);
      const swapped = this.swapsDimensions(orientationText);
      const gps = this.parseExifGps(latitudeText, longitudeText, latitudeRef, longitudeRef);
      const result: Record<string, Object | null> = {
        width: swapped ? info.size.height : info.size.width,
        height: swapped ? info.size.width : info.size.height,
        fileSizeBytes: fs.statSync(path).size,
        mimeType: info.mimeType.length > 0 ? info.mimeType : 'image/jpeg',
        latitude: gps.latitude,
        longitude: gps.longitude,
      };
      return result;
    } finally {
      await source.release();
    }
  }

  private async readImageProperty(source: image.ImageSource, key: image.PropertyKey): Promise<string> {
    try {
      return await source.getImageProperty(key);
    } catch (_error) {
      return '';
    }
  }

  private swapsDimensions(orientationText: string): boolean {
    const value = orientationText.trim().toUpperCase();
    if (value.length === 0) {
      return false;
    }
    const numeric = Number.parseInt(value, 10);
    if (!Number.isNaN(numeric)) {
      return numeric === 5 || numeric === 6 || numeric === 7 || numeric === 8;
    }
    return value.indexOf('LEFT') >= 0 || value.indexOf('RIGHT') >= 0;
  }

  private parseExifGps(
    latitudeText: string,
    longitudeText: string,
    latitudeRef: string,
    longitudeRef: string,
  ): GpsPair {
    const empty: GpsPair = {
      latitude: null,
      longitude: null,
    };
    const latitude = this.parseCoordinate(latitudeText);
    const longitude = this.parseCoordinate(longitudeText);
    if (latitude === null || longitude === null) {
      return empty;
    }
    const signedLatitude = this.applyGpsRef(latitude, latitudeRef, true);
    const signedLongitude = this.applyGpsRef(longitude, longitudeRef, false);
    if (signedLatitude === null || signedLongitude === null) {
      return empty;
    }
    if (Math.abs(signedLatitude) > 90 || Math.abs(signedLongitude) > 180) {
      return empty;
    }
    const result: GpsPair = {
      latitude: signedLatitude,
      longitude: signedLongitude,
    };
    return result;
  }

  private applyGpsRef(value: number, refText: string, latitude: boolean): number | null {
    const ref = refText.trim().toUpperCase();
    if (ref.length === 0) {
      return value;
    }
    if (latitude) {
      if (ref === 'N' || ref === 'NORTH') {
        return Math.abs(value);
      }
      if (ref === 'S' || ref === 'SOUTH') {
        return -Math.abs(value);
      }
      return null;
    }
    if (ref === 'E' || ref === 'EAST') {
      return Math.abs(value);
    }
    if (ref === 'W' || ref === 'WEST') {
      return -Math.abs(value);
    }
    return null;
  }

  private parseCoordinate(raw: string): number | null {
    const text = raw.trim();
    if (text.length === 0) {
      return null;
    }
    const parts: Array<string> = [];
    let current = '';
    for (let index = 0; index < text.length; index++) {
      const ch = text.charAt(index);
      if (ch === ',' || ch === ' ') {
        if (current.length > 0) {
          parts.push(current);
          current = '';
        }
      } else {
        current += ch;
      }
    }
    if (current.length > 0) {
      parts.push(current);
    }
    if (parts.length === 0) {
      return null;
    }
    if (parts.length === 1) {
      return this.parseRational(parts[0]);
    }
    const degrees = this.parseRational(parts[0]);
    const minutes = parts.length > 1 ? this.parseRational(parts[1]) : 0;
    const seconds = parts.length > 2 ? this.parseRational(parts[2]) : 0;
    if (degrees === null || minutes === null || seconds === null) {
      return null;
    }
    const sign = degrees < 0 ? -1 : 1;
    return sign * (Math.abs(degrees) + Math.abs(minutes) / 60 + Math.abs(seconds) / 3600);
  }

  private parseRational(raw: string): number | null {
    const text = raw.trim();
    if (text.length === 0) {
      return null;
    }
    const slash = text.indexOf('/');
    if (slash > 0) {
      const numerator = Number.parseFloat(text.substring(0, slash));
      const denominator = Number.parseFloat(text.substring(slash + 1));
      if (Number.isNaN(numerator) || Number.isNaN(denominator) || denominator === 0) {
        return null;
      }
      return numerator / denominator;
    }
    const value = Number.parseFloat(text);
    if (Number.isNaN(value)) {
      return null;
    }
    return value;
  }

  private cameraCaptured(outputPath: string): CameraCaptureResult {
    const result: CameraCaptureResult = {
      outcome: CAMERA_OUTCOME_CAPTURED,
      outputPath: outputPath,
      errorMessage: null,
    };
    return result;
  }

  private cameraCancelled(outputPath: string): CameraCaptureResult {
    const result: CameraCaptureResult = {
      outcome: CAMERA_OUTCOME_CANCELLED,
      outputPath: outputPath,
      errorMessage: null,
    };
    return result;
  }

  private cameraFailed(outputPath: string): CameraCaptureResult {
    const result: CameraCaptureResult = {
      outcome: CAMERA_OUTCOME_FAILED,
      outputPath: outputPath,
      errorMessage: null,
    };
    return result;
  }

  private locationResult(outcome: number): LocationFixResult {
    const result: LocationFixResult = {
      outcome: outcome,
      latitude: null,
      longitude: null,
      accuracyMeters: null,
      address: null,
      errorMessage: null,
    };
    return result;
  }

  private stringAt(values: Array<string>, index: number): string {
    let current = 0;
    for (const value of values) {
      if (current === index) {
        return value;
      }
      current += 1;
    }
    throw new Error(`Missing string at ${index}`);
  }

  private numberAt(values: Array<number>, index: number): number {
    let current = 0;
    for (const value of values) {
      if (current === index) {
        return value;
      }
      current += 1;
    }
    throw new Error(`Missing number at ${index}`);
  }

  private charAt(value: string, index: number): string {
    return value.substring(index, index + 1);
  }

  private resolveAppDirectory(method: string): string {
    if (method === 'getTemporaryDirectory') {
      return this.context.tempDir;
    }
    if (method === 'getApplicationCacheDirectory') {
      return this.context.cacheDir;
    }
    return this.context.filesDir;
  }

  private requiredString(args: Record<string, Object | null | undefined> | null, key: string): string {
    const value = args?.[key];
    if (typeof value !== 'string') {
      throw new Error(`Missing ${key}`);
    }
    return value;
  }

  private optionalString(
    args: Record<string, Object | null | undefined> | null,
    key: string,
  ): string | null {
    const value = args?.[key];
    if (typeof value !== 'string' || value.length === 0) {
      return null;
    }
    return value;
  }

  private boolArg(args: Record<string, Object | null | undefined> | null, key: string): boolean {
    return args?.[key] === true;
  }

  private numberArg(
    args: Record<string, Object | null | undefined> | null,
    key: string,
    fallback: number,
  ): number {
    const value = args?.[key];
    return typeof value === 'number' ? value : fallback;
  }

  private abilityContext(): common.UIAbilityContext {
    const abilityContext = this.ability?.context as common.UIAbilityContext | undefined;
    if (abilityContext === undefined) {
      throw new Error('ohos_not_ready');
    }
    return abilityContext;
  }

  private async requestEnableNotification(): Promise<boolean> {
    if (await notificationManager.isNotificationEnabled()) {
      return true;
    }
    try {
      await notificationManager.requestEnableNotification(this.abilityContext());
      return await notificationManager.isNotificationEnabled();
    } catch (_error) {
      return false;
    }
  }

  private async publishCaptureReady(title: string, text: string, deepLink: string): Promise<void> {
    const abilityContext = this.abilityContext();
    try {
      await notificationManager.addSlot(notificationManager.SlotType.CONTENT_INFORMATION);
    } catch (_slotError) {
    }
    const agentInfo: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: abilityContext.abilityInfo.bundleName,
          abilityName: 'EntryAbility',
          parameters: {
            'sitemarkDeepLink': deepLink,
          },
        },
      ],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: this.notificationId(deepLink),
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
    };
    const agent = await wantAgent.getWantAgent(agentInfo);
    const request: notificationManager.NotificationRequest = {
      id: this.notificationId(deepLink),
      notificationSlotType: notificationManager.SlotType.CONTENT_INFORMATION,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: title,
          text: text,
        },
      },
      wantAgent: agent,
    };
    await notificationManager.publish(request);
  }

  private notificationId(deepLink: string): number {
    let hash = 0;
    let index = 0;
    while (index < deepLink.length) {
      hash = ((hash << 5) - hash + deepLink.charCodeAt(index)) | 0;
      index += 1;
    }
    const id = Math.abs(hash);
    return id === 0 ? 1 : id;
  }
}
