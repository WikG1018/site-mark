import { AppRuntime } from '../../app/AppRuntime';
import { Routes } from '../../app/Routes';
import { StorageInspector, StorageSnapshot } from '../../core/system/StorageInspector';
import { DiagnosticSummary } from '../../data/database/AppDatabase';
import { AppSettingsRecord } from '../../domain/Models';
import { AccentSwatchRow, AppTopBar, LifecycleSegment, SectionHeader, SegmentOption, SettingRow, ValueTextRow } from
  '../../shared/AppComponents';
import { AccentSwatches } from '../../shared/AccentSwatches';
import { formatBytes, formatDateTime, lifecycleLabel } from '../../shared/Formatters';
import { UiTokens } from '../../shared/UiTokens';
import { ProjectSummary } from '../../domain/Models';
import { ProjectLifecycleStatus } from '../../domain/StateMachine';
import { BackupResult, ProjectBackupService } from '../backup/BackupService';
import { ProjectRestoreService } from '../backup/RestoreService';
import { DiagnosticBundleService } from '../diagnostics/DiagnosticBundleService';
import { tr, userFacingMessage } from '../../shared/AppText';
import { ScreenMessageClock } from '../../shared/Feedback';
import { SAFE_AREA_BOTTOM_VP } from '../../shared/SystemBars';
import { RootShellPolicy } from '../../shared/RootShellPolicy';
import { ScrollChromeCoordinator } from '../../shared/ScrollChromePolicy';
import { MotionPolicy } from '../../shared/MotionPolicy';
import { ScreenLifecycleActionCoordinator, ScreenRequestCoordinator } from '../../shared/ScreenActionCoordinator';
import { StableSelectionList } from './SettingsProjectSelection';
import { settingsBackAccessibilityText, settingsConfirmationButtonHeight, diagnosticsConfirmAccessibilityText }
  from './SettingsAccessibility';
import { AppearanceSettingsDraft } from './AppearanceSettingsDraft';
import { DiagnosticsGenerationOutcome, DiagnosticsGenerationOutcomeStore, DiagnosticsGenerationStatus }
  from './DiagnosticsActionOutcome';
import { ExportDeliveryChannel } from '../backup/ExportDeliveryPolicy';
import { loadAppVersion } from '../../shared/AppVersion';

const notificationActionCoordinator: ScreenLifecycleActionCoordinator = new ScreenLifecycleActionCoordinator();
const appearanceActionCoordinator: ScreenLifecycleActionCoordinator = new ScreenLifecycleActionCoordinator();
const diagnosticsActionCoordinator: ScreenLifecycleActionCoordinator = new ScreenLifecycleActionCoordinator();
const diagnosticsOutcomeStore: DiagnosticsGenerationOutcomeStore = new DiagnosticsGenerationOutcomeStore();
const backupActionCoordinator: ScreenLifecycleActionCoordinator = new ScreenLifecycleActionCoordinator();

@Component
export struct SettingsView {
  @Consume('pathStack') pathStack: NavPathStack;
  @StorageLink(SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;
  private readonly loadCoordinator: ScreenRequestCoordinator = new ScreenRequestCoordinator();
  private readonly notificationCoordinator: ScreenLifecycleActionCoordinator = notificationActionCoordinator;
  @State private notificationsEnabled: boolean = false;
  @State private notificationsLoading: boolean = true;
  @State private notificationsBusy: boolean = false;
  @State private notificationMessage: string = '';
  @State private notificationError: boolean = false;
  @State private chromeVisible: boolean = true;
  private readonly chromeListener: () => void = (): void => {
    this.chromeVisible = ScrollChromeCoordinator.shared().isVisible();
  };

  aboutToAppear(): void {
    ScrollChromeCoordinator.shared().subscribe(this.chromeListener);
    this.chromeVisible = ScrollChromeCoordinator.shared().isVisible();
    this.loadCoordinator.activate();
    this.notificationCoordinator.activate();
    this.notificationsBusy = this.notificationCoordinator.isBusy();
    this.loadSettings();
    if (this.notificationsBusy) this.reconcileNotificationWhenIdle();
  }

  aboutToDisappear(): void {
    this.loadCoordinator.deactivate();
    this.notificationCoordinator.invalidate();
    ScrollChromeCoordinator.shared().unsubscribe(this.chromeListener);
  }

  private async loadSettings(): Promise<void> {
    const token: number = this.loadCoordinator.begin();
    if (token < 0) return;
    this.notificationsLoading = true;
    try {
      const settings: AppSettingsRecord = await AppRuntime.require().database.settings();
      if (!this.loadCoordinator.isCurrent(token)) return;
      this.notificationsEnabled = settings.completionNotificationsEnabled;
      this.notificationMessage = '';
      this.notificationError = false;
    } catch (_) {
      if (!this.loadCoordinator.isCurrent(token)) return;
      this.notificationMessage = tr('通知设置加载失败，请稍后重试',
        'Notification settings could not be loaded. Try again later.');
      this.notificationError = true;
    } finally {
      if (this.loadCoordinator.isCurrent(token)) this.notificationsLoading = false;
    }
  }

  private async reconcileNotificationWhenIdle(): Promise<void> {
    await this.notificationCoordinator.whenIdle();
    if (!this.loadCoordinator.isActive()) return;
    this.notificationsBusy = false;
    await this.loadSettings();
  }

  private async setNotifications(enabled: boolean): Promise<void> {
    const token: number | null = this.notificationCoordinator.begin();
    if (token === null) return;
    this.notificationsBusy = true;
    const runtime = AppRuntime.require();
    try {
      const settings: AppSettingsRecord = await runtime.database.settings();
      if (enabled) {
        const granted: boolean = await runtime.notifications.requestEnable();
        if (!granted) {
          if (this.notificationCoordinator.isCurrent(token)) {
            this.notificationsEnabled = false;
            this.notificationMessage = tr('系统未允许通知；拍摄和后台处理不受影响',
              'Notifications were not allowed; capture and processing are unaffected');
            this.notificationError = false;
          }
          return;
        }
      }
      settings.completionNotificationsEnabled = enabled;
      await runtime.database.updateSettings(settings);
      if (!this.notificationCoordinator.isCurrent(token)) return;
      this.notificationsEnabled = enabled;
      this.notificationMessage = enabled ? tr('处理完成后会发送一条本机通知',
        'A local notification will be sent when processing completes') : '';
      this.notificationError = false;
    } catch (_) {
      if (this.notificationCoordinator.isCurrent(token)) {
        this.notificationMessage = tr('通知设置保存失败，请稍后重试',
          'Notification settings could not be saved. Try again later.');
        this.notificationError = true;
      }
    } finally {
      if (this.notificationCoordinator.finish(token)) this.notificationsBusy = false;
    }
  }

  build() {
    Column() {
      AppTopBar({ title: tr('设置', 'Settings'), subtitle: tr('拍摄、数据与应用偏好',
        'Capture, data, and app preferences') })
        .translate({ y: this.chromeVisible ? 0 : -UiTokens.TOP_BAR_HEIGHT })
        .animation({ duration: MotionPolicy.duration(UiTokens.MOTION_STANDARD), curve: Curve.EaseOut })
        .hitTestBehavior(this.chromeVisible ? HitTestMode.Default : HitTestMode.None)
      Scroll() {
        Column() {
          SectionHeader({ title: tr('拍摄与记录', 'Capture and records') })
          Column() {
            SettingRow({ icon: '◩', title: tr('新建项目水印默认值', 'New-project watermark defaults'),
              subtitle: tr('位置、透明度、字体大小和强调色', 'Position, opacity, font size, and accent color'),
              showDivider: true,
              action: (): void => { this.pathStack.pushPathByName(Routes.APPEARANCE, null); } })
            SettingRow({ icon: '⌖', title: tr('位置权限', 'Location permission'),
              subtitle: tr('拒绝定位也不会阻止拍摄', 'Declining location does not block capture'),
              showDivider: true,
              action: (): void => {
                AppRuntime.require().services.openApplicationSettings().then((opened: boolean): void => {
                  if (!opened) {
                    this.notificationMessage = tr('无法打开系统设置，请在系统设置中手动授权定位',
                      'Could not open system settings. Grant the location permission manually there.');
                    this.notificationError = true;
                  }
                });
              } })
            Row({ space: 14 }) {
              Text('◉').fontSize(22).fontColor(UiTokens.PRIMARY).width(36).textAlign(TextAlign.Center)
              Column({ space: 3 }) {
                Text(tr('完成通知', 'Completion notifications')).fontSize(16)
                  .fontWeight(FontWeight.Medium).width('100%')
                Text(tr('可选；关闭后不影响后台处理', 'Optional; disabling this does not affect processing'))
                  .fontSize(13).fontColor(UiTokens.TEXT_SECONDARY).width('100%')
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Toggle({ type: ToggleType.Switch, isOn: this.notificationsEnabled })
                .selectedColor(UiTokens.PRIMARY)
                .accessibilityText(tr('完成通知', 'Completion notifications'))
                .enabled(!this.notificationsLoading && !this.notificationsBusy)
                .onChange((value: boolean): void => { this.setNotifications(value); })
            }
            .constraintSize({ minHeight: 64 })
            .padding({ left: 16, right: 16, top: 9, bottom: 9 })
            .accessibilityText(tr('完成通知，可选；关闭后不影响后台处理',
              'Completion notifications. Optional; disabling this does not affect processing'))
            .width('100%')
          }.margin({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING })
            .backgroundColor(UiTokens.SURFACE).borderRadius(UiTokens.CARD_RADIUS)
            .border({ width: 1, color: UiTokens.OUTLINE_SUBTLE })
          if (this.notificationsLoading || this.notificationMessage.length > 0) {
            Text(this.notificationsLoading ? tr('正在读取通知设置…', 'Loading notification settings…') :
              this.notificationMessage).fontSize(12)
              .fontColor(this.notificationError ? UiTokens.DANGER : UiTokens.TEXT_SECONDARY)
              .padding({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING, top: 6, bottom: 2 }).width('100%')
          }
          SectionHeader({ title: tr('数据与安全', 'Data and safety') })
          Column() {
            SettingRow({ icon: '⇅', title: tr('备份与恢复', 'Backup and restore'),
              subtitle: tr('备份一个或多个项目，并从 SiteMark ZIP 恢复',
                'Back up one or more projects and restore SiteMark ZIP files'),
              showDivider: true,
              action: (): void => { this.pathStack.pushPathByName(Routes.BACKUP, null); } })
            SettingRow({ icon: '▤', title: tr('存储', 'Storage'),
              subtitle: tr('查看应用内原图、成片和导出占用', 'Review private originals, images, and exports'),
              showDivider: true,
              action: (): void => { this.pathStack.pushPathByName(Routes.STORAGE, null); } })
            SettingRow({ icon: '⌂', title: tr('NAS 同步', 'NAS sync'),
              subtitle: tr('把水印成片自动上传到你的 NAS',
                'Auto-upload watermarked photos to your NAS'),
              showDivider: true,
              action: (): void => { this.pathStack.pushPathByName(Routes.NAS_SYNC, null); } })
            SettingRow({ icon: '◇', title: tr('诊断与反馈', 'Diagnostics and feedback'),
              subtitle: tr('本机生成隐私安全的诊断包，不会自动上传',
                'Create a privacy-safe diagnostic bundle locally; nothing is uploaded automatically'),
              action: (): void => { this.pathStack.pushPathByName(Routes.DIAGNOSTICS, null); } })
          }.margin({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING })
            .backgroundColor(UiTokens.SURFACE).borderRadius(UiTokens.CARD_RADIUS)
            .border({ width: 1, color: UiTokens.OUTLINE_SUBTLE })
          SectionHeader({ title: tr('应用', 'App') })
          Column() {
            SettingRow({ icon: '◐', title: tr('外观与语言', 'Appearance and language'),
              subtitle: tr('跟随系统、浅色/深色和中英文', 'System, light/dark, Chinese, and English'),
              showDivider: true,
              action: (): void => { this.pathStack.pushPathByName(Routes.APPEARANCE, null); } })
            SettingRow({ icon: 'ⓘ', title: tr('关于工程印记', 'About SiteMark'),
              subtitle: tr('版本、隐私说明和 GitHub 代码仓库', 'Version, privacy, and GitHub repository'),
              action: (): void => { this.pathStack.pushPathByName(Routes.ABOUT, null); } })
          }.margin({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING })
            .backgroundColor(UiTokens.SURFACE).borderRadius(UiTokens.CARD_RADIUS)
            .border({ width: 1, color: UiTokens.OUTLINE_SUBTLE })
        }
        .padding({ bottom: RootShellPolicy.contentBottomInset() + this.safeAreaBottomVp })
        .width('100%')
      }.layoutWeight(1)
      .onDidScroll((xOffset: number, yOffset: number): void => {
        ScrollChromeCoordinator.shared().applyOffset(yOffset);
      })
    }
    .width('100%').height('100%').backgroundColor(UiTokens.BACKGROUND)
  }
}

@Component
export struct AppearanceScreen {
  @Consume('pathStack') pathStack: NavPathStack;
  @StorageLink(SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;
  private readonly loadCoordinator: ScreenRequestCoordinator = new ScreenRequestCoordinator();
  private readonly saveCoordinator: ScreenLifecycleActionCoordinator = appearanceActionCoordinator;
  @State private settings: AppSettingsRecord | null = null;
  @State private watermarkOpacity: number = 0.78;
  @State private fontScale: number = 1.0;
  @State private watermarkPosition: string = 'bottomLeft';
  @State private appSeed: number = AccentSwatches.defaultArgb();
  @State private accent: number = AccentSwatches.defaultArgb();
  @State private theme: string = 'system';
  @State private locale: string = '';
  @State private message: string = '';
  @State private loading: boolean = true;
  @State private saving: boolean = false;
  @State private savedFlash: boolean = false;
  @State private messageError: boolean = false;
  private readonly messageClock = new ScreenMessageClock();

  aboutToAppear(): void {
    this.loadCoordinator.activate();
    this.saveCoordinator.activate();
    this.saving = this.saveCoordinator.isBusy();
    this.load();
    if (this.saving) this.reconcileSaveWhenIdle();
  }

  aboutToDisappear(): void {
    this.messageClock.reset();
    this.loadCoordinator.deactivate();
    this.saveCoordinator.invalidate();
  }

  private async load(): Promise<void> {
    const token: number = this.loadCoordinator.begin();
    if (token < 0) return;
    this.loading = true;
    try {
      const value: AppSettingsRecord = await AppRuntime.require().database.settings();
      if (!this.loadCoordinator.isCurrent(token)) return;
      this.settings = value;
      this.watermarkOpacity = value.defaultWatermarkOpacity;
      this.fontScale = value.defaultWatermarkFontScale;
      this.watermarkPosition = value.defaultWatermarkPosition;
      this.appSeed = value.appSeedColorArgb;
      this.accent = value.defaultWatermarkAccentColorArgb;
      this.theme = value.themeMode;
      this.locale = value.localeCode;
      this.message = '';
      this.messageError = false;
    } catch (_) {
      if (this.loadCoordinator.isCurrent(token)) {
        this.message = tr('设置加载失败，请返回后重试', 'Settings could not be loaded. Go back and try again.');
        this.messageError = true;
      }
    } finally {
      if (this.loadCoordinator.isCurrent(token)) this.loading = false;
    }
  }

  private async reconcileSaveWhenIdle(): Promise<void> {
    await this.saveCoordinator.whenIdle();
    if (!this.loadCoordinator.isActive()) return;
    this.saving = false;
    await this.load();
  }

  private async save(): Promise<void> {
    if (this.settings === null) return;
    const token: number | null = this.saveCoordinator.begin();
    if (token === null) return;
    this.saving = true;
    const draft = AppearanceSettingsDraft.fromSettings(this.settings);
    draft.themeMode = this.theme;
    draft.localeCode = this.locale;
    draft.defaultWatermarkPosition = this.watermarkPosition;
    draft.defaultWatermarkOpacity = this.watermarkOpacity;
    draft.defaultWatermarkFontScale = this.fontScale;
    draft.appSeed = this.appSeed;
    draft.accent = this.accent;
    const value = draft.toRecord();
    try {
      await AppRuntime.require().database.updateSettings(value);
      try {
        await AppRuntime.require().applyAppearance();
      } catch (_) {
        // Settings are already committed; a failure while applying them
        // in-memory (next launch applies the stored value) must not report
        // the save itself as failed.
      }
      if (this.saveCoordinator.isCurrent(token)) {
        this.settings = value;
        this.messageError = false;
        // The inline message sits at the bottom of a long scroll and
        // auto-clears after 4s, so mirror the confirmation on the top-bar
        // action where the user's tap actually landed.
        this.savedFlash = true;
        this.messageClock.show((next: string): void => {
          this.message = next;
          if (next.length === 0) {
            this.savedFlash = false;
          }
        }, tr('设置已保存', 'Settings saved'));
      }
    } catch (_) {
      if (this.saveCoordinator.isCurrent(token)) {
        this.message = tr('设置保存失败，请稍后重试', 'Settings could not be saved. Try again later.');
        this.messageError = true;
      }
    } finally {
      if (this.saveCoordinator.finish(token)) this.saving = false;
    }
  }

  build() {
    NavDestination() {
      Column() {
        AppTopBar({ title: tr('外观与默认水印', 'Appearance & watermark'), showBack: true,
          backAccessibilityText: settingsBackAccessibilityText(),
          onBack: (): void => { this.pathStack.pop(); },
          actionLabel: this.saving ? tr('保存中…', 'Saving…') :
            (this.savedFlash ? tr('已保存', 'Saved') : tr('保存', 'Save')),
          actionAccessibilityText: this.saving ? tr('正在保存设置', 'Saving settings') : tr('保存设置', 'Save settings'),
          actionEnabled: !this.loading && !this.saving && this.settings !== null,
          onAction: (): void => { this.save(); } })
        Scroll() {
          Column({ space: 18 }) {
            if (this.loading) {
              Text(tr('正在加载设置…', 'Loading settings…')).fontSize(13)
                .fontColor(UiTokens.TEXT_SECONDARY).width('100%')
            }
            Text(tr('界面外观', 'Appearance')).fontSize(16).fontWeight(FontWeight.Bold).width('100%')
            LifecycleSegment({ options: [
              new SegmentOption('system', tr('跟随系统', 'System')),
              new SegmentOption('light', tr('浅色', 'Light')),
              new SegmentOption('dark', tr('深色', 'Dark'))
            ], selectedValue: this.theme, controlEnabled: !this.loading && !this.saving,
              onSelect: (value: string): void => { this.theme = value; } })
            Text(tr('应用主题色', 'App theme color')).fontSize(16).fontWeight(FontWeight.Bold).width('100%')
            AccentSwatchRow({
              selectedArgb: this.appSeed,
              controlEnabled: !this.loading && !this.saving,
              accessibilityKind: 'theme',
              onSelect: (argb: number): void => { this.appSeed = argb; }
            })
            Text(tr('应用语言', 'App language')).fontSize(16).fontWeight(FontWeight.Bold).width('100%')
            LifecycleSegment({ options: [
              new SegmentOption('', tr('跟随系统', 'System')),
              new SegmentOption('zh', tr('简体中文', '简体中文')),
              new SegmentOption('en', 'English')
            ], selectedValue: this.locale, controlEnabled: !this.loading && !this.saving,
              onSelect: (value: string): void => { this.locale = value; } })
            Divider().color(UiTokens.OUTLINE)
            Text(tr('新建项目水印默认值', 'New-project watermark defaults')).fontSize(16)
              .fontWeight(FontWeight.Bold).width('100%')
            LifecycleSegment({ options: [
              new SegmentOption('bottomLeft', tr('左下', 'Bottom left')),
              new SegmentOption('bottomRight', tr('右下', 'Bottom right'))
            ], selectedValue: this.watermarkPosition, controlEnabled: !this.loading && !this.saving,
              onSelect: (value: string): void => { this.watermarkPosition = value; } })
            Row() { Text(tr('透明度', 'Opacity')).layoutWeight(1); Text(`${Math.round(this.watermarkOpacity * 100)}%`) }
              .width('100%')
            Slider({ value: this.watermarkOpacity, min: 0.35, max: 1, step: 0.05 })
              .selectedColor(UiTokens.PRIMARY)
              .enabled(!this.loading && !this.saving)
              .accessibilityText(tr('水印透明度', 'Watermark opacity'))
              .onChange((value: number): void => { this.watermarkOpacity = value; })
            Row() { Text(tr('字体大小', 'Font size')).layoutWeight(1); Text(`${Math.round(this.fontScale * 100)}%`) }
              .width('100%')
            Slider({ value: this.fontScale, min: 0.75, max: 1.6, step: 0.05 })
              .selectedColor(UiTokens.PRIMARY)
              .enabled(!this.loading && !this.saving)
              .accessibilityText(tr('水印字体大小', 'Watermark font size'))
              .onChange((value: number): void => { this.fontScale = value; })
            Text(tr('水印强调色', 'Watermark accent')).fontSize(16).fontWeight(FontWeight.Bold).width('100%')
            AccentSwatchRow({
              selectedArgb: this.accent,
              controlEnabled: !this.loading && !this.saving,
              accessibilityKind: 'watermark',
              onSelect: (argb: number): void => { this.accent = argb; }
            })
            if (this.message.length > 0) {
              Text(this.message).fontSize(13)
                .fontColor(this.messageError ? UiTokens.DANGER : UiTokens.SUCCESS).width('100%')
            }
          }
          .padding(16)
          .margin({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING, top: 10,
            bottom: 40 + this.safeAreaBottomVp })
          .width(`calc(100% - ${UiTokens.PAGE_PADDING * 2}vp)`)
          .backgroundColor(UiTokens.SURFACE)
          .borderRadius(UiTokens.CARD_RADIUS)
          .border({ width: 1, color: UiTokens.OUTLINE_SUBTLE })
        }.layoutWeight(1)
      }.width('100%').height('100%').backgroundColor(UiTokens.BACKGROUND)
    }.hideTitleBar(true)
  }
}

@Component
export struct StorageScreen {
  @Consume('pathStack') pathStack: NavPathStack;
  @StorageLink(SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;
  @State private snapshot: StorageSnapshot = new StorageSnapshot();
  @State private message: string = '';
  private readonly messageClock = new ScreenMessageClock();

  aboutToAppear(): void { this.refresh(); }

  aboutToDisappear(): void { this.messageClock.reset(); }

  private refresh(): void {
    this.snapshot = StorageInspector.inspect(AppRuntime.require().context.filesDir);
  }

  private clearExports(): void {
    StorageInspector.clearExports(AppRuntime.require().context.filesDir);
    this.messageClock.show((next: string): void => {
      this.message = next;
    }, tr('本机私有导出 ZIP 已清理；照片、记录和已保存副本不受影响',
      'Private export ZIP files were cleared; photos, records, and saved copies are unchanged'));
    this.refresh();
  }

  build() {
    NavDestination() {
      Column() {
        AppTopBar({ title: tr('存储', 'Storage'), showBack: true,
          backAccessibilityText: settingsBackAccessibilityText(),
          onBack: (): void => { this.pathStack.pop(); } })
        Scroll() {
          Column({ space: 16 }) {
            Column({ space: 2 }) {
              Text(formatBytes(this.snapshot.total())).fontSize(28).fontWeight(FontWeight.Bold)
                .fontColor(UiTokens.PRIMARY).width('100%')
              Text(tr('SiteMark 应用内数据占用', 'SiteMark in-app data')).fontSize(13)
                .fontColor(UiTokens.TEXT_SECONDARY).width('100%')
              Divider().color(UiTokens.OUTLINE_SUBTLE).margin({ top: 12 })
              ValueTextRow({ label: tr('私有原图', 'Private originals'), value: formatBytes(this.snapshot.originals) })
              ValueTextRow({ label: tr('私有水印成片', 'Private watermarked images'),
                value: formatBytes(this.snapshot.rendered) })
              ValueTextRow({ label: tr('备份与导出 ZIP', 'Backup and export ZIP files'),
                value: formatBytes(this.snapshot.exports) })
              ValueTextRow({ label: tr('其他应用文件', 'Other app files'), value: formatBytes(this.snapshot.other) })
            }
            .padding(16).width('100%').backgroundColor(UiTokens.SURFACE)
            .borderRadius(UiTokens.CARD_RADIUS).border({ width: 1, color: UiTokens.OUTLINE_SUBTLE })
            Text(tr('此统计不包含已经保存到系统相册的照片。卸载应用会删除这里的数据库、原图和成片。',
              'This total excludes photos saved to the system gallery. Uninstalling deletes this database, private originals, and rendered images.'))
              .fontSize(13).fontColor(UiTokens.TEXT_SECONDARY).lineHeight(20).width('100%')
            Button(tr('清理本机私有导出 ZIP', 'Clear private export ZIP files')).height(UiTokens.TOUCH_TARGET)
              .width('100%').fontColor(UiTokens.DANGER).backgroundColor(UiTokens.DANGER_CONTAINER)
              .accessibilityText(tr('清理本机私有导出 ZIP', 'Clear private export ZIP files'))
              .onClick((): void => this.clearExports())
            if (this.message.length > 0) {
              Text(this.message).fontSize(13).fontColor(UiTokens.PRIMARY).width('100%')
            }
          }
          .padding(16)
          .margin({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING, top: 10,
            bottom: 40 + this.safeAreaBottomVp })
          .width(`calc(100% - ${UiTokens.PAGE_PADDING * 2}vp)`)
          .backgroundColor(UiTokens.SURFACE)
          .borderRadius(UiTokens.CARD_RADIUS)
          .border({ width: 1, color: UiTokens.OUTLINE_SUBTLE })
        }.layoutWeight(1)
      }.width('100%').height('100%').backgroundColor(UiTokens.BACKGROUND)
    }.hideTitleBar(true)
  }
}

@Component
export struct DiagnosticsScreen {
  @Consume('pathStack') pathStack: NavPathStack;
  @StorageLink(SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;
  private readonly loadCoordinator: ScreenRequestCoordinator = new ScreenRequestCoordinator();
  private readonly actionCoordinator: ScreenLifecycleActionCoordinator = diagnosticsActionCoordinator;
  @State private summary: DiagnosticSummary = new DiagnosticSummary(0, 0);
  @State private message: string = '';
  @State private confirming: boolean = false;
  @State private busy: boolean = false;
  @State private loading: boolean = true;
  @State private loadError: boolean = false;
  @State private messageError: boolean = false;
  private readonly messageClock = new ScreenMessageClock();

  aboutToAppear(): void {
    this.loadCoordinator.activate();
    this.actionCoordinator.activate();
    this.busy = this.actionCoordinator.isBusy();
    if (!this.busy) this.consumeDiagnosticsOutcome(false);
    this.refresh();
    if (this.busy) this.reconcileDiagnosticsWhenIdle();
  }

  aboutToDisappear(): void {
    this.messageClock.reset();
    this.loadCoordinator.deactivate();
    this.actionCoordinator.invalidate();
  }

  private async refresh(): Promise<void> {
    const token: number = this.loadCoordinator.begin();
    if (token < 0) return;
    this.loading = true;
    this.loadError = false;
    try {
      const summary: DiagnosticSummary = await AppRuntime.require().database.diagnosticSummary();
      if (!this.loadCoordinator.isCurrent(token)) return;
      this.summary = summary;
    } catch (_) {
      if (this.loadCoordinator.isCurrent(token)) this.loadError = true;
    } finally {
      if (this.loadCoordinator.isCurrent(token)) this.loading = false;
    }
  }

  private async reconcileDiagnosticsWhenIdle(): Promise<void> {
    await this.actionCoordinator.whenIdle();
    if (!this.loadCoordinator.isActive()) return;
    this.busy = false;
    this.confirming = false;
    this.consumeDiagnosticsOutcome(true);
    await this.refresh();
  }

  private consumeDiagnosticsOutcome(clearStaleMessage: boolean): void {
    const outcome: DiagnosticsGenerationOutcome | null = diagnosticsOutcomeStore.consume();
    if (outcome === null) {
      if (clearStaleMessage) {
        this.message = '';
        this.messageError = false;
      }
      return;
    }
    if (outcome.status === DiagnosticsGenerationStatus.SAVED) {
      this.messageError = false;
      this.messageClock.show((next: string): void => {
        this.message = next;
      }, outcome.channel === ExportDeliveryChannel.SHARE_PANEL ?
        tr(`诊断包已生成，系统分享面板已打开（${outcome.eventCount} 条事件）`,
          `Diagnostic bundle ready in the system share sheet (${outcome.eventCount} events)`) :
        tr(`诊断包已保存（${outcome.eventCount} 条事件）`,
          `Diagnostic bundle saved (${outcome.eventCount} events)`));
      return;
    }
    if (outcome.status === DiagnosticsGenerationStatus.CANCELLED) {
      this.messageError = false;
      this.messageClock.show((next: string): void => {
        this.message = next;
      }, tr('诊断包已生成，但你取消了保存；可以再次生成并选择位置',
        'The bundle was generated, but saving was cancelled. Generate it again to choose a location.'));
      return;
    }
    this.message = tr('诊断包生成失败，请检查存储空间后重试',
      'Diagnostic bundle generation failed. Check storage and try again.');
    this.messageError = true;
  }

  private async clear(): Promise<void> {
    const token: number | null = this.actionCoordinator.begin();
    if (token === null) return;
    diagnosticsOutcomeStore.clear();
    this.busy = true;
    try {
      await AppRuntime.require().database.clearDiagnostics();
      if (this.actionCoordinator.isCurrent(token)) {
        this.messageError = false;
        this.messageClock.show((next: string): void => {
          this.message = next;
        }, tr('本机诊断记录已清除', 'Local diagnostic records cleared'));
      }
      await this.refresh();
    } catch (_) {
      if (this.actionCoordinator.isCurrent(token)) {
        this.message = tr('诊断记录清除失败，请稍后重试',
          'Diagnostic records could not be cleared. Try again later.');
        this.messageError = true;
      }
    } finally {
      if (this.actionCoordinator.finish(token)) this.busy = false;
    }
  }

  private async generate(): Promise<void> {
    const token: number | null = this.actionCoordinator.begin();
    if (token === null) return;
    diagnosticsOutcomeStore.clear();
    this.busy = true;
    this.confirming = false;
    this.message = tr('正在生成诊断包…', 'Generating diagnostic bundle…');
    this.messageError = false;
    try {
      const service = new DiagnosticBundleService(AppRuntime.require());
      const result = await service.generate();
      const outcome = await service.saveAs(result);
      diagnosticsOutcomeStore.publish(new DiagnosticsGenerationOutcome(
        outcome.delivered ? DiagnosticsGenerationStatus.SAVED : DiagnosticsGenerationStatus.CANCELLED,
        result.eventCount, outcome.channel));
      await this.refresh();
    } catch (_) {
      diagnosticsOutcomeStore.publish(new DiagnosticsGenerationOutcome(DiagnosticsGenerationStatus.FAILED, 0));
    } finally {
      if (this.actionCoordinator.finish(token)) {
        this.busy = false;
        this.consumeDiagnosticsOutcome(false);
      }
    }
  }

  build() {
    NavDestination() {
      Column() {
        AppTopBar({ title: tr('诊断与反馈', 'Diagnostics and feedback'), showBack: true,
          backAccessibilityText: settingsBackAccessibilityText(),
          onBack: (): void => { this.pathStack.pop(); } })
        Scroll() {
          Column({ space: 16 }) {
            Column({ space: 10 }) {
              Text(tr('隐私保护', 'Privacy protection')).fontSize(18).fontWeight(FontWeight.Bold)
                .fontColor(UiTokens.PRIMARY).width('100%')
              Text(tr('诊断记录只保存在本机，不会自动上传。诊断包不包含照片、项目名称、工程内容、拍摄人、位置坐标、文件路径、SHA-256、原始异常或堆栈。',
                'Diagnostic records stay on this device and are never uploaded automatically. Bundles exclude photos, project names, work details, photographers, coordinates, file paths, SHA-256 values, raw exceptions, and stack traces.'))
                .fontSize(14).fontColor(UiTokens.TEXT).lineHeight(22).width('100%')
              Text(tr('只有你主动确认分享或选择保存位置后，诊断 ZIP 才会离开应用私有目录。',
                'A diagnostic ZIP leaves private storage only after you confirm sharing or choose a save location.'))
                .fontSize(13).fontColor(UiTokens.TEXT_SECONDARY).lineHeight(20).width('100%')
            }
            .padding(16).width('100%').backgroundColor(UiTokens.PRIMARY_CONTAINER)
            .borderRadius(UiTokens.CARD_RADIUS).border({ width: 1, color: UiTokens.OUTLINE_SUBTLE })
            Column({ space: 8 }) {
              if (this.loading) {
                Text(tr('正在读取本机诊断记录…', 'Loading local diagnostic records…')).fontSize(14)
                  .fontColor(UiTokens.TEXT_SECONDARY).width('100%')
              } else if (this.loadError) {
                Text(tr('诊断记录读取失败', 'Diagnostic records could not be loaded')).fontSize(14)
                  .fontColor(UiTokens.DANGER).width('100%')
                Button(tr('重试', 'Retry')).height(UiTokens.TOUCH_TARGET).backgroundColor(Color.Transparent)
                  .fontColor(UiTokens.PRIMARY).onClick((): void => { this.refresh(); })
              } else {
                Text(tr(`本机诊断事件：${this.summary.eventCount} 条`,
                  `Local diagnostic events: ${this.summary.eventCount}`)).fontSize(16)
                  .fontWeight(FontWeight.Bold).width('100%')
                Text(tr(`最近记录：${formatDateTime(this.summary.latestAt)}`,
                  `Latest: ${formatDateTime(this.summary.latestAt)}`)).fontSize(13)
                  .fontColor(UiTokens.TEXT_SECONDARY).width('100%')
              }
            }
            .padding(16).width('100%').backgroundColor(UiTokens.SURFACE)
            .borderRadius(UiTokens.CARD_RADIUS).border({ width: 1, color: UiTokens.OUTLINE_SUBTLE })
            Button(this.busy ? tr('正在处理…', 'Working…') :
              tr('生成并保存诊断包', 'Generate and save diagnostic bundle'))
              .constraintSize({ minHeight: 48 }).padding({ top: 8, bottom: 8 }).width('100%')
              .backgroundColor(UiTokens.PRIMARY).fontColor(UiTokens.ON_PRIMARY)
              .enabled(!this.busy).onClick((): void => { this.confirming = true; })
            if (this.confirming) {
              Column({ space: 10 }) {
                Text(tr('保存诊断包？', 'Save diagnostic bundle?')).fontSize(17)
                  .fontWeight(FontWeight.Bold).width('100%')
                Text(tr('包含：应用与系统版本、固定错误分类、结果、数量和耗时。',
                  'Includes app and system versions, fixed error categories, outcomes, counts, and durations.'))
                  .fontSize(13).fontColor(UiTokens.TEXT).lineHeight(20).width('100%')
                Text(tr('不包含：照片、项目名称、工程内容、拍摄人、位置、文件路径、哈希、原始异常和堆栈。',
                  'Excludes photos, project names, work details, photographers, locations, file paths, hashes, raw exceptions, and stack traces.'))
                  .fontSize(13).fontColor(UiTokens.TEXT_SECONDARY).lineHeight(20).width('100%')
                Column({ space: 8 }) {
                  Button(tr('取消', 'Cancel'))
                    .constraintSize({ minHeight: settingsConfirmationButtonHeight() }).padding({ top: 8, bottom: 8 })
                    .width('100%')
                    .backgroundColor(UiTokens.CONTROL)
                    .fontColor(UiTokens.TEXT).onClick((): void => { this.confirming = false; })
                  Button(tr('确认并选择位置', 'Confirm and choose location'))
                    .constraintSize({ minHeight: settingsConfirmationButtonHeight() }).padding({ top: 8, bottom: 8 })
                    .width('100%')
                    .backgroundColor(UiTokens.PRIMARY)
                    .fontColor(UiTokens.ON_PRIMARY).accessibilityText(diagnosticsConfirmAccessibilityText())
                    .onClick((): void => { this.generate(); })
                }.width('100%')
              }
              .padding(16).width('100%').backgroundColor(UiTokens.SURFACE)
              .borderRadius(UiTokens.CARD_RADIUS).border({ width: 1, color: UiTokens.OUTLINE_SUBTLE })
            }
            Button(tr('清除本机诊断记录', 'Clear local diagnostic records'))
              .constraintSize({ minHeight: UiTokens.TOUCH_TARGET }).padding({ top: 8, bottom: 8 }).width('100%')
              .fontColor(UiTokens.DANGER)
              .backgroundColor(UiTokens.DANGER_CONTAINER).enabled(!this.busy)
              .onClick((): void => { this.clear(); })
            if (this.busy) {
              Row({ space: 10 }) {
                LoadingProgress().width(22).height(22).color(UiTokens.PRIMARY)
                Text(tr('正在处理，请稍候…', 'Working, please wait…')).fontSize(13)
                  .fontColor(UiTokens.TEXT_SECONDARY)
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
            }
            if (this.message.length > 0) {
              Text(this.message).fontSize(13)
                .fontColor(this.messageError ? UiTokens.DANGER : UiTokens.PRIMARY).width('100%')
            }
          }
          .padding({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING, top: 10,
            bottom: 40 + this.safeAreaBottomVp })
          .width('100%')
        }.layoutWeight(1)
      }.width('100%').height('100%').backgroundColor(UiTokens.BACKGROUND)
    }.hideTitleBar(true)
  }
}

@Component
export struct AboutScreen {
  @Consume('pathStack') pathStack: NavPathStack;
  @StorageLink(SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;
  @State private versionLabel: string = tr('正在读取版本…', 'Loading version…');
  private versionGeneration: number = 0;

  aboutToAppear(): void {
    const generation = ++this.versionGeneration;
    this.loadVersion(generation);
  }

  aboutToDisappear(): void {
    this.versionGeneration += 1;
  }

  private async loadVersion(generation: number): Promise<void> {
    const version = await loadAppVersion();
    if (generation !== this.versionGeneration) {
      return;
    }
    this.versionLabel = version.versionName === 'unknown' ? tr('版本信息不可用', 'Version unavailable') :
      tr(`版本 ${version.versionName}（${version.versionCode}）`,
        `Version ${version.versionName} (${version.versionCode})`);
  }

  build() {
    NavDestination() {
      Column() {
        AppTopBar({ title: tr('关于工程印记', 'About SiteMark'), showBack: true,
          backAccessibilityText: settingsBackAccessibilityText(),
          onBack: (): void => { this.pathStack.pop(); } })
        Scroll() {
          Column({ space: 14 }) {
            Text('SiteMark').fontSize(30).fontWeight(FontWeight.Bold).fontColor(UiTokens.PRIMARY)
            Text(tr('工程印记 · 鸿蒙原生版', 'SiteMark · Native HarmonyOS')).fontSize(18)
              .fontWeight(FontWeight.Medium)
            Text(this.versionLabel).fontSize(14).fontColor(UiTokens.TEXT_SECONDARY)
            Text(tr('面向工程现场记录的原生 ArkTS 水印相机。调用系统相机，无广告、无账号、无第三方云同步；照片和项目数据在本机处理。可选 NAS 默认同步关闭。',
              'A native ArkTS watermark camera for engineering site records. It uses the system camera with no ads, accounts, or third-party cloud sync; photos and project data are processed on-device. Optional NAS sync stays off by default.'))
              .fontSize(14).fontColor(UiTokens.TEXT).lineHeight(22).textAlign(TextAlign.Center)
            Divider().color(UiTokens.OUTLINE_SUBTLE).margin({ top: 8, bottom: 4 })
            Button(tr('GitHub 代码仓库\ngithub.com/WikG1018/site-mark',
              'GitHub repository\ngithub.com/WikG1018/site-mark'))
              .height(64).width('100%').fontSize(14).fontColor(UiTokens.PRIMARY)
              .backgroundColor(UiTokens.PRIMARY_CONTAINER)
              .accessibilityText(tr('打开 GitHub 代码仓库', 'Open GitHub repository'))
              .onClick((): void => { AppRuntime.require().services.openRepository(); })
            Text(tr('默认离线。唯一的网络出口是你主动配置并启用的 NAS 同步，只连接你自己的服务器。点击仓库链接时会交给系统浏览器。',
              'Offline by default. The only network surface is optional NAS sync that you enable yourself; it connects only to the server you configure. Repository links open in the system browser.'))
              .fontSize(12).fontColor(UiTokens.TEXT_SECONDARY).textAlign(TextAlign.Center)
            Divider().color(UiTokens.OUTLINE_SUBTLE).margin({ top: 8, bottom: 4 })
            Text(tr('本项目以 Apache-2.0 许可证开源，第三方组件声明见仓库 THIRD_PARTY_NOTICES.md。',
              'This project is open source under the Apache-2.0 license; third-party notices are in THIRD_PARTY_NOTICES.md in the repository.'))
              .fontSize(12).fontColor(UiTokens.TEXT_SECONDARY).textAlign(TextAlign.Center)
          }
          .padding(20).width('100%').backgroundColor(UiTokens.SURFACE)
          .borderRadius(UiTokens.CARD_RADIUS).border({ width: 1, color: UiTokens.OUTLINE_SUBTLE })
          .margin({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING, top: 10,
            bottom: 40 + this.safeAreaBottomVp })
        }.layoutWeight(1)
      }.width('100%').height('100%').backgroundColor(UiTokens.BACKGROUND)
    }.hideTitleBar(true)
  }
}

@Component
export struct BackupScreen {
  @Consume('pathStack') pathStack: NavPathStack;
  private readonly loadCoordinator: ScreenRequestCoordinator = new ScreenRequestCoordinator();
  private readonly actionCoordinator: ScreenLifecycleActionCoordinator = backupActionCoordinator;
  private readonly projectSelection: StableSelectionList<ProjectSummary> =
    new StableSelectionList<ProjectSummary>((item: ProjectSummary): string => item.project.id);
  @State private projectCount: number = 0;
  @State private selectedIds: string[] = [];
  @State private includeOriginals: boolean = true;
  @State private skipFailed: boolean = false;
  @State private busy: boolean = false;
  @State private message: string = '';
  @State private result: BackupResult | null = null;
  @State private loadingProjects: boolean = true;
  @State private projectLoadError: boolean = false;
  @StorageLink(SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;
  @State private messageError: boolean = false;
  private readonly messageClock = new ScreenMessageClock();

  aboutToAppear(): void {
    this.loadCoordinator.activate();
    this.actionCoordinator.activate();
    this.busy = this.actionCoordinator.isBusy();
    this.load();
    if (this.busy) this.reconcileBackupWhenIdle();
  }

  aboutToDisappear(): void {
    this.messageClock.reset();
    this.loadCoordinator.deactivate();
    this.actionCoordinator.invalidate();
    this.projectSelection.invalidate();
  }

  private async load(): Promise<void> {
    const token: number = this.loadCoordinator.begin();
    if (token < 0) return;
    const generation = this.projectSelection.beginLoad();
    const database = AppRuntime.require().database;
    this.loadingProjects = true;
    this.projectLoadError = false;
    try {
      const groups: ProjectSummary[][] = await Promise.all([
        database.listProjectSummaries(ProjectLifecycleStatus.ACTIVE),
        database.listProjectSummaries(ProjectLifecycleStatus.COMPLETED),
        database.listProjectSummaries(ProjectLifecycleStatus.ARCHIVED)
      ]);
      if (!this.loadCoordinator.isCurrent(token)) return;
      const rows: ProjectSummary[] = groups[0].concat(groups[1]).concat(groups[2]);
      if (this.projectSelection.replaceFor(generation, rows)) {
        this.projectCount = this.projectSelection.count();
        this.selectedIds = this.projectSelection.selectedIds();
      }
    } catch (_) {
      if (this.loadCoordinator.isCurrent(token)) this.projectLoadError = true;
    } finally {
      if (this.loadCoordinator.isCurrent(token)) this.loadingProjects = false;
    }
  }

  private toggle(id: string): void {
    this.projectSelection.toggle(id);
    this.selectedIds = this.projectSelection.selectedIds();
  }

  private async createBackup(): Promise<void> {
    const token: number | null = this.actionCoordinator.begin();
    if (token === null) return;
    this.busy = true; this.message = tr('正在校验项目并生成备份…',
      'Validating projects and generating a backup…'); this.result = null;
    this.messageError = false;
    try {
      const result: BackupResult = await new ProjectBackupService(AppRuntime.require()).create(this.selectedIds,
        this.includeOriginals, this.skipFailed);
      if (this.actionCoordinator.isCurrent(token)) {
        this.result = result;
        this.messageError = false;
        this.messageClock.show((next: string): void => {
          this.message = next;
        }, tr(`备份已生成：${result.projectCount} 个项目、${result.photoCount} 张照片` +
          (result.omittedFailed > 0 ? `，已按你的选择跳过 ${result.omittedFailed} 条失败记录` : ''),
          `Backup generated: ${result.projectCount} project${result.projectCount === 1 ? '' : 's'}, ` +
          `${result.photoCount} photo${result.photoCount === 1 ? '' : 's'}` +
          (result.omittedFailed > 0 ?
            `; skipped ${result.omittedFailed} failed record${result.omittedFailed === 1 ? '' : 's'}` : '')));
      }
    } catch (error) {
      if (this.actionCoordinator.isCurrent(token)) {
        this.message = userFacingMessage(error, '备份生成失败，请重试',
          'Backup failed. Please try again.');
        this.messageError = true;
      }
    } finally {
      if (this.actionCoordinator.finish(token)) this.busy = false;
    }
  }

  private async reconcileBackupWhenIdle(): Promise<void> {
    await this.actionCoordinator.whenIdle();
    if (!this.loadCoordinator.isActive()) return;
    this.busy = false;
    this.message = '';
    this.messageError = false;
    this.result = null;
    await this.load();
  }

  private async saveBackup(): Promise<void> {
    if (this.result === null) return;
    const token: number | null = this.actionCoordinator.begin();
    if (token === null) return;
    this.busy = true;
    const result: BackupResult = this.result;
    try {
      const outcome = await new ProjectBackupService(AppRuntime.require()).saveAs(result);
      if (this.actionCoordinator.isCurrent(token)) {
        this.messageError = false;
        this.messageClock.show((next: string): void => {
          this.message = next;
        }, outcome.channel === ExportDeliveryChannel.SHARE_PANEL ?
          tr('备份已在系统分享面板打开，可选择发送或保存',
            'The backup opened in the system share sheet. Send or save it from there.') :
          (outcome.delivered ? tr('备份已保存到你选择的位置', 'Backup saved to your chosen location') :
            tr('已取消保存；应用内生成的备份仍可再次保存',
              'Save cancelled; the generated backup can still be saved again')));
      }
    } catch (_) {
      if (this.actionCoordinator.isCurrent(token)) this.message = tr('保存失败，请释放存储空间或改选其他位置',
        'Save failed. Free storage or choose another location.');
      if (this.actionCoordinator.isCurrent(token)) this.messageError = true;
    } finally {
      if (this.actionCoordinator.finish(token)) this.busy = false;
    }
  }

  private async restoreBackup(): Promise<void> {
    const token: number | null = this.actionCoordinator.begin();
    if (token === null) return;
    this.busy = true; this.message = tr('正在选择并严格校验备份…',
      'Selecting and validating the backup…'); this.result = null;
    this.messageError = false;
    try {
      const restored = await new ProjectRestoreService(AppRuntime.require()).chooseAndRestore();
      if (restored === null) {
        if (this.actionCoordinator.isCurrent(token)) {
          this.messageError = false;
          this.messageClock.show((next: string): void => {
            this.message = next;
          }, tr('已取消恢复', 'Restore cancelled'));
        }
      } else {
        if (this.actionCoordinator.isCurrent(token)) {
          this.messageError = false;
          this.messageClock.show((next: string): void => {
            this.message = next;
          }, tr(`已恢复 ${restored.projectCount} 个项目、${restored.photoCount} 张照片` +
            (restored.renamedCount > 0 ? `；${restored.renamedCount} 个同名项目已自动添加“恢复”后缀` : ''),
            `Restored ${restored.projectCount} project${restored.projectCount === 1 ? '' : 's'} and ` +
            `${restored.photoCount} photo${restored.photoCount === 1 ? '' : 's'}` +
            (restored.renamedCount > 0 ?
              `; ${restored.renamedCount} duplicate name${restored.renamedCount === 1 ? '' : 's'} received a Restore suffix` : '')));
        }
        await this.load();
      }
    } catch (error) {
      if (this.actionCoordinator.isCurrent(token)) {
        this.message = userFacingMessage(error, '恢复失败，请重新选择备份',
          'Restore failed. Choose the backup again.');
        this.messageError = true;
      }
    } finally {
      if (this.actionCoordinator.finish(token)) this.busy = false;
    }
  }

  build() {
    NavDestination() {
      Column() {
        AppTopBar({ title: tr('备份与恢复', 'Backup and restore'), showBack: true,
          backAccessibilityText: settingsBackAccessibilityText(),
          onBack: (): void => { this.pathStack.pop(); } })
        List({ space: 14 }) {
          ListItem() {
            Column({ space: 6 }) {
              Text(tr('备份项目', 'Back up projects')).fontSize(19).fontWeight(FontWeight.Bold).width('100%')
              Text(tr('选择一个或多个项目。空白项目同样会保留项目说明和水印设置。',
                'Select one or more projects. Empty projects still retain their description and watermark settings.'))
                .fontSize(13).fontColor(UiTokens.TEXT_SECONDARY).lineHeight(19).width('100%')
            }.width('100%')
          }
          if (this.loadingProjects) {
            ListItem() {
              Text(tr('正在加载可备份项目…', 'Loading projects available for backup…'))
                .fontSize(14).fontColor(UiTokens.TEXT_SECONDARY).width('100%')
                .padding(16).backgroundColor(UiTokens.SURFACE).borderRadius(UiTokens.CARD_RADIUS)
                .border({ width: 1, color: UiTokens.OUTLINE_SUBTLE })
            }
          } else if (this.projectLoadError) {
            ListItem() {
              Column({ space: 8 }) {
                Text(tr('项目列表加载失败，请重试', 'Projects could not be loaded. Try again.'))
                  .fontSize(14).fontColor(UiTokens.DANGER).width('100%')
                Button(tr('重试', 'Retry')).height(UiTokens.TOUCH_TARGET).width('100%')
                  .backgroundColor(UiTokens.CONTROL).fontColor(UiTokens.PRIMARY)
                  .onClick((): void => { this.load(); })
              }.padding(16).width('100%').backgroundColor(UiTokens.SURFACE).borderRadius(UiTokens.CARD_RADIUS)
                .border({ width: 1, color: UiTokens.OUTLINE_SUBTLE })
            }
          } else if (this.projectCount === 0) {
            ListItem() {
              Text(tr('没有可备份的项目', 'No projects available for backup'))
                .fontSize(14).fontColor(UiTokens.TEXT_SECONDARY).width('100%')
                .padding(16).backgroundColor(UiTokens.SURFACE).borderRadius(UiTokens.CARD_RADIUS)
                .border({ width: 1, color: UiTokens.OUTLINE_SUBTLE })
            }
          } else {
            LazyForEach(this.projectSelection.data, (item: ProjectSummary) => {
              ListItem() {
                Row({ space: 12 }) {
                  Text(this.projectSelection.isSelected(item.project.id) ? '✓' : '')
                    .width(UiTokens.TOUCH_TARGET).height(UiTokens.TOUCH_TARGET).textAlign(TextAlign.Center)
                    .fontColor(this.projectSelection.isSelected(item.project.id) ?
                      UiTokens.ON_PRIMARY : UiTokens.TEXT_SECONDARY)
                    .backgroundColor(this.projectSelection.isSelected(item.project.id) ?
                      UiTokens.PRIMARY : UiTokens.SURFACE_MUTED)
                    .border({ width: 1, color: this.projectSelection.isSelected(item.project.id) ?
                      UiTokens.PRIMARY : UiTokens.OUTLINE_SUBTLE })
                    .borderRadius(UiTokens.TOUCH_TARGET / 2)
                  Column({ space: 3 }) {
                    Text(item.project.name).fontSize(16).fontWeight(FontWeight.Medium).width('100%')
                    Text(tr(`${item.captureCount} 条记录 · ${lifecycleLabel(item.project.lifecycleStatus)}`,
                      `${item.captureCount} record${item.captureCount === 1 ? '' : 's'} · ` +
                      `${lifecycleLabel(item.project.lifecycleStatus)}`))
                      .fontSize(13).fontColor(UiTokens.TEXT_SECONDARY).width('100%')
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                }
                .constraintSize({ minHeight: 64 })
                .padding({ left: 12, right: 12, top: 10, bottom: 10 }).width('100%')
                .backgroundColor(UiTokens.SURFACE).borderRadius(UiTokens.CARD_RADIUS)
                .border({ width: 1, color: UiTokens.OUTLINE_SUBTLE })
                .accessibilityText(this.projectSelection.isSelected(item.project.id) ?
                  tr(`已选择：${item.project.name}`, `Selected: ${item.project.name}`) :
                  tr(`未选择：${item.project.name}`, `Not selected: ${item.project.name}`))
                .onClick((): void => this.toggle(item.project.id))
              }
            }, (item: ProjectSummary): string => item.project.id)
          }
          ListItem() {
            Row() {
              Column({ space: 3 }) {
                Text(tr('包含私有原图', 'Include private originals')).fontSize(15)
                  .fontWeight(FontWeight.Medium).width('100%')
                Text(tr('文件更大；已清理原图的项目需关闭此项',
                  'Creates larger files; disable this for projects with cleared originals')).fontSize(12)
                  .fontColor(UiTokens.TEXT_SECONDARY).width('100%')
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Toggle({ type: ToggleType.Switch, isOn: this.includeOriginals })
                .selectedColor(UiTokens.PRIMARY).accessibilityText(tr('包含私有原图', 'Include private originals'))
                .onChange((value: boolean): void => { this.includeOriginals = value; })
            }.padding(14).width('100%').backgroundColor(UiTokens.SURFACE).borderRadius(UiTokens.CARD_RADIUS)
              .border({ width: 1, color: UiTokens.OUTLINE_SUBTLE })
          }
          ListItem() {
            Row() {
              Column({ space: 3 }) {
                Text(tr('仅备份已完成记录', 'Back up completed records only')).fontSize(15)
                  .fontWeight(FontWeight.Medium).width('100%')
                Text(tr('遇到失败记录时明确跳过；处理中记录始终阻止备份',
                  'Explicitly skips failed records; processing records always block backup')).fontSize(12)
                  .fontColor(UiTokens.TEXT_SECONDARY).width('100%')
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Toggle({ type: ToggleType.Switch, isOn: this.skipFailed })
                .selectedColor(UiTokens.PRIMARY).accessibilityText(tr('仅备份已完成记录', 'Back up completed records only'))
                .onChange((value: boolean): void => { this.skipFailed = value; })
            }.padding(14).width('100%').backgroundColor(UiTokens.SURFACE).borderRadius(UiTokens.CARD_RADIUS)
              .border({ width: 1, color: UiTokens.OUTLINE_SUBTLE })
          }
          ListItem() {
            Button(this.busy ? tr('正在处理…', 'Working…') :
              tr(`生成备份（已选 ${this.selectedIds.length} 个）`,
                `Generate backup (${this.selectedIds.length} selected)`))
              .height(50).width('100%').backgroundColor(UiTokens.PRIMARY).fontColor(UiTokens.ON_PRIMARY)
              .enabled(!this.busy && this.selectedIds.length > 0).onClick((): void => { this.createBackup(); })
          }
          if (this.result !== null) {
            ListItem() {
              Button(tr('保存到其他位置', 'Save to another location')).height(46).width('100%')
                .backgroundColor(UiTokens.PRIMARY_CONTAINER)
                .fontColor(UiTokens.PRIMARY).enabled(!this.busy).onClick((): void => { this.saveBackup(); })
            }
          }
          if (this.busy) {
            ListItem() {
              Row({ space: 10 }) {
                LoadingProgress().width(22).height(22).color(UiTokens.PRIMARY)
                Text(tr('正在处理，请稍候…', 'Working, please wait…')).fontSize(13)
                  .fontColor(UiTokens.TEXT_SECONDARY)
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
            }
          }
          if (this.message.length > 0) {
            ListItem() {
              Text(this.message).fontSize(13).fontColor(this.messageError ? UiTokens.DANGER : UiTokens.PRIMARY)
                .lineHeight(20).width('100%')
            }
          }
          ListItem() {
            Column({ space: 8 }) {
              Divider().color(UiTokens.OUTLINE_SUBTLE).margin({ top: 8, bottom: 4 })
              Text(tr('恢复项目', 'Restore projects')).fontSize(19).fontWeight(FontWeight.Bold).width('100%')
              Text(tr('请选择由 SiteMark“备份项目”生成的单项目 ZIP 或多项目 bundle；普通照片分享 ZIP 无法恢复。',
                'Choose a project ZIP or multi-project bundle created by SiteMark Backup. Ordinary photo-sharing ZIP files cannot be restored.'))
                .fontSize(13).fontColor(UiTokens.TEXT_SECONDARY).lineHeight(19).width('100%')
              Button(tr('选择备份 ZIP', 'Choose backup ZIP')).height(46).width('100%').backgroundColor(UiTokens.SURFACE_MUTED)
              .fontColor(UiTokens.PRIMARY).enabled(!this.busy)
              .onClick((): void => { this.restoreBackup(); })
              Text(tr('系统相册中的照片独立保留；重要备份请保存到应用目录之外。',
                'System gallery photos remain independent. Save important backups outside the app directory.'))
                .fontSize(12).fontColor(UiTokens.TEXT_SECONDARY).lineHeight(18).width('100%')
            }.width('100%')
          }
        }
        .cachedCount(4)
        .padding({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING, top: 10,
          bottom: 40 + this.safeAreaBottomVp })
        .width('100%')
        .layoutWeight(1)
      }.width('100%').height('100%').backgroundColor(UiTokens.BACKGROUND)
    }.hideTitleBar(true)
  }
}
