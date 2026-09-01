import connection from '@ohos.net.connection';
import sitemarkNative from 'libsitemark_native.so';
import asset from '@ohos.security.asset';
import hilog from '@ohos.hilog';
import { AppDatabase, NasSyncConfigRecord, NasUploadCounts } from '../../data/database/AppDatabase';

const LOG_DOMAIN: number = 0x5100;
const LOG_TAG: string = 'NasSync';

/** JSON C ABI operation names (see rust/src/ffi/mod.rs). */
export class NasNativeBridge {
  async testConnection(config: NasSyncConfigRecord, password: string): Promise<string | null> {
    const payload: Record<string, Object | null> = {
      protocol: config.protocol,
      host: config.host,
      port: config.port,
      username: config.username,
      password: password,
      root_path: config.rootPath,
      secure_tls: config.secureTls,
      accept_invalid_tls: config.acceptInvalidTls,
      known_sftp_fingerprint: config.knownSftpFingerprint
    };
    try {
      const encoded = JSON.stringify(payload);
      await sitemarkNative.callRaw('nasTestConnection', encoded);
      return null;
    } catch (error) {
      return nasFailureCode((error as Error).message);
    }
  }

  async upload(config: NasSyncConfigRecord, password: string, localPath: string,
    projectKey: string, fileName: string): Promise<string | null> {
    const payload: Record<string, Object | null> = {
      config: {
        protocol: config.protocol,
        host: config.host,
        port: config.port,
        username: config.username,
        password: password,
        root_path: config.rootPath,
        secure_tls: config.secureTls,
        accept_invalid_tls: config.acceptInvalidTls,
        known_sftp_fingerprint: config.knownSftpFingerprint
      },
      project_key: projectKey,
      file_name: fileName,
      local_path: localPath
    };
    try {
      await sitemarkNative.callRaw('nasUpload', JSON.stringify(payload));
      return null;
    } catch (error) {
      return nasFailureCode((error as Error).message);
    }
  }
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

  async read(): Promise<string | null> {
    try {
      const result = await asset.query({
        ALIAS: NasSecretStore.ALIAS,
        RETURN_TYPE: asset.PropertyType.ALL
      } as asset.AssetMap);
      const bytes = result.RESULT as Uint8Array;
      return bytes === undefined ? null : NasSyncService.decodeUtf8(bytes);
    } catch (_) {
      // Missing asset = no stored password.
      return null;
    }
  }

  async write(password: string): Promise<void> {
    try {
      await asset.remove({ ALIAS: NasSecretStore.ALIAS } as asset.AssetMap);
    } catch (_) {
      // First write: nothing to remove.
    }
    await asset.add({
      ALIAS: NasSecretStore.ALIAS,
      DATA: NasSyncService.encodeUtf8(password)
    } as asset.AssetMap);
  }

  async delete(): Promise<void> {
    try {
      await asset.remove({ ALIAS: NasSecretStore.ALIAS } as asset.AssetMap);
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
  private syncing: boolean = false;
  private rerunQueued: boolean = false;

  constructor(private readonly database: AppDatabase) {
  }

  static decodeUtf8(bytes: Uint8Array): string {
    return String.fromCharCode(...bytes);
  }

  static encodeUtf8(value: string): Uint8Array {
    const bytes = new Uint8Array(value.length);
    for (let i = 0; i < value.length; i++) {
      bytes[i] = value.charCodeAt(i) & 0xFF;
    }
    return bytes;
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
      return capabilities.bearType === connection.NetBearType.BEARER_WIFI ||
        capabilities.bearType === connection.NetBearType.BEARER_ETHERNET;
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
    try {
      while (true) {
        const config = await this.database.nasSyncConfig();
        if (!config.enabled) {
          return;
        }
        if (!await this.networkAllows(config.wifiOnly)) {
          return;
        }
        const queue = await this.database.pendingNasUploads();
        if (queue.length === 0) {
          return;
        }
        const rerunBefore = this.rerunQueued;
        this.rerunQueued = false;
        await this.uploadOne(config, queue[0].captureId);
        if (!rerunBefore && !this.rerunQueued) {
          continue;
        }
        return;
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

  private async uploadOne(config: NasSyncConfigRecord, captureId: string): Promise<void> {
    const capture = await this.database.captureById(captureId);
    if (capture === null || capture.status !== 'ready' || capture.photoNumber === null) {
      await this.database.markNasUploadFailed(captureId, 'path_invalid');
      return;
    }
    const project = await this.database.projectById(capture.projectId);
    if (project === null) {
      await this.database.markNasUploadFailed(captureId, 'path_invalid');
      return;
    }
    const password = await this.secrets.read();
    if (password === null || password.length === 0) {
      await this.database.markNasUploadFailed(captureId, 'config_invalid');
      return;
    }
    const failureCode = await this.bridge.upload(config, password,
      capture.renderedPath, sanitizeProjectKey(project.name), `${capture.photoNumber}.jpg`);
    if (failureCode === null) {
      await this.database.markNasUploaded(captureId);
    } else {
      await this.database.markNasUploadFailed(captureId, failureCode);
    }
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
