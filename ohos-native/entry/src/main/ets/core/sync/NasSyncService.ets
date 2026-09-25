import connection from '@ohos.net.connection';
import sitemarkNative from 'libsitemark_native.so';
import asset from '@ohos.security.asset';
import hilog from '@ohos.hilog';
import util from '@ohos.util';
import { AppDatabase, NasSyncConfigRecord, NasUploadCounts } from '../../data/database/AppDatabase';
import { CaptureRecord } from '../../domain/Models';
import { NasImportCandidateGroup, NasRemoteFileEntry, NasTwoWayPolicy } from './NasTwoWayPolicy';

const LOG_DOMAIN: number = 0x5100;
const LOG_TAG: string = 'NasSync';

interface NativeResponse<T> {
  ok: boolean;
  value: T | null;
  error: string | null;
}

interface NasListValue {
  project_key: string;
  file_name: string;
}

/** nasList outcome: a failure category, or the remote {project, file} rows. */
export class NasListOutcome {
  readonly failure: string | null;
  readonly entries: NasRemoteFileEntry[];

  constructor(failure: string | null, entries: NasRemoteFileEntry[]) {
    this.failure = failure;
    this.entries = entries;
  }
}

/** One import-preview group: policy candidates plus the local project match. */
export class NasImportPreviewGroup {
  readonly projectKey: string;
  readonly photoNumbers: string[];
  readonly existsLocally: boolean;

  constructor(projectKey: string, photoNumbers: string[], existsLocally: boolean) {
    this.projectKey = projectKey;
    this.photoNumbers = photoNumbers;
    this.existsLocally = existsLocally;
  }
}

export class NasImportPreviewResult {
  readonly failure: string | null;
  readonly groups: NasImportPreviewGroup[];

  constructor(failure: string | null, groups: NasImportPreviewGroup[]) {
    this.failure = failure;
    this.groups = groups;
  }
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

  /** Two-way preview input: the remote {project, file} rows (H5). */
  async list(config: NasSyncConfigRecord, password: string): Promise<NasListOutcome> {
    const response = await this.call<NasListValue[]>('nasList', nasConfigPayload(config, password));
    if (!response.ok) {
      return new NasListOutcome(nasFailureCode(response.error ?? 'protocol_error'), []);
    }
    const entries: NasRemoteFileEntry[] = [];
    const rows = response.value ?? [];
    for (let i = 0; i < rows.length; i += 1) {
      entries.push({ projectKey: rows[i].project_key, fileName: rows[i].file_name });
    }
    return new NasListOutcome(null, entries);
  }

  /** Best-effort remote delete of one uploaded JPEG (H5). */
  async delete(config: NasSyncConfigRecord, password: string, projectKey: string,
    fileName: string): Promise<string | null> {
    const payload = new NasUploadPayload();
    payload.config = nasConfigPayload(config, password);
    payload.project_key = projectKey;
    payload.file_name = fileName;
    payload.local_path = '';
    const response = await this.call<Object>('nasDelete', payload);
    if (response.ok) {
      return null;
    }
    return nasFailureCode(response.error ?? 'protocol_error');
  }

  /** Two-way import: fetch one remote JPEG into the private renders dir (H5). */
  async download(config: NasSyncConfigRecord, password: string, projectKey: string,
    fileName: string, localPath: string): Promise<string | null> {
    const payload = new NasUploadPayload();
    payload.config = nasConfigPayload(config, password);
    payload.project_key = projectKey;
    payload.file_name = fileName;
    payload.local_path = localPath;
    const response = await this.call<Object>('nasDownload', payload);
    if (response.ok) {
      return null;
    }
    return nasFailureCode(response.error ?? 'protocol_error');
  }

  /** SHA-256 of a local file (import bookkeeping, same as Dart). */
  async sha256(localPath: string): Promise<string> {
    const request = new PathPayload();
    request.path = localPath;
    const response = await this.call<string>('sha256', request);
    if (!response.ok || response.value === null) {
      throw new Error('local_io');
    }
    return response.value;
  }
}

class PathPayload {
  path: string = '';
}

function nasConfigPayload(config: NasSyncConfigRecord, password: string): NasConfigPayload {
  const payload = new NasConfigPayload();
  payload.protocol = config.protocol;
  payload.host = config.host;
  payload.port = config.port;
  payload.username = config.username;
  payload.password = password;
  payload.root_path = config.rootPath;
  payload.secure_tls = config.protocol === 'webdav' ? false : config.secureTls;
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
  private readonly filesDir: string;
  private syncing: boolean = false;
  private rerunQueued: boolean = false;
  private netConnection: connection.NetConnection | null = null;
  private countsListeners: Array<(counts: NasUploadCounts) => void> = [];

  constructor(database: AppDatabase, filesDir: string) {
    this.database = database;
    this.filesDir = filesDir;
  }

  /**
   * Subscribe to default-net availability and capability flips so a
   * wifi-only queue parked on mobile resumes when Wi-Fi returns.
   */
  start(): void {
    if (this.netConnection !== null) {
      return;
    }
    const netConnection = connection.createNetConnection();
    this.netConnection = netConnection;
    netConnection.on('netAvailable', (): void => {
      this.syncNow();
    });
    netConnection.on('netCapabilitiesChange', (): void => {
      this.syncNow();
    });
    netConnection.on('netLost', (): void => {
      this.syncNow();
    });
    netConnection.register((err: Object) => {
      if (err) {
        hilog.error(LOG_DOMAIN, LOG_TAG, 'nas net watch failed');
      }
    });
  }

  addCountsListener(listener: (counts: NasUploadCounts) => void): void {
    this.countsListeners.push(listener);
  }

  removeCountsListener(listener: (counts: NasUploadCounts) => void): void {
    const next: Array<(counts: NasUploadCounts) => void> = [];
    for (let i = 0; i < this.countsListeners.length; i++) {
      if (this.countsListeners[i] !== listener) {
        next.push(this.countsListeners[i]);
      }
    }
    this.countsListeners = next;
  }

  private async notifyCounts(): Promise<void> {
    if (this.countsListeners.length === 0) {
      return;
    }
    const counts = await this.counts();
    for (let i = 0; i < this.countsListeners.length; i++) {
      this.countsListeners[i](counts);
    }
  }

  static decodeUtf8(bytes: Uint8Array): string {
    return util.TextDecoder.create('utf-8').decodeToString(bytes);
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
          break;
        }
        await this.database.enqueueReadyCapturesForNas();
        if (!await this.networkAllows(config.wifiOnly)) {
          break;
        }
        const queue = await this.database.pendingNasUploads();
        if (queue.length === 0) {
          break;
        }
        // A capture still processing is deferred, not failed; once every
        // queued item deferred this cycle, stop and wait for the next
        // trigger instead of spinning on the same row forever.
        const first = queue[0].captureId;
        if (deferredThisCycle.has(first)) {
          break;
        }
        const progressed = await this.uploadOne(config, first);
        if (!progressed) {
          deferredThisCycle.add(first);
        }
        await this.notifyCounts();
      }
    } catch (error) {
      // The queue is a background observer; failures surface through the
      // recorded per-capture failure codes, never through a crash.
      hilog.error(LOG_DOMAIN, LOG_TAG, 'nas sync cycle failed: %{public}s',
        (error as Error).message);
    } finally {
      this.syncing = false;
      await this.notifyCounts();
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

  /// Two-way gates shared by preview/import: enabled + two_way + stored
  /// password, mirroring Dart's _twoWayCredentials. Deliberately NO network
  /// check here — an offline run must surface the native call's failure, not
  /// masquerade as "nothing to restore".
  private async twoWayCredentials(): Promise<NasSyncConfigRecord | null> {
    const config = await this.database.nasSyncConfig();
    if (!config.enabled || !NasTwoWayPolicy.isTwoWay(config.syncMode)) {
      return null;
    }
    const password = await this.secrets.read();
    if (password === null || password.length === 0) {
      return null;
    }
    return config;
  }

  /** Read-only import preview (H5). Nothing is written; the settings screen
   * shows the groups and the user picks what to import. */
  async previewImport(): Promise<NasImportPreviewResult> {
    const config = await this.twoWayCredentials();
    if (config === null) {
      return new NasImportPreviewResult(null, []);
    }
    const password = await this.secrets.read() ?? '';
    const listed = await this.bridge.list(config, password);
    if (listed.failure !== null) {
      return new NasImportPreviewResult(listed.failure, []);
    }
    const localIndex = await this.localPhotoIndex();
    const candidates: NasImportCandidateGroup[] =
      NasTwoWayPolicy.importCandidates(listed.entries, localIndex);
    const groups: NasImportPreviewGroup[] = [];
    for (let i = 0; i < candidates.length; i += 1) {
      groups.push(new NasImportPreviewGroup(candidates[i].projectKey,
        candidates[i].photoNumbers, localIndex.has(candidates[i].projectKey)));
    }
    return new NasImportPreviewResult(null, groups);
  }

  /** Local photo numbers keyed by sanitized project key (import matching). */
  private async localPhotoIndex(): Promise<Map<string, Set<string>>> {
    const rows = await this.database.capturePhotoNumbersByProjectName();
    const index = new Map<string, Set<string>>();
    for (let i = 0; i < rows.length; i += 1) {
      const key = sanitizeProjectKey(rows[i].projectName);
      let numbers = index.get(key);
      if (numbers === undefined) {
        numbers = new Set<string>();
        index.set(key, numbers);
      }
      numbers.add(rows[i].photoNumber);
    }
    return index;
  }

  /** Best-effort remote delete after a local delete (H5, Dart parity):
   * any failure is swallowed so the local delete never depends on the NAS. */
  async deleteRemoteForCapture(capture: CaptureRecord): Promise<void> {
    try {
      if (capture.photoNumber.length === 0) {
        return;
      }
      const config = await this.database.nasSyncConfig();
      if (!config.enabled || !NasTwoWayPolicy.isTwoWay(config.syncMode)) {
        return;
      }
      const password = await this.secrets.read();
      if (password === null || password.length === 0) {
        return;
      }
      await this.bridge.delete(config, password, sanitizeProjectKey(capture.projectName),
        `${capture.photoNumber}.jpg`);
    } catch (_) {
      // Remote cleanup is best-effort by contract.
    }
  }

  /** Imports the selected preview groups (H5, Dart importNasProjects
   * parity). Creates missing local projects named after the NAS key; a
   * download or hash failure aborts the run with a `nas:{code}` error —
   * already-imported photos stay, exactly like Dart. Returns the count. */
  async importProjects(selected: NasImportPreviewGroup[]): Promise<number> {
    if (selected.length === 0) {
      return 0;
    }
    const config = await this.twoWayCredentials();
    if (config === null) {
      return 0;
    }
    const password = await this.secrets.read() ?? '';
    let imported = 0;
    for (let g = 0; g < selected.length; g += 1) {
      const group = selected[g];
      const projectId = await this.resolveImportProjectId(group.projectKey);
      if (projectId === null) {
        continue;
      }
      for (let i = 0; i < group.photoNumbers.length; i += 1) {
        const photoNumber = group.photoNumbers[i];
        if (await this.database.capturePhotoNumberExists(projectId, photoNumber)) {
          continue;
        }
        const captureId = util.generateRandomUUID();
        const localPath = `${this.filesDir}/renders/${captureId}.jpg`;
        const failure = await this.bridge.download(config, password, group.projectKey,
          `${photoNumber}.jpg`, localPath);
        if (failure !== null) {
          throw new Error(`nas:${failure}`);
        }
        const sha256 = await this.bridge.sha256(localPath);
        const now = Date.now();
        await this.database.insertNasImportedCapture(captureId, projectId, photoNumber,
          localPath, sha256, now);
        // Queue bookkeeping marks the photo as already delivered so the
        // upload drain never re-uploads an import.
        await this.database.upsertNasUploadPending(captureId);
        await this.database.markNasUploaded(captureId);
        imported += 1;
      }
    }
    return imported;
  }

  /// Existing local project matching the NAS key, or a fresh one created
  /// with the key as its name; a name conflict reuses the winner (Dart
  /// ProjectNameConflictException path).
  private async resolveImportProjectId(projectKey: string): Promise<string | null> {
    const existing = await this.database.listProjectsForFilter();
    for (let i = 0; i < existing.length; i += 1) {
      if (sanitizeProjectKey(existing[i].name) === projectKey) {
        return existing[i].id;
      }
    }
    try {
      const created = await this.database.createProject(projectKey);
      return created.id;
    } catch (error) {
      if ((error as Error).message !== 'project_name_conflict') {
        throw error as Error;
      }
      const projects = await this.database.listProjectsForFilter();
      for (let i = 0; i < projects.length; i += 1) {
        if (sanitizeProjectKey(projects[i].name) === projectKey) {
          return projects[i].id;
        }
      }
      return null;
    }
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
