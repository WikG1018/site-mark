import { common } from '@kit.AbilityKit';
import { AbilityContextHolder } from '../app/AbilityContextHolder';
import { AppRuntime } from '../app/AppRuntime';
import { Routes } from '../app/Routes';
import { PreferencesConsentStorage } from '../data/prefs/PreferencesConsentStorage';
import { PrivacyConsentStore } from '../data/prefs/PrivacyConsentStore';
import { CaptureDetailScreen, CaptureEditorScreen, CaptureFormScreen, AllRecordsView,
  PhotoViewerScreen } from '../feature/records/RecordScreens';
import { ProjectDetailScreen, ProjectEditorScreen, ProjectListView,
  ProjectSettingsScreen } from '../feature/projects/ProjectScreens';
import { AboutScreen, AppearanceScreen, BackupScreen, DiagnosticsScreen, SettingsView,
  StorageScreen } from '../feature/settings/SettingsScreens';
import { UiTokens } from '../shared/UiTokens';
import { AppText, tr } from '../shared/AppText';
import { MotionPolicy } from '../shared/MotionPolicy';
import { RootMotionSpec, RootShellPolicy, RootTabTransition } from '../shared/RootShellPolicy';

@Entry
@Component
struct Index {
  @Provide('pathStack') pathStack: NavPathStack = new NavPathStack();
  @State private consentChecked: boolean = false;
  @State private consentAccepted: boolean = false;
  @State private runtimeReady: boolean = false;
  @State private runtimeError: string = '';
  @State private activeTab: number = 0;
  @State private tabDirection: number = 1;
  @State private selectionMode: boolean = false;
  @State private appearanceRevision: number = 0;
  @State private motionRevision: number = 0;
  private lifecycleGeneration: number = 0;
  private tabMotionGeneration: number = 0;
  private pendingTabMotion: number = 0;
  private queuedTabIndex: number = -1;
  private rootVisible: boolean = false;
  private consentStore: PrivacyConsentStore = new PrivacyConsentStore(
    new PreferencesConsentStorage(AbilityContextHolder.require()));
  private readonly runtimeListener: () => void = (): void => {
    const runtime = AppRuntime.current;
    this.selectionMode = runtime?.rootSelectionMode ?? false;
    this.appearanceRevision += 1;
  };

  aboutToAppear(): void {
    this.rootVisible = true;
    this.lifecycleGeneration += 1;
    AppText.apply('', this.context().resourceManager.getConfigurationSync().locale);
    this.refreshMotionPolicy();
    this.checkConsent();
  }

  aboutToDisappear(): void {
    this.deactivateRootShell();
    AppRuntime.current?.unsubscribe(this.runtimeListener);
  }

  aboutToBeDeleted(): void {
    this.deactivateRootShell();
    AppRuntime.current?.unsubscribe(this.runtimeListener);
  }

  onPageShow(): void {
    this.rootVisible = true;
    this.lifecycleGeneration += 1;
    this.refreshMotionPolicy();
  }

  onPageHide(): void {
    this.deactivateRootShell();
  }

  private context(): common.UIAbilityContext {
    return AbilityContextHolder.require();
  }

  private async checkConsent(): Promise<void> {
    try {
      this.consentAccepted = await this.consentStore.isAccepted();
    } catch (_) {
      this.consentAccepted = false;
    }
    this.consentChecked = true;
    if (this.consentAccepted) {
      await this.initializeRuntime();
    }
  }

  private async acceptPrivacy(): Promise<void> {
    await this.consentStore.accept();
    this.consentAccepted = true;
    await this.initializeRuntime();
  }

  private async initializeRuntime(): Promise<void> {
    this.runtimeError = '';
    try {
      const runtime = await AppRuntime.initialize(this.context());
      runtime.subscribe(this.runtimeListener);
      await this.refreshMotionPolicy();
      this.runtimeReady = true;
      this.runtimeListener();
    } catch (_) {
      this.runtimeError = tr('本机数据初始化失败。请释放存储空间后重试；现有数据不会被自动删除。',
        'Local data could not be initialized. Free some storage and try again; existing data will not be deleted.');
    }
  }

  private async refreshMotionPolicy(): Promise<void> {
    const generation = this.lifecycleGeneration;
    try {
      await MotionPolicy.refresh();
    } catch (_) {
    }
    if (!this.rootVisible || generation !== this.lifecycleGeneration) {
      return;
    }
    try {
      this.pathStack.disableAnimation(MotionPolicy.reduceMotion);
    } catch (_) {
    }
    this.motionRevision += 1;
  }

  private deactivateRootShell(): void {
    this.rootVisible = false;
    this.lifecycleGeneration += 1;
    this.tabMotionGeneration += 1;
    this.pendingTabMotion = 0;
    this.queuedTabIndex = -1;
  }

  private switchTab(index: number): void {
    const transition: RootTabTransition = RootShellPolicy.transition(
      this.activeTab, index, this.pendingTabMotion !== 0);
    if (!transition.changed) {
      if (this.pendingTabMotion !== 0) {
        this.queuedTabIndex = -1;
      }
      return;
    }
    if (transition.deferUntilSettled) {
      this.queuedTabIndex = transition.targetIndex;
      return;
    }
    const motion: RootMotionSpec = RootShellPolicy.motion(transition.direction);
    if (motion.dockDuration === 0) {
      this.tabDirection = transition.direction;
      this.activeTab = transition.targetIndex;
      this.queuedTabIndex = -1;
      return;
    }
    const generation = this.tabMotionGeneration + 1;
    this.tabMotionGeneration = generation;
    this.pendingTabMotion = generation;
    this.getUIContext().animateTo({
      duration: motion.dockDuration,
      curve: Curve.EaseOut,
      onFinish: (): void => {
        if (this.rootVisible && this.pendingTabMotion === generation) {
          this.pendingTabMotion = 0;
          const queuedTab = this.queuedTabIndex;
          this.queuedTabIndex = -1;
          if (queuedTab >= 0) {
            this.switchTab(queuedTab);
          }
        }
      },
    }, (): void => {
      this.tabDirection = transition.direction;
      this.activeTab = transition.targetIndex;
    });
  }

  private contentTransition(): TransitionEffect {
    const motion: RootMotionSpec = RootShellPolicy.motion(this.tabDirection);
    return TransitionEffect.asymmetric(
      TransitionEffect.translate({ x: motion.enterX, y: 0 })
        .animation({ duration: motion.pageDuration, curve: Curve.EaseOut })
        .combine(TransitionEffect.opacity(0)
          .animation({ duration: motion.fadeDuration, curve: Curve.EaseOut })),
      TransitionEffect.translate({ x: motion.exitX, y: 0 })
        .animation({ duration: motion.pageDuration, curve: Curve.EaseOut })
        .combine(TransitionEffect.opacity(0)
          .animation({ duration: motion.fadeDuration, curve: Curve.EaseOut }))
    );
  }

  @Builder
  private pathMap(routeName: string) {
    if (routeName === Routes.PROJECT_DETAIL) {
      ProjectDetailScreen();
    } else if (routeName === Routes.PROJECT_EDITOR) {
      ProjectEditorScreen();
    } else if (routeName === Routes.PROJECT_SETTINGS) {
      ProjectSettingsScreen();
    } else if (routeName === Routes.CAPTURE_FORM) {
      CaptureFormScreen();
    } else if (routeName === Routes.CAPTURE_DETAIL) {
      CaptureDetailScreen();
    } else if (routeName === Routes.CAPTURE_EDITOR) {
      CaptureEditorScreen();
    } else if (routeName === Routes.PHOTO_VIEWER) {
      PhotoViewerScreen();
    } else if (routeName === Routes.BACKUP) {
      BackupScreen();
    } else if (routeName === Routes.STORAGE) {
      StorageScreen();
    } else if (routeName === Routes.DIAGNOSTICS) {
      DiagnosticsScreen();
    } else if (routeName === Routes.APPEARANCE) {
      AppearanceScreen();
    } else if (routeName === Routes.ABOUT) {
      AboutScreen();
    }
  }

  @Builder
  private dockItem(index: number, icon: Resource, label: string, selectedLabel: string) {
    Button() {
      Column({ space: 3 }) {
        Image(icon).width(23).height(23)
          .fillColor(this.activeTab === index ? UiTokens.PRIMARY : UiTokens.TEXT_SECONDARY)
          .accessibilityLevel('no')
        Text(label).fontSize(12).fontWeight(this.activeTab === index ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.activeTab === index ? UiTokens.PRIMARY : UiTokens.TEXT_SECONDARY)
          .accessibilityLevel('no')
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    }
    .layoutWeight(1)
    .height(RootShellPolicy.dockHeight())
    .backgroundColor(Color.Transparent)
    .borderRadius(UiTokens.CONTROL_RADIUS)
    .accessibilityGroup(true)
    .accessibilityText(this.activeTab === index ? selectedLabel : label)
    .onClick((): void => this.switchTab(index))
  }

  @Builder
  private floatingDock() {
    Stack({ alignContent: Alignment.TopStart }) {
      Row()
        .width(`${RootShellPolicy.dockSelectedOffset(100, 1)}%`)
        .height(RootShellPolicy.dockHeight() - 8)
        .position({ x: `${RootShellPolicy.dockSelectedOffset(100, this.activeTab)}%`, y: 4 })
        .backgroundColor(MotionPolicy.reduceMotion ? UiTokens.PRIMARY_CONTAINER : UiTokens.DOCK_SELECTED)
        .backdropBlur(RootShellPolicy.motion(this.tabDirection).selectionBlur)
        .borderRadius(UiTokens.CARD_RADIUS + 4)
        .hitTestBehavior(HitTestMode.None)
        .accessibilityLevel('no')
      Row() {
        this.dockItem(0, $r('app.media.ic_projects'), tr('项目', 'Projects'),
          tr('项目，已选择', 'Projects, selected'))
        this.dockItem(1, $r('app.media.ic_records'), tr('全部记录', 'Records'),
          tr('全部记录，已选择', 'Records, selected'))
        this.dockItem(2, $r('app.media.ic_settings'), tr('设置', 'Settings'),
          tr('设置，已选择', 'Settings, selected'))
      }.width('100%').height('100%')
    }
    .height(RootShellPolicy.dockHeight())
    .margin({ bottom: RootShellPolicy.dockBottomMargin() })
    .width(`calc(100% - ${RootShellPolicy.dockHorizontalMargin() * 2}vp)`)
    .backgroundColor(MotionPolicy.reduceMotion ? UiTokens.SURFACE : UiTokens.DOCK)
    .backdropBlur(RootShellPolicy.motion(this.tabDirection).dockBlur)
    .border({ width: 1, color: UiTokens.OUTLINE_SUBTLE })
    .borderRadius(UiTokens.CARD_RADIUS + 8)
    .shadow({ radius: 12, color: UiTokens.CARD_SHADOW, offsetY: 4 })
  }

  @Builder
  private rootContent() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.activeTab === 0) {
        ProjectListView().transition(this.contentTransition())
      } else if (this.activeTab === 1) {
        AllRecordsView().transition(this.contentTransition())
      } else {
        SettingsView().transition(this.contentTransition())
      }
      if (!this.selectionMode) {
        this.floatingDock()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(UiTokens.BACKGROUND)
  }

  @Builder
  private privacyGate() {
    Column() {
      Scroll() {
        Column({ space: 18 }) {
          Text('SiteMark').fontSize(38).fontWeight(FontWeight.Bold).fontColor(UiTokens.PRIMARY)
          Text(tr('工程印记 · 鸿蒙原生版', 'SiteMark · Native HarmonyOS')).fontSize(22)
            .fontWeight(FontWeight.Bold).fontColor(UiTokens.TEXT)
          Text(tr('开始前，请了解本应用如何处理你的数据与权限。',
            'Before continuing, please review how this app handles your data and permissions.'))
            .fontSize(15).fontColor(UiTokens.TEXT_SECONDARY).textAlign(TextAlign.Center)
          Column({ space: 13 }) {
            Text(tr('本机处理', 'On-device processing')).fontSize(17).fontWeight(FontWeight.Bold)
              .fontColor(UiTokens.PRIMARY).width('100%')
            Text(tr('项目、照片、水印和诊断均在本机处理；应用没有广告、账号、云同步或统计上传，也不申请网络权限。',
              'Projects, photos, watermarks, and diagnostics are processed on this device. There are no ads, accounts, cloud sync, analytics uploads, or network permission.'))
              .fontSize(14).lineHeight(22).fontColor(UiTokens.TEXT).width('100%')
            Text(tr('系统相机', 'System camera')).fontSize(17).fontWeight(FontWeight.Bold)
              .fontColor(UiTokens.PRIMARY).width('100%')
            Text(tr('拍照交给系统相机完成，SiteMark 不申请相机权限。返回后在后台串行生成水印。',
              'Photos are taken by the system camera, so SiteMark does not request camera permission. Watermarks are rendered serially after you return.'))
              .fontSize(14).lineHeight(22).fontColor(UiTokens.TEXT).width('100%')
            Text(tr('可选位置', 'Optional location')).fontSize(17).fontWeight(FontWeight.Bold)
              .fontColor(UiTokens.PRIMARY).width('100%')
            Text(tr('仅在你主动拍摄时请求一次前台位置。拒绝定位仍可正常拍照，应用不申请后台定位。',
              'Foreground location is requested only when you take a photo. You can keep shooting if you decline; background location is never requested.'))
              .fontSize(14).lineHeight(22).fontColor(UiTokens.TEXT).width('100%')
            Text(tr('相册与备份', 'Gallery and backups')).fontSize(17).fontWeight(FontWeight.Bold)
              .fontColor(UiTokens.PRIMARY).width('100%')
            Text(tr('保存成片、删除相册照片和选择备份位置时，会使用鸿蒙系统确认界面。卸载前请把重要备份保存到应用目录之外。',
              'HarmonyOS confirmation panels are used to save or delete gallery photos and choose backup locations. Save important backups outside the app before uninstalling.'))
              .fontSize(14).lineHeight(22).fontColor(UiTokens.TEXT).width('100%')
          }
          .padding(20).width('100%').backgroundColor(UiTokens.GLASS).borderRadius(UiTokens.CARD_RADIUS)
          Button(tr('同意并继续', 'Agree and continue')).height(54).width('100%').fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White).backgroundColor(UiTokens.PRIMARY).borderRadius(27)
            .onClick((): void => { this.acceptPrivacy(); })
          Button(tr('退出应用', 'Exit app')).height(44).width('100%').fontColor(UiTokens.TEXT_SECONDARY)
            .backgroundColor(Color.Transparent).onClick((): void => { this.context().terminateSelf(); })
        }
        .padding({ left: 24, right: 24, top: 52, bottom: 34 })
        .width('100%')
      }
      .width('100%').height('100%')
    }
    .width('100%').height('100%').backgroundColor(UiTokens.BACKGROUND)
  }

  build() {
    if (!this.consentChecked) {
      Column({ space: 14 }) {
        LoadingProgress().width(42).height(42).color(UiTokens.PRIMARY)
        Text(tr('正在准备工程印记…', 'Preparing SiteMark…')).fontSize(14).fontColor(UiTokens.TEXT_SECONDARY)
      }
      .width('100%').height('100%').justifyContent(FlexAlign.Center).backgroundColor(UiTokens.BACKGROUND)
    } else if (!this.consentAccepted) {
      this.privacyGate()
    } else if (this.runtimeError.length > 0) {
      Column({ space: 16 }) {
        Text(tr('无法启动', 'Unable to start')).fontSize(26).fontWeight(FontWeight.Bold).fontColor(UiTokens.TEXT)
        Text(this.runtimeError).fontSize(14).fontColor(UiTokens.TEXT_SECONDARY)
          .lineHeight(22).textAlign(TextAlign.Center).padding({ left: 32, right: 32 })
        Button(tr('重试', 'Retry')).height(46).backgroundColor(UiTokens.PRIMARY).fontColor(Color.White)
          .onClick((): void => { this.initializeRuntime(); })
      }.width('100%').height('100%').justifyContent(FlexAlign.Center).backgroundColor(UiTokens.BACKGROUND)
    } else if (!this.runtimeReady) {
      Column({ space: 14 }) {
        LoadingProgress().width(42).height(42).color(UiTokens.PRIMARY)
        Text(tr('正在恢复本机记录…', 'Recovering local records…')).fontSize(14)
          .fontColor(UiTokens.TEXT_SECONDARY)
      }.width('100%').height('100%').justifyContent(FlexAlign.Center).backgroundColor(UiTokens.BACKGROUND)
    } else {
      Navigation(this.pathStack) {
        this.rootContent()
      }
      .hideTitleBar(true)
      .navDestination(this.pathMap)
      .mode(NavigationMode.Stack)
    }
  }
}
