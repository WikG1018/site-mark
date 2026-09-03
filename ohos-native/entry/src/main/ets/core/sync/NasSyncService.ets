import connection from '@ohos.net.connection';
import sitemarkNative from 'libsitemark_native.so';
import asset from '@ohos.security.asset';
import hilog from '@ohos.hilog';
import util from '@ohos.util';
import { AppDatabase, NasSyncConfigRecord, NasUploadCounts } from '../../data/database/AppDatabase';

const LOG_DOMAIN: number = 0x5100;
const LOG_TAG: string = 'NasSync';

interface NativeResponse<T> {
  ok: boolean;
  value: T | null;
  error: string | null;
}

interface NasTestDetailsValue {
  sftp_fingerprint: string | null;
}

/** Result of a connection probe: a failure category, or the observed host key. */
export class NasTestOutcome {
  readonly failure: string | null;
  readonly sftpFingerprint: string | null;

  constructor(failure: string | null, sftpFingerprint: string | null) {
    this.failure = failure;
    this.sftpFingerprint = sftpFingerprint;
  }
}

/** JSON C ABI payload for nasTestConnection / the nested config on nasUpload. */
class NasConfigPayload {
  protocol: string = '';
  host: string = '';
  port: number | null = null;
  username: string = '';
  password: string = '';
  root_path: string = '';
  secure_tls: boolean = false;
  accept_invalid_tls: boolean = false;
  known_sftp_fingerprint: string | null = null;
}

class NasUploadPayload {
  config: NasConfigPayload = new NasConfigPayload();
  project_key: string = '';
  file_name: string = '';
  local_path: string = '';
}

/**
 * Thin wrapper over the JSON C ABI envelope (see rust/src/ffi/mod.rs):
 * the request is `{operation, payload}` and operation failures come back
 * as `ok:false` with a `nas:{code}` error string — `call()` itself only
 * rejects on transport-level breakage.
 */
export class NasNativeBridge {
  private async call<T>(operation: string, payload: Object): Promise<NativeResponse<T>> {
    const request = `{"operation":${JSON.stringify(operation)},"payload":${JSON.stringify(payload)}}`;
    const encoded = await sitemarkNative.call(request);
    return JSON.parse(encoded) as NativeResponse<T>;
  }

  async testConnection(config: NasSyncConfigRecord, password: string): Promise<NasTestOutcome> {
    const response = await this.call<NasTestDetailsValue>('nasTestConnection', nasConfigPayload(config, password));
    if (!response.ok) {
      return new NasTestOutcome(nasFailureCode(response.error ?? 'protocol_error'), null);
    }
    const details = response.value;
    return new NasTestOutcome(null, details === null ? null : details.sftp_fingerprint);
  }

  async upload(config: NasSyncConfigRecord, password: string, localPath: string,
    projectKey: string, fileName: string): Promise<string | null> {
    const payload = new NasUploadPayload();
    payload.config = nasConfigPayload(config, password);
    payload.project_key = projectKey;
    payload.file_name = fileName;
    payload.local_path = localPath;
    const response = await this.call<Object>('nasUpload', payload);
    if (response.ok) {
      return null;
    }
    return nasFailureCode(response.error ?? 'protocol_error');
  }
}

function nasConfigPayload(config: NasSyncConfigRecord, password: string): NasConfigPayload {
  const payload = new NasConfigPayload();
  payload.protocol = config.protocol;
  payload.host = config.host;
  payload.port = config.port;
  payload.username = config.username;
  payload.password = password;
  payload.root_path = config.rootPath;
  payload.secure_tls = config.secureTls;
  payload.accept_invalid_tls = config.acceptInvalidTls;
  payload.known_sftp_fingerprint = config.knownSftpFingerprint;
  return payload;
}

/**
 * Maps a native error string (`nas:{code}`) into its category suffix, the
 * same vocabulary the Flutter line displays. Anything unrecognized stays a
 * protocol error — raw server strings never reach the UI.
 */
export function nasFailureCode(message: string): string {
  const prefix = 'nas:';
  if (message.startsWith(prefix)) {
    return message.substring(prefix.length);
  }
  return 'protocol_error';
}

/**
 * NAS password storage on the HarmonyOS line: the system asset store keeps
 * the secret out of Preferences, RDB, backups and diagnostics (D-023).
 */
export class NasSecretStore {
  private static readonly ALIAS: string = 'sitemark.nas.password';

  private aliasMap(): asset.AssetMap {
    const attributes: asset.AssetMap = new Map();
    attributes.set(asset.Tag.ALIAS, NasSyncService.encodeUtf8(NasSecretStore.ALIAS));
    return attributes;
  }

  async read(): Promise<string | null> {
    try {
      const query = this.aliasMap();
      query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
      const rows: Array<asset.AssetMap> = await asset.query(query);
      if (rows.length === 0) {
        return null;
      }
      const secret = rows[0].get(asset.Tag.SECRET);
      if (secret === undefined) {
        return null;
      }
      return NasSyncService.decodeUtf8(secret as Uint8Array);
    } catch (_) {
      // Missing asset = no stored password.
      return null;
    }
  }

  async write(password: string): Promise<void> {
    try {
      await asset.remove(this.aliasMap());
    } catch (_) {
      // First write: nothing to remove.
    }
    const attributes = this.aliasMap();
    attributes.set(asset.Tag.SECRET, NasSyncService.encodeUtf8(password));
    attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    await asset.add(attributes);
  }

  async delete(): Promise<void> {
    try {
      await asset.remove(this.aliasMap());
    } catch (_) {
      // Already absent.
    }
  }
}

/**
 * Drains the NAS upload queue for the HarmonyOS line. Observer pattern: the
 * queue is re-synced after each capture commit, on app start and whenever
 * the settings screen saves the configuration — nothing in the capture
 * pipeline knows about NAS.
 */
export class NasSyncService {
  private static readonly instance: NasSyncService | null = null;

  readonly bridge: NasNativeBridge = new NasNativeBridge();
  readonly secrets: NasSecretStore = new NasSecretStore();
  private readonly database: AppDatabase;
  private syncing: boolean = false;
  private rerunQueued: boolean = false;

  constructor(database: AppDatabase) {
    this.database = database;
  }

  static decodeUtf8(bytes: Uint8Array): string {
    return new util.TextDecoder().decodeToString(bytes);
  }

  static encodeUtf8(value: string): Uint8Array {
    return new util.TextEncoder().encodeInto(value);
  }

  /** Wi-Fi gate: uploads over metered links only when wifiOnly is false. */
  async networkAllows(wifiOnly: boolean): Promise<boolean> {
    try {
      const net = await connection.getDefaultNet();
      if (net === null || net.netId === 0) {
        return false;
      }
      if (!wifiOnly) {
        return true;
      }
      const capabilities = await connection.getNetCapabilities(net);
      const types: Array<connection.NetBearType> = capabilities.bearerTypes;
      for (let i = 0; i < types.length; i++) {
        if (types[i] === connection.NetBearType.BEARER_WIFI ||
          types[i] === connection.NetBearType.BEARER_ETHERNET) {
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /**
   * One serial drain cycle. Safe to call from anywhere, any number of
   * times: it returns immediately when sync is disabled, offline, or
   * already running (the run is re-queued instead of dropped).
   */
  async syncNow(): Promise<void> {
    if (this.syncing) {
      this.rerunQueued = true;
      return;
    }
    this.syncing = true;
    const deferredThisCycle = new Set<string>();
    try {
      while (true) {
        const config = await this.database.nasSyncConfig();
        if (!config.enabled) {
          return;
        }
        await this.database.enqueueReadyCapturesForNas();
        if (!await this.networkAllows(config.wifiOnly)) {
          return;
        }
        const queue = await this.database.pendingNasUploads();
        if (queue.length === 0) {
          return;
        }
        // A capture still processing is deferred, not failed; once every
        // queued item deferred this cycle, stop and wait for the next
        // trigger instead of spinning on the same row forever.
        const first = queue[0].captureId;
        if (deferredThisCycle.has(first)) {
          return;
        }
        const progressed = await this.uploadOne(config, first);
        if (!progressed) {
          deferredThisCycle.add(first);
        }
      }
    } catch (error) {
      // The queue is a background observer; failures surface through the
      // recorded per-capture failure codes, never through a crash.
      hilog.error(LOG_DOMAIN, LOG_TAG, 'nas sync cycle failed: %{public}s',
        (error as Error).message);
    } finally {
      this.syncing = false;
    }
    if (this.rerunQueued) {
      this.rerunQueued = false;
      await this.syncNow();
    }
  }

  /**
   * Uploads one capture. Returns false when the row was only deferred
   * (capture not ready yet) — the drain treats that as no progress.
   */
  private async uploadOne(config: NasSyncConfigRecord, captureId: string): Promise<boolean> {
    const capture = await this.database.captureById(captureId);
    if (capture === null) {
      await this.database.markNasUploadFailed(captureId, 'path_invalid');
      return true;
    }
    if (capture.status !== 'ready') {
      // The capture changed while queued; keep the job pending and let
      // the next capture commit re-trigger the drain.
      await this.database.deferNasUpload(captureId);
      return false;
    }
    if (capture.photoNumber === null || capture.photoNumber.length === 0) {
      await this.database.markNasUploadFailed(captureId, 'path_invalid');
      return true;
    }
    const project = await this.database.projectById(capture.projectId);
    if (project === null) {
      await this.database.markNasUploadFailed(captureId, 'path_invalid');
      return true;
    }
    const password = await this.secrets.read();
    if (password === null || password.length === 0) {
      await this.database.markNasUploadFailed(captureId, 'config_invalid');
      return true;
    }
    const failureCode = await this.bridge.upload(config, password,
      capture.renderedPath, sanitizeProjectKey(project.name),
      `${capture.photoNumber}.jpg`);
    if (failureCode === null) {
      await this.database.markNasUploaded(captureId);
    } else {
      await this.database.markNasUploadFailed(captureId, failureCode);
    }
    return true;
  }

  async counts(): Promise<NasUploadCounts> {
    return this.database.countNasUploadStates();
  }

  async retryFailed(): Promise<void> {
    await this.database.resetFailedNasUploads();
    await this.syncNow();
  }
}

/** Mirrors Rust's segment validation for the remote project directory. */
export function sanitizeProjectKey(projectName: string): string {
  const safe = projectName.trim()
    .replace(/[\s~ /\\:*?"<>|\x00-\x1F\x7F\x80-\x9F]+/g, '_')
    .replace(/_+/g, '_')
    .replace(/^[._ ]+|[._ ]+$/g, '');
  return safe.length === 0 ? 'Project' : safe;
}
