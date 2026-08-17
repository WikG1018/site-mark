import { common, Want, abilityAccessCtrl } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { camera, cameraPicker } from '@kit.CameraKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { geoLocationManager } from '@kit.LocationKit';
import { preferences } from '@kit.ArkData';
import UIAbility from '@ohos.app.ability.UIAbility';

const CAPTURE_PREFERENCES = 'sitemark_capture_recovery';
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

export default class OhosSystemHost {
  private context: common.Context;
  private ability: UIAbility | null = null;
  private captureStore: preferences.Preferences | null = null;
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
      case 'inspectImage':
      case 'publishJpeg':
      case 'recoverPublishJournals':
      case 'clearPublishJournal':
      case 'saveArchive':
      case 'deletePublishedImage':
        throw new Error('ohos_not_ready');
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
      const saveUri = fileUri.getUriFromPath(target);
      let launched = false;
      let userCancelled = false;
      try {
        const pickerResult = await cameraPicker.pick(
          abilityContext,
          [cameraPicker.PickerMediaType.PHOTO],
          {
            cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK,
            saveUri: saveUri,
          },
        );
        launched = true;
        if (!this.hasCaptureContent(target) && pickerResult?.resultUri) {
          await this.copyUriToPath(pickerResult.resultUri, target);
        }
        if (this.hasCaptureContent(target)) {
          return this.cameraCaptured(target);
        }
        userCancelled = pickerResult === undefined || pickerResult.resultCode !== 0;
      } catch (_pickerError) {
        try {
          const want: Want = {
            action: 'ohos.want.action.imageCapture',
            parameters: {},
          };
          want.parameters![wantConstantParamStream()] = saveUri;
          const result = await abilityContext.startAbilityForResult(want);
          launched = true;
          if (this.hasCaptureContent(target)) {
            return this.cameraCaptured(target);
          }
          userCancelled = result.resultCode !== 0;
        } catch (_abilityError) {
          return this.cameraFailed(target);
        }
      }
      if (!launched) {
        return this.cameraFailed(target);
      }
      if (userCancelled || !this.hasCaptureContent(target)) {
        return this.cameraCancelled(target);
      }
      return this.cameraFailed(target);
    } catch (_error) {
      return this.cameraFailed(target);
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

  private cameraCaptured(outputPath: string): Record<string, Object | null> {
    return {
      outcome: CAMERA_OUTCOME_CAPTURED,
      outputPath: outputPath,
      errorMessage: null,
    };
  }

  private cameraCancelled(outputPath: string): Record<string, Object | null> {
    return {
      outcome: CAMERA_OUTCOME_CANCELLED,
      outputPath: outputPath,
      errorMessage: null,
    };
  }

  private cameraFailed(outputPath: string): Record<string, Object | null> {
    return {
      outcome: CAMERA_OUTCOME_FAILED,
      outputPath: outputPath,
      errorMessage: null,
    };
  }

  private locationResult(outcome: number): Record<string, Object | null> {
    return {
      outcome: outcome,
      latitude: null,
      longitude: null,
      accuracyMeters: null,
      address: null,
      errorMessage: null,
    };
  }

  private requiredString(args: Record<string, Object | null | undefined> | null, key: string): string {
    const value = args?.[key];
    if (typeof value !== 'string') {
      throw new Error(`Missing ${key}`);
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
}

function wantConstantParamStream(): string {
  return 'ability.params.stream';
}
