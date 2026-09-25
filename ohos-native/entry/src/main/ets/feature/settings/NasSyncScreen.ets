import hilog from '@ohos.hilog';
import { AppDatabase, NasSyncConfigRecord, NasUploadCounts } from '../../data/database/AppDatabase';
import { AppRuntime } from '../../app/AppRuntime';
import { LifecycleSegment, messageTransition, SectionHeader, SegmentOption } from '../../shared/AppComponents';
import { FormField } from '../../shared/FormComponents';
import { tr } from '../../shared/AppText';
import { UiTokens } from '../../shared/UiTokens';
import { SAFE_AREA_BOTTOM_VP } from '../../shared/SystemBars';
import { RootShellPolicy } from '../../shared/RootShellPolicy';
import { nasFailureCode, NasImportPreviewGroup } from '../../core/sync/NasSyncService';
import { Haptics } from '../../shared/Feedback';

const LOG_DOMAIN: number = 0x5100;
const LOG_TAG: string = 'NasSyncScreen';

/**
 * NAS sync configuration (settings, data and safety). Mirrors the Flutter
 * surface: protocol choice, target fields, wifi-only gate, connection test
 * and the live queue summary. The password is written straight into the
 * asset store and never enters RDB, backups or diagnostics.
 */
@Component
export struct NasSyncScreen {
  @Consume('pathStack') pathStack: NavPathStack;
  @StorageLink(SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;
  @State private protocol: string = 'webdav';
  @State private host: string = '';
  @State private portText: string = '';
  @State private username: string = '';
  @State private rootPath: string = '/';
  @State private secureTls: boolean = false;
  @State private acceptInvalidTls: boolean = false;
  @State private wifiOnly: boolean = true;
  @State private syncEnabled: boolean = false;
  @State private syncMode: string = 'upload_only';
  @State private importGroups: NasImportPreviewGroup[] = [];
  @State private importSelected: string[] = [];
  @State private loaded: boolean = false;
  @State private busy: boolean = false;
  @State private message: string = '';
  @State private messageError: boolean = false;
  @State private counts: NasUploadCounts = new NasUploadCounts(0, 0, 0);
  private password: string = '';
  private passwordStored: boolean = false;
  private knownFingerprint: string | null = null;
  private database: AppDatabase | null = null;
  private countsListener: ((counts: NasUploadCounts) => void) | null = null;

  aboutToAppear(): void {
    this.database = AppRuntime.require().database;
    this.countsListener = (counts: NasUploadCounts): void => {
      this.counts = counts;
    };
    AppRuntime.require().nasSync.addCountsListener(this.countsListener);
    this.reload();
  }

  aboutToDisappear(): void {
    if (this.countsListener !== null) {
      AppRuntime.require().nasSync.removeCountsListener(this.countsListener);
      this.countsListener = null;
    }
  }

  private async reload(): Promise<void> {
    if (this.database === null) {
      return;
    }
    const config = await this.database.nasSyncConfig();
    const runtime = AppRuntime.require();
    const stored = await runtime.nasSync.secrets.read();
    this.passwordStored = stored !== null && stored.length > 0;
    this.knownFingerprint = config.knownSftpFingerprint;
    this.protocol = config.protocol;
    this.host = config.host;
    this.portText = config.port === null ? '' : `${config.port}`;
    this.username = config.username;
    this.rootPath = config.rootPath;
    this.secureTls = config.secureTls;
    this.acceptInvalidTls = config.acceptInvalidTls;
    this.wifiOnly = config.wifiOnly;
    this.syncEnabled = config.enabled;
    this.syncMode = config.syncMode;
    this.counts = await this.database.countNasUploadStates();
    this.loaded = true;
  }

  private showToast(message: string, isError: boolean): void {
    this.message = message;
    this.messageError = isError;
  }

  private buildConfig(): NasSyncConfigRecord {
    const port = Number.parseInt(this.portText, 10);
    const config = new NasSyncConfigRecord();
    config.protocol = this.protocol;
    config.host = this.host.trim();
    config.port = Number.isFinite(port) && this.portText.trim().length > 0 ? port : null;
    config.username = this.username.trim();
    config.rootPath = this.rootPath.trim().length === 0 ? '/' : this.rootPath.trim();
    // ohos-native WebDAV has no TLS backend (D-023). Never send HTTPS.
    config.secureTls = this.protocol === 'webdav' ? false : this.secureTls;
    config.acceptInvalidTls = false;
    config.knownSftpFingerprint = this.knownFingerprint;
    config.wifiOnly = this.wifiOnly;
    config.enabled = this.syncEnabled;
    config.syncMode = this.syncMode === 'two_way' ? 'two_way' : 'upload_only';
    config.updatedAt = Date.now();
    return config;
  }

  /**
   * Ports outside 1–65535 never reach the Rust core: its u16 decoding
   * would surface as an opaque error instead of this friendly message.
   */
  private hasPortError(): boolean {
    const text = this.portText.trim();
    if (text.length === 0) {
      return false;
    }
    if (!/^[0-9]+$/.test(text)) {
      return true;
    }
    const port = Number.parseInt(text, 10);
    return !Number.isFinite(port) || port < 1 || port > 65535;
  }

  /**
   * The enable switch is the master of the upload queue, matching Flutter:
   * persist immediately, and refuse to turn on until a host exists.
   */
  private async setEnabled(value: boolean): Promise<void> {
    if (value && this.host.trim().length === 0) {
      this.showToast(tr('请先填写服务器地址', 'Enter the server address first'), true);
      return;
    }
    this.syncEnabled = value;
    await this.save();
  }

  private async save(): Promise<void> {
    if (this.database === null) {
      return;
    }
    if (this.host.trim().length === 0 && this.syncEnabled) {
      this.showToast(tr('请先填写服务器地址', 'Enter the server address first'), true);
      return;
    }
    if (this.hasPortError()) {
      this.showToast(tr('端口需在 1–65535 之间', 'Port must be between 1 and 65535'), true);
      return;
    }
    this.busy = true;
    try {
      const config = this.buildConfig();
      await this.database.saveNasSyncConfig(config);
      const runtime = AppRuntime.require();
      if (this.password.length > 0) {
        await runtime.nasSync.secrets.write(this.password);
        this.password = '';
        this.passwordStored = true;
      }
      this.showToast(tr('已保存', 'Saved'), false);
      await runtime.nasSync.syncNow();
      this.counts = await this.database.countNasUploadStates();
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'nas save failed: %{public}s', (error as Error).message);
      this.showToast(tr('保存失败，请稍后重试', 'Saving failed; try again later'), true);
    } finally {
      this.busy = false;
    }
  }

  private async testConnection(): Promise<void> {
    const database = this.database;
    if (database === null) {
      return;
    }
    if (this.host.trim().length === 0) {
      this.showToast(tr('请先填写服务器地址', 'Enter the server address first'), true);
      return;
    }
    if (this.hasPortError()) {
      this.showToast(tr('端口需在 1–65535 之间', 'Port must be between 1 and 65535'), true);
      return;
    }
    this.busy = true;
    try {
      const runtime = AppRuntime.require();
      const config = this.buildConfig();
      const stored = await runtime.nasSync.secrets.read();
      const password = this.password.length > 0 ? this.password : (stored ?? '');
      const outcome = await runtime.nasSync.bridge.testConnection(config, password);
      if (outcome.failure !== null) {
        this.showToast(this.failureText(outcome.failure), true);
        return;
      }
      if (outcome.sftpFingerprint !== null && outcome.sftpFingerprint !== this.knownFingerprint) {
        if (!await this.confirmFingerprint(outcome.sftpFingerprint)) {
          return;
        }
        this.knownFingerprint = outcome.sftpFingerprint;
        await database.saveNasSyncConfig(this.buildConfig());
      }
      this.showToast(tr('连接成功', 'Connection successful'), false);
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'nas test failed: %{public}s', (error as Error).message);
      this.showToast(tr('测试失败，请稍后重试', 'The test failed; try again later'), true);
    } finally {
      this.busy = false;
    }
  }

  /** Trust-on-first-use gate: the SFTP host key fingerprint must be confirmed before it is stored. */
  private confirmFingerprint(fingerprint: string): Promise<boolean> {
    return new Promise<boolean>((resolve) => {
      AlertDialog.show({
        title: tr('验证服务器指纹', 'Verify server fingerprint'),
        message: tr(
          `首次连接该 SFTP 服务器。请核对主机密钥指纹后再信任：\n\n${fingerprint}`,
          `First connection to this SFTP server. Verify the host key fingerprint before trusting it:\n\n${fingerprint}`),
        autoCancel: true,
        secondaryButton: {
          value: tr('取消', 'Cancel'),
          action: () => resolve(false)
        },
        primaryButton: {
          value: tr('信任并继续', 'Trust and continue'),
          fontColor: UiTokens.PRIMARY,
          action: () => resolve(true)
        },
        cancel: () => resolve(false)
      });
    });
  }

  private failureText(code: string): string {
    if (code === 'connection_failed') {
      return tr('无法连接服务器，请检查地址和网络。', 'Cannot reach the server. Check the address and network.');
    }
    if (code === 'auth_failed') {
      return tr('用户名或密码不正确', 'Incorrect username or password');
    }
    if (code === 'timeout') {
      return tr('连接超时', 'Connection timed out');
    }
    if (code === 'tls_unsupported') {
      return tr('当前平台的 WebDAV 暂不支持 HTTPS，可改用 HTTP 或 SFTP/SMB。',
        'WebDAV over HTTPS is unavailable on this platform. Use HTTP, SFTP or SMB.');
    }
    if (code === 'tls_error') {
      return tr('TLS 或证书错误', 'TLS or certificate error');
    }
    if (code === 'host_key_changed') {
      return tr('服务器指纹已变化，请重新测试连接并确认。',
        'The server fingerprint changed. Re-run the connection test to confirm.');
    }
    if (code === 'quota_insufficient') {
      return tr('NAS 存储空间不足', 'The NAS is out of storage space');
    }
    if (code === 'path_invalid') {
      return tr('远程路径无效', 'Invalid remote path');
    }
    if (code === 'local_io') {
      return tr('本地照片文件缺失', 'Local photo file is missing');
    }
    if (code === 'config_invalid') {
      return tr('配置不完整', 'The configuration is incomplete');
    }
    return tr('服务器响应异常', 'The server returned an unexpected response');
  }

  private async retryFailed(): Promise<void> {
    const runtime = AppRuntime.require();
    await runtime.nasSync.retryFailed();
    if (this.database !== null) {
      this.counts = await this.database.countNasUploadStates();
    }
  }

  /// Read-only NAS scan for remote-only photos (two-way mode only; the
  /// service gates credentials and network, mirroring the Dart flow).
  private async refreshImportPreview(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      const result = await AppRuntime.require().nasSync.previewImport();
      if (result.failure !== null) {
        this.importGroups = [];
        this.importSelected = [];
        this.showToast(this.failureText(result.failure), true);
        return;
      }
      this.importGroups = result.groups;
      this.importSelected = result.groups.map((g: NasImportPreviewGroup): string => g.projectKey);
      if (result.groups.length === 0) {
        this.showToast(tr('NAS 上没有可恢复的照片', 'No restorable photos on the NAS'), false);
      }
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'nas preview failed: %{public}s', (error as Error).message);
      this.showToast(tr('暂时无法读取 NAS 照片，请稍后重试', 'Could not read NAS photos; try again later'), true);
    } finally {
      this.busy = false;
    }
  }

  private toggleImportSelection(projectKey: string, selected: boolean): void {
    Haptics.selectionClick();
    const next: string[] = this.importSelected.filter((key: string): boolean => key !== projectKey);
    if (selected) {
      next.push(projectKey);
    }
    this.importSelected = next;
  }

  private async runImport(): Promise<void> {
    if (this.busy) {
      return;
    }
    const selected = this.importGroups.filter((g: NasImportPreviewGroup): boolean =>
      this.importSelected.includes(g.projectKey));
    if (selected.length === 0) {
      this.showToast(tr('请先勾选要恢复的项目', 'Select the projects to restore first'), true);
      return;
    }
    this.busy = true;
    try {
      const imported = await AppRuntime.require().nasSync.importProjects(selected);
      this.importGroups = [];
      this.importSelected = [];
      if (this.database !== null) {
        this.counts = await this.database.countNasUploadStates();
      }
      if (imported > 0) {
        // Imported records must show up without waiting for the next
        // capture or queue event to refresh the observers.
        AppRuntime.require().notifyDataChanged();
        Haptics.lightImpact();
      }
      this.showToast(tr(`已从 NAS 恢复 ${imported} 张照片`, `Restored ${imported} photos from the NAS`), false);
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'nas import failed: %{public}s', (error as Error).message);
      this.showToast(this.failureText(nasFailureCode((error as Error).message)), true);
    } finally {
      this.busy = false;
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column() {
          SectionHeader({ title: tr('NAS 同步', 'NAS sync') })
          Column({ space: 8 }) {
            this.toggleRow(tr('启用 NAS 同步', 'Enable NAS sync'), this.syncEnabled,
              (value: boolean) => { this.setEnabled(value); })
            Text(tr('协议', 'Protocol'))
              .fontSize(16).fontWeight(FontWeight.Medium).fontColor(UiTokens.TEXT).width('100%')
            LifecycleSegment({
              options: [
                new SegmentOption('webdav', tr('WebDAV', 'WebDAV')),
                new SegmentOption('sftp', tr('SFTP', 'SFTP')),
                new SegmentOption('smb', tr('SMB', 'SMB'))
              ],
              selectedValue: this.protocol,
              controlEnabled: !this.busy,
              onSelect: (value: string): void => { this.protocol = value; }
            })
            FormField({
              label: tr('服务器地址', 'Server address'),
              value: this.host,
              placeholder: tr('例如 192.168.1.10', 'e.g. 192.168.1.10'),
              fieldEnabled: !this.busy,
              onChange: (value: string): void => { this.host = value; }
            })
            FormField({
              label: tr('端口（可选）', 'Port (optional)'),
              value: this.portText,
              placeholder: this.protocol === 'smb' ? '445' :
                (this.protocol === 'sftp' ? '22' : '80'),
              maxLength: 5,
              fieldEnabled: !this.busy,
              onChange: (value: string): void => { this.portText = value; }
            })
            FormField({
              label: tr('用户名', 'Username'),
              value: this.username,
              fieldEnabled: !this.busy,
              onChange: (value: string): void => { this.username = value; }
            })
            FormField({
              label: tr('密码', 'Password'),
              value: this.password,
              helper: this.passwordStored ? tr('已保存，输入可更新', 'Saved; type to update') : '',
              obscure: true,
              fieldEnabled: !this.busy,
              onChange: (value: string): void => { this.password = value; }
            })
            FormField({
              label: tr('根目录', 'Root path'),
              value: this.rootPath,
              placeholder: this.protocol === 'smb'
                ? tr('以共享名开头，例如 /media/SiteMark', 'Start with the share, e.g. /media/SiteMark')
                : tr('例如 /SiteMark', 'e.g. /SiteMark'),
              fieldEnabled: !this.busy,
              onChange: (value: string): void => { this.rootPath = value; }
            })
            if (this.protocol === 'webdav') {
              Text(tr('当前平台的 WebDAV 仅支持 HTTP。加密传输请改用 SFTP 或 SMB。',
                'WebDAV on this platform is HTTP only. Use SFTP or SMB for encrypted transport.'))
                .fontSize(12).fontColor(UiTokens.TEXT_SECONDARY).width('100%')
            }
            this.toggleRow(tr('仅 Wi-Fi 上传', 'Upload on Wi-Fi only'), this.wifiOnly,
              (value: boolean) => { this.wifiOnly = value; })
            Text(tr('同步模式', 'Sync mode'))
              .fontSize(16).fontWeight(FontWeight.Medium).fontColor(UiTokens.TEXT).width('100%')
            LifecycleSegment({
              options: [
                new SegmentOption('upload_only', tr('仅上传', 'Upload only')),
                new SegmentOption('two_way', tr('双向同步', 'Two-way'))
              ],
              selectedValue: this.syncMode,
              controlEnabled: !this.busy,
              onSelect: (value: string): void => { this.syncMode = value; }
            })
            Text(tr('仅上传：照片只从本机发出。双向：本机删除的照片会同时清理 NAS 副本，且可从这里恢复 NAS 上本机没有的照片。',
              'Upload only: photos leave this device only. Two-way: photos deleted here also remove the NAS copy, and photos the NAS has but this device lacks can be restored here.'))
              .fontSize(12).fontColor(UiTokens.TEXT_SECONDARY).width('100%')
            if (this.syncMode === 'two_way' && this.syncEnabled) {
              Button(this.busy ? tr('正在读取…', 'Reading…') :
                tr('查找 NAS 上可恢复的照片', 'Find restorable photos on the NAS'))
                .buttonStyle(ButtonStyleMode.NORMAL).width('100%')
                .enabled(!this.busy)
                .onClick(() => this.refreshImportPreview())
              ForEach(this.importGroups, (group: NasImportPreviewGroup) => {
                Row({ space: 10 }) {
                  Checkbox({ name: group.projectKey, group: 'nasImport' })
                    .select(this.importSelected.includes(group.projectKey))
                    .selectedColor(UiTokens.PRIMARY)
                    .onChange((selected: boolean) => this.toggleImportSelection(group.projectKey, selected))
                  Column({ space: 2 }) {
                    Text(group.projectKey).fontSize(14).fontWeight(FontWeight.Medium)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(group.existsLocally ?
                      tr(`已有项目 · 可恢复 ${group.photoNumbers.length} 张`,
                        `Existing project · ${group.photoNumbers.length} to restore`) :
                      tr(`将新建项目 · 可恢复 ${group.photoNumbers.length} 张`,
                        `New project · ${group.photoNumbers.length} to restore`))
                      .fontSize(12).fontColor(UiTokens.TEXT_SECONDARY)
                  }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                }
                .width('100%').padding({ top: 8, bottom: 8 })
              }, (group: NasImportPreviewGroup): string => group.projectKey)
              if (this.importGroups.length > 0) {
                Button(this.busy ? tr('正在恢复…', 'Restoring…') :
                  tr(`导入选中的 ${this.importSelected.length} 个项目`, `Import ${this.importSelected.length} selected projects`))
                  .buttonStyle(ButtonStyleMode.EMPHASIZED).width('100%')
                  .enabled(!this.busy && this.importSelected.length > 0)
                  .onClick(() => this.runImport())
              }
            }
            Row({ space: 12 }) {
              Button(tr('测试连接', 'Test connection'))
                .buttonStyle(ButtonStyleMode.NORMAL).role(ButtonRole.NORMAL)
                .enabled(!this.busy)
                .onClick(() => this.testConnection())
              Button(tr('保存', 'Save'))
                .buttonStyle(ButtonStyleMode.EMPHASIZED)
                .enabled(!this.busy)
                .onClick(() => this.save())
            }
            .width('100%').padding({ top: 8, bottom: 8 })
            Text(tr(`待上传 ${this.counts.pending} · 失败 ${this.counts.failed} · 已上传 ${this.counts.uploaded}`,
              `Pending ${this.counts.pending} · Failed ${this.counts.failed} · Uploaded ${this.counts.uploaded}`))
              .fontSize(12).fontColor(UiTokens.TEXT_SECONDARY).width('100%')
            Button(tr('重试失败的上传', 'Retry failed uploads'))
              .buttonStyle(ButtonStyleMode.NORMAL)
              .enabled(!this.busy && this.counts.failed > 0)
              .onClick(() => this.retryFailed())
            Text(tr('上传仅面向你配置的 NAS。密码保存在系统安全存储，不会进入备份或诊断。',
              'Uploads go only to the NAS you configure. Passwords stay in system secure storage and never enter backups or diagnostics.'))
              .fontSize(12).fontColor(UiTokens.TEXT_SECONDARY).width('100%')
            if (this.message.length > 0) {
              Text(this.message).fontSize(12)
                .fontColor(this.messageError ? UiTokens.DANGER : UiTokens.TEXT_SECONDARY)
                .width('100%').transition(messageTransition())
            }
          }
          .constraintSize({ minHeight: 64 })
          .padding(12)
          .margin({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING })
          .backgroundColor(UiTokens.SURFACE).borderRadius(UiTokens.CARD_RADIUS)
          .border({ width: 1, color: UiTokens.OUTLINE_SUBTLE })
        }
        .padding({ bottom: RootShellPolicy.contentBottomInset() + this.safeAreaBottomVp })
        .width('100%')
      }
      .layoutWeight(1)
    }
    .width('100%').height('100%').backgroundColor(UiTokens.BACKGROUND)
  }

  @Builder
  private toggleRow(label: string, value: boolean, onChange: (value: boolean) => void) {
    Row() {
      Text(label).fontSize(15).layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: value })
        .selectedColor(UiTokens.PRIMARY)
        .onChange((next: boolean): void => onChange(next))
    }
    .constraintSize({ minHeight: 48 })
    .width('100%')
  }
}
