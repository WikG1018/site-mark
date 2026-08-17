import { common, Want, abilityAccessCtrl } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { camera, cameraPicker } from '@kit.CameraKit';
import { fileIo as fs, fileUri, picker } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { geoLocationManager } from '@kit.LocationKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { dataSharePredicates, preferences, util } from '@kit.ArkData';
import UIAbility from '@ohos.app.ability.UIAbility';

const CAPTURE_PREFERENCES = 'sitemark_capture_recovery';
const PUBLISH_PREFERENCES = 'sitemark_publish_journal';
const KEY_CAPTURE_ID = 'capture_id';
const KEY_CAPTURE_PATH = 'capture_path';
const KEY_LOCATION_PERMISSION_REQUESTED = 'location_permission_requested';
const SAFE_CAPTURE_ID = /^[A-Za-z0-9][A-Za-z0-9_-]{0,95}$/;
const FORBIDDEN_NAME = /[\p{Cc}\p{Z}\uFEFF/\\:*?"<>|]/u;

const CAMERA_OUTCOME_CAPTURED = 0;
const CAMERA_OUTCOME_CANCELLED = 1;
const CAMERA_OUTCOME_FAILED = 2;
const ARCHIVE_SAVED = 0;
const ARCHIVE_CANCELLED = 1;
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

export default class OhosSystemHost {
  private context: common.Context;
  private ability: UIAbility | null = null;
  private captureStore: preferences.Preferences | null = null;
  private publishStore: preferences.Preferences | null = null;
  private cameraBusy: boolean = false;
  private archiveBusy: boolean = false;
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
      case 'inspectImage':
        return await this.inspectImage(this.requiredString(args, 'path'));
      case 'requestCurrentLocation':
        return await this.requestCurrentLocation(this.numberArg(args, 'timeoutMillis', 10000));
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
      case 'saveArchive':
        return await this.saveArchive(
          this.requiredString(args, 'sourcePath'),
          this.requiredString(args, 'suggestedName'),
        );
      case 'deletePublishedImage':
        await this.deletePublishedImage(this.requiredString(args, 'contentUri'));
        return null;
      case 'detectGalleryAccess':
        return await this.detectGalleryAccess();
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

  private async launchCamera(captureId: string): Promise<Record<string, Object | null>> {
    if (this.cameraBusy) {
      throw new Error('A camera capture is already active');
    }
    const abilityContext = this.requireAbilityContext('System camera requires a foreground ability');
    const target = await this.preparedTarget(captureId);
    const cameraState = await this.ensurePermission(abilityContext, PERMISSION_CAMERA);
    if (cameraState !== PERMISSION_GRANTED) {
      return {
        outcome: CAMERA_OUTCOME_FAILED,
        outputPath: target,
        errorMessage: 'Camera permission is denied',
      };
    }
    this.cameraBusy = true;
    try {
      this.ensureWritableFile(target);
      const saveUri = fileUri.getUriFromPath(target);
      let captured = false;
      try {
        const pickerResult = await cameraPicker.pick(
          abilityContext,
          [cameraPicker.PickerMediaType.PHOTO],
          {
            cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK,
            saveUri: saveUri,
          },
        );
        captured = pickerResult !== undefined && pickerResult.resultCode === 0;
        if (!this.hasCaptureContent(target) && pickerResult?.resultUri) {
          await this.copyUriToPath(pickerResult.resultUri, target);
        }
      } catch (_pickerError) {
        const want: Want = {
          action: 'ohos.want.action.imageCapture',
          parameters: {},
        };
        want.parameters![wantConstantParamStream()] = saveUri;
        const result = await abilityContext.startAbilityForResult(want);
        captured = result.resultCode === 0;
      }
      if (captured && this.hasCaptureContent(target)) {
        return {
          outcome: CAMERA_OUTCOME_CAPTURED,
          outputPath: target,
          errorMessage: null,
        };
      }
      await this.finishCameraCapture(captureId, false);
      return {
        outcome: CAMERA_OUTCOME_CANCELLED,
        outputPath: target,
        errorMessage: null,
      };
    } catch (error) {
      return {
        outcome: CAMERA_OUTCOME_FAILED,
        outputPath: target,
        errorMessage: this.errorMessage(error),
      };
    } finally {
      this.cameraBusy = false;
    }
  }

  private async recoverCameraCapture(): Promise<Record<string, Object> | null> {
    const store = await this.capturePreferences();
    const captureId = await store.get(KEY_CAPTURE_ID, '') as string;
    const outputPath = await store.get(KEY_CAPTURE_PATH, '') as string;
    if (captureId.length === 0 || outputPath.length === 0) {
      return null;
    }
    return {
      captureId: captureId,
      outputPath: outputPath,
      hasContent: this.hasCaptureContent(outputPath),
    };
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
    const result = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(
      abilityContext,
      [PERMISSION_APPROXIMATE, PERMISSION_LOCATION],
    );
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
    const want: Want = {
      bundleName: 'com.huawei.hmos.settings',
      abilityName: 'com.huawei.hmos.settings.MainAbility',
      uri: 'application_info_entry',
      parameters: {
        pushParams: context.applicationInfo.name,
      },
    };
    await context.startAbility(want);
  }

  private async inspectImage(path: string): Promise<Record<string, Object | null>> {
    const file = this.validatedPrivateFile(path);
    const stat = fs.statSync(file);
    let width = 0;
    let height = 0;
    let latitude: number | null = null;
    let longitude: number | null = null;
    const source = image.createImageSource(file);
    try {
      const info = await source.getImageInfo();
      width = info.size.width;
      height = info.size.height;
      try {
        const lat = await source.getImageProperty(image.PropertyKey.GPS_LATITUDE);
        const lon = await source.getImageProperty(image.PropertyKey.GPS_LONGITUDE);
        latitude = this.parseCoordinate(lat);
        longitude = this.parseCoordinate(lon);
      } catch (_exif) {
        latitude = null;
        longitude = null;
      }
    } finally {
      await source.release();
    }
    return {
      width: width,
      height: height,
      fileSizeBytes: stat.size,
      mimeType: 'image/jpeg',
      latitude: latitude,
      longitude: longitude,
    };
  }

  private async requestCurrentLocation(timeoutMillis: number): Promise<Record<string, Object | null>> {
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
        locatingPriority: (await this.hasPermission(PERMISSION_LOCATION))
          ? geoLocationManager.LocatingPriority.PRIORITY_ACCURACY
          : geoLocationManager.LocatingPriority.PRIORITY_LOCATING_SPEED,
      };
      try {
        const location = await geoLocationManager.getCurrentLocation(request);
        return {
          outcome: (await this.hasPermission(PERMISSION_LOCATION)) ? LOCATION_PRECISE : LOCATION_APPROXIMATE,
          latitude: location.latitude,
          longitude: location.longitude,
          accuracyMeters: location.accuracy,
          address: null,
          errorMessage: null,
        };
      } catch (error) {
        const code = (error as BusinessError).code;
        if (code === 3301100) {
          return this.locationResult(LOCATION_SERVICES_DISABLED);
        }
        if (code === 3301200 || code === 3301800) {
          return this.locationResult(LOCATION_TIMEOUT);
        }
        if (code === 201) {
          return this.locationResult(LOCATION_PERMISSION_DENIED, this.errorMessage(error));
        }
        return this.locationResult(LOCATION_UNAVAILABLE, this.errorMessage(error));
      }
    } finally {
      this.locationBusy = false;
    }
  }

  private async publishJpeg(
    sourcePath: string,
    displayName: string,
    captureId: string,
    publishedUri: string | null,
  ): Promise<Record<string, Object>> {
    if (captureId.trim().length === 0) {
      throw new Error('Publish requires a capture ID');
    }
    const source = this.validatedPrivateFile(sourcePath);
    const safeName = this.normalizedJpegName(displayName);
    const leftover = await this.peekJournal(captureId);
    const superseded: string[] = [];
    this.addUnique(superseded, publishedUri);
    if (leftover !== null) {
      this.addUnique(superseded, leftover.contentUri);
      leftover.supersededUris.forEach((uri: string) => this.addUnique(superseded, uri));
    }
    const created = await this.writePublishedImage(source, safeName);
    const journaled = await this.recordJournal(captureId, created, superseded);
    if (!journaled) {
      try {
        await this.deletePublishedImage(created);
      } catch (_cleanup) {
      }
      throw new Error('Unable to persist the publish journal');
    }
    return {
      contentUri: created,
      supersededUris: superseded,
    };
  }

  private async recoverPublishJournals(): Promise<Object[]> {
    const store = await this.publishPreferences();
    const all = await store.getAll();
    const result: Object[] = [];
    const keys = Object.keys(all);
    for (const key of keys) {
      if (!key.endsWith('.exists')) {
        continue;
      }
      const prefix = `${key.substring(0, key.length - '.exists'.length)}.`;
      const contentUri = all[`${prefix}newUri`] as string | undefined;
      if (contentUri === undefined || contentUri.length === 0) {
        continue;
      }
      const captureId = this.decodeCaptureId(prefix);
      if (captureId === null) {
        continue;
      }
      const staleCount = (all[`${prefix}staleCount`] as number | undefined) ?? 0;
      const staleUris: string[] = [];
      for (let index = 0; index < staleCount; index++) {
        const stale = all[`${prefix}stale.${index}`] as string | undefined;
        if (stale !== undefined && stale.length > 0) {
          staleUris.push(stale);
        }
      }
      result.push({
        captureId: captureId,
        contentUri: contentUri,
        supersededUris: staleUris,
      });
    }
    return result;
  }

  private async clearPublishJournal(captureId: string, expectedContentUri: string): Promise<void> {
    const store = await this.publishPreferences();
    const prefix = this.journalPrefix(captureId);
    const exists = await store.has(`${prefix}exists`);
    if (!exists) {
      return;
    }
    const current = await store.get(`${prefix}newUri`, '') as string;
    if (current.length > 0 && current !== expectedContentUri) {
      return;
    }
    const staleCount = await store.get(`${prefix}staleCount`, 0) as number;
    await store.delete(`${prefix}exists`);
    await store.delete(`${prefix}newUri`);
    await store.delete(`${prefix}staleCount`);
    for (let index = 0; index < staleCount; index++) {
      await store.delete(`${prefix}stale.${index}`);
    }
    await store.flush();
  }

  private async saveArchive(sourcePath: string, suggestedName: string): Promise<number> {
    if (this.archiveBusy) {
      throw new Error('A backup save is already active');
    }
    const abilityContext = this.requireAbilityContext('Saving a backup requires a foreground ability');
    const source = this.validatedPrivateFile(sourcePath);
    const safeName = this.normalizeArchiveName(suggestedName);
    this.archiveBusy = true;
    try {
      const documentPicker = new picker.DocumentViewPicker(abilityContext);
      const saveOptions = new picker.DocumentSaveOptions();
      saveOptions.newFileNames = [safeName];
      saveOptions.fileSuffixChoices = ['.zip'];
      const uris = await documentPicker.save(saveOptions);
      if (uris === undefined || uris.length === 0) {
        return ARCHIVE_CANCELLED;
      }
      await this.copyPathToUri(source, uris[0]);
      return ARCHIVE_SAVED;
    } catch (error) {
      if ((error as BusinessError).code === 13900002) {
        return ARCHIVE_CANCELLED;
      }
      throw error;
    } finally {
      this.archiveBusy = false;
    }
  }

  private async deletePublishedImage(contentUri: string): Promise<void> {
    if (contentUri.startsWith('file://') || contentUri.startsWith('/')) {
      const path = contentUri.startsWith('file://') ? fileUri.getPathFromUriSync(contentUri) : contentUri;
      if (this.pathExists(path)) {
        this.validatedPrivateFile(path);
        fs.unlinkSync(path);
      }
      return;
    }
    try {
      const helper = photoAccessHelper.getPhotoAccessHelper(this.context);
      const predicates = new dataSharePredicates.DataSharePredicates();
      predicates.equalTo(photoAccessHelper.PhotoKeys.URI, contentUri);
      const fetch = await helper.getAssets({
        fetchColumns: [],
        predicates: predicates,
      });
      const first = await fetch.getFirstObject();
      fetch.close();
      if (first === undefined) {
        return;
      }
      await helper.deleteAssets(
        this.requireAbilityContext('Deleting a gallery photo requires a foreground ability'),
        [contentUri],
      );
    } catch (_error) {
      return;
    }
  }

  private async detectGalleryAccess(): Promise<string> {
    if (await this.hasPermission(PERMISSION_READ_MEDIA) && await this.hasPermission(PERMISSION_WRITE_MEDIA)) {
      return 'acl';
    }
    const abilityContext = this.ability?.context as common.UIAbilityContext | undefined;
    if (abilityContext === undefined) {
      return 'pickerFallback';
    }
    try {
      const result = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(
        abilityContext,
        [PERMISSION_READ_MEDIA, PERMISSION_WRITE_MEDIA],
      );
      if (this.allGranted(result.authResults)) {
        return 'acl';
      }
    } catch (_error) {
    }
    return 'pickerFallback';
  }

  private async writePublishedImage(sourcePath: string, displayName: string): Promise<string> {
    if (await this.hasPermission(PERMISSION_WRITE_MEDIA) || await this.requestGalleryWrite()) {
      try {
        const helper = photoAccessHelper.getPhotoAccessHelper(this.context);
        const createdUri = await helper.createAsset(photoAccessHelper.PhotoType.IMAGE, 'jpg', {
          title: displayName.replace(/\.jpe?g$/i, ''),
        });
        await this.copyPathToUri(sourcePath, createdUri);
        return createdUri;
      } catch (_error) {
      }
    }
    const directory = `${this.context.filesDir}/published`;
    await this.ensureDir(directory);
    const target = `${directory}/${displayName}`;
    if (this.pathExists(target)) {
      fs.unlinkSync(target);
    }
    this.copyFile(sourcePath, target);
    return fileUri.getUriFromPath(target);
  }

  private async requestGalleryWrite(): Promise<boolean> {
    const abilityContext = this.ability?.context as common.UIAbilityContext | undefined;
    if (abilityContext === undefined) {
      return false;
    }
    try {
      const result = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(
        abilityContext,
        [PERMISSION_READ_MEDIA, PERMISSION_WRITE_MEDIA],
      );
      return this.allGranted(result.authResults);
    } catch (_error) {
      return false;
    }
  }

  private async peekJournal(captureId: string): Promise<JournalEntry | null> {
    const store = await this.publishPreferences();
    const prefix = this.journalPrefix(captureId);
    if (!(await store.has(`${prefix}exists`))) {
      return null;
    }
    const contentUri = await store.get(`${prefix}newUri`, '') as string;
    if (contentUri.length === 0) {
      return null;
    }
    const staleCount = await store.get(`${prefix}staleCount`, 0) as number;
    const supersededUris: string[] = [];
    for (let index = 0; index < staleCount; index++) {
      const stale = await store.get(`${prefix}stale.${index}`, '') as string;
      if (stale.length > 0) {
        supersededUris.push(stale);
      }
    }
    return { contentUri: contentUri, supersededUris: supersededUris };
  }

  private async recordJournal(captureId: string, contentUri: string, supersededUris: string[]): Promise<boolean> {
    try {
      const store = await this.publishPreferences();
      const prefix = this.journalPrefix(captureId);
      const previousCount = await store.get(`${prefix}staleCount`, 0) as number;
      await store.put(`${prefix}newUri`, contentUri);
      await store.put(`${prefix}staleCount`, supersededUris.length);
      await store.put(`${prefix}exists`, true);
      for (let index = 0; index < supersededUris.length; index++) {
        await store.put(`${prefix}stale.${index}`, supersededUris[index]);
      }
      for (let index = supersededUris.length; index < previousCount; index++) {
        await store.delete(`${prefix}stale.${index}`);
      }
      await store.flush();
      return true;
    } catch (_error) {
      return false;
    }
  }

  private journalPrefix(captureId: string): string {
    const helper = new util.Base64Helper();
    const encoded = helper.encodeToStringSync(new util.TextEncoder().encodeInto(captureId))
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=+$/g, '');
    return `journal.${encoded}.`;
  }

  private decodeCaptureId(prefix: string): string | null {
    if (!prefix.startsWith('journal.') || !prefix.endsWith('.')) {
      return null;
    }
    const encoded = prefix.substring('journal.'.length, prefix.length - 1)
      .replace(/-/g, '+')
      .replace(/_/g, '/');
    if (encoded.length === 0) {
      return null;
    }
    try {
      const helper = new util.Base64Helper();
      const padded = encoded + '==='.substring((encoded.length + 3) % 4);
      return helper.decodeToStringSync(padded);
    } catch (_error) {
      return null;
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

  private async publishPreferences(): Promise<preferences.Preferences> {
    if (this.publishStore === null) {
      this.publishStore = await preferences.getPreferences(this.context, PUBLISH_PREFERENCES);
    }
    return this.publishStore;
  }

  private async hasAnyLocationPermission(): Promise<boolean> {
    return await this.hasPermission(PERMISSION_LOCATION) || await this.hasPermission(PERMISSION_APPROXIMATE);
  }

  private async hasPermission(permission: string): Promise<boolean> {
    const tokenId = this.context.applicationInfo.accessTokenId;
    const status = await abilityAccessCtrl.createAtManager().checkAccessToken(tokenId, permission);
    return status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
  }

  private async ensurePermission(abilityContext: common.UIAbilityContext, permission: string): Promise<number> {
    if (await this.hasPermission(permission)) {
      return PERMISSION_GRANTED;
    }
    const result = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(
      abilityContext,
      [permission],
    );
    if (this.anyGranted(result.authResults)) {
      return PERMISSION_GRANTED;
    }
    return this.dialogWasHidden(result) ? PERMISSION_PERMANENTLY_DENIED : PERMISSION_DENIED;
  }

  private anyGranted(authResults: Array<number>): boolean {
    return authResults.some((value: number) => value === 0);
  }

  private allGranted(authResults: Array<number>): boolean {
    return authResults.length > 0 && authResults.every((value: number) => value === 0);
  }

  private dialogWasHidden(result: abilityAccessCtrl.PermissionRequestResult): boolean {
    const shown = result.dialogShownResults;
    return shown !== undefined && shown.length > 0 && shown.every((value: boolean) => !value);
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

  private validatedPrivateFile(path: string): string {
    const filesDir = this.context.filesDir;
    if (!path.startsWith(`${filesDir}/`) && path !== filesDir) {
      throw new Error('Source image must be in app-private storage');
    }
    if (!this.pathExists(path) || fs.statSync(path).size <= 0) {
      throw new Error('Source image is empty or missing');
    }
    return path;
  }

  private normalizedJpegName(displayName: string): string {
    let base = displayName;
    if (base.toLowerCase().endsWith('.jpeg')) {
      base = base.substring(0, base.length - 5);
    } else if (base.toLowerCase().endsWith('.jpg')) {
      base = base.substring(0, base.length - 4);
    }
    if (base.length === 0 || FORBIDDEN_NAME.test(base)) {
      throw new Error('Invalid published image name');
    }
    return `${base}.jpg`;
  }

  private normalizeArchiveName(suggestedName: string): string {
    let name = suggestedName.trim();
    if (name.length === 0 || name.includes('/') || name.includes('\\')) {
      throw new Error('Invalid backup name');
    }
    if (!name.toLowerCase().endsWith('.zip')) {
      name = `${name}.zip`;
    }
    return name;
  }

  private async ensureDir(path: string): Promise<void> {
    if (!this.pathExists(path)) {
      fs.mkdirSync(path, true);
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

  private async copyUriToPath(uri: string, destination: string): Promise<void> {
    const source = uri.startsWith('file://') ? fileUri.getPathFromUriSync(uri) : uri;
    if (source.startsWith('/')) {
      this.copyFile(source, destination);
      return;
    }
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

  private async copyPathToUri(source: string, uri: string): Promise<void> {
    if (uri.startsWith('file://') || uri.startsWith('/')) {
      const destination = uri.startsWith('file://') ? fileUri.getPathFromUriSync(uri) : uri;
      this.copyFile(source, destination);
      return;
    }
    const input = fs.openSync(source, fs.OpenMode.READ_ONLY);
    const output = fs.openSync(uri, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
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

  private parseCoordinate(value: string | image.PropertyKey | undefined): number | null {
    if (typeof value !== 'string' || value.length === 0) {
      return null;
    }
    const parsed = Number.parseFloat(value);
    return Number.isFinite(parsed) ? parsed : null;
  }

  private locationResult(outcome: number, errorMessage: string | null = null): Record<string, Object | null> {
    return {
      outcome: outcome,
      latitude: null,
      longitude: null,
      accuracyMeters: null,
      address: null,
      errorMessage: errorMessage,
    };
  }

  private addUnique(values: string[], value: string | null): void {
    if (value !== null && value.length > 0 && values.indexOf(value) < 0) {
      values.push(value);
    }
  }

  private requiredString(args: Record<string, Object | null | undefined> | null, key: string): string {
    const value = args?.[key];
    if (typeof value !== 'string') {
      throw new Error(`Missing ${key}`);
    }
    return value;
  }

  private optionalString(args: Record<string, Object | null | undefined> | null, key: string): string | null {
    const value = args?.[key];
    return typeof value === 'string' && value.length > 0 ? value : null;
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

  private errorMessage(error: Object): string {
    if (error instanceof Error) {
      return error.message;
    }
    return `${error}`;
  }
}

interface JournalEntry {
  contentUri: string;
  supersededUris: string[];
}

function wantConstantParamStream(): string {
  return 'ability.params.stream';
}
