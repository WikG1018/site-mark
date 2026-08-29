import { window } from '@kit.ArkUI';
import { AppRuntime } from '../../app/AppRuntime';
import { CaptureRecord, CaptureViewerWindow } from '../../domain/Models';
import { AppImage } from '../../shared/AppImage';
import { InlineErrorPanel } from '../../shared/AppComponents';
import { tr } from '../../shared/AppText';
import { imageUri } from '../../shared/Formatters';
import { ListPageCoordinator } from '../../shared/ListPageCoordinator';
import { MotionPolicy } from '../../shared/MotionPolicy';
import { UiTokens } from '../../shared/UiTokens';
import { PhotoViewerWindowController, PhotoViewerWindowLoader } from './PhotoViewerWindow';
import { PhotoViewerGestureState, PhotoViewerPanTracker, RecordNavigationSeedStore,
  ViewerFullImageCoordinator, ViewerFullImageRequest, ViewerNavigationSeedCoordinator,
  ViewerNodePolicy, ViewerRenderedVersionTracker } from './RecordUiCoordinator';

class RuntimePhotoViewerWindowLoader implements PhotoViewerWindowLoader {
  captureViewerWindow(captureId: string): Promise<CaptureViewerWindow> {
    return AppRuntime.require().database.captureViewerWindow(captureId, 2);
  }
}

@Component
export struct PhotoViewerScreen {
  @Consume('pathStack') pathStack: NavPathStack;
  @State private viewerRevision: number = 0;
  @State private viewerScale: number = 1;
  @State private panOffsetX: number = 0;
  @State private panOffsetY: number = 0;
  @State private fullImageRevision: number = 0;
  private readonly pageState: ListPageCoordinator = new ListPageCoordinator();
  private readonly gestureState: PhotoViewerGestureState = new PhotoViewerGestureState();
  private readonly renderedVersion: ViewerRenderedVersionTracker = new ViewerRenderedVersionTracker();
  private readonly navigationSeed: ViewerNavigationSeedCoordinator = new ViewerNavigationSeedCoordinator();
  private readonly fullImage: ViewerFullImageCoordinator = new ViewerFullImageCoordinator();
  private panBaseX: number = 0;
  private panBaseY: number = 0;
  private readonly panTracker: PhotoViewerPanTracker = new PhotoViewerPanTracker();
  private viewportWidth: number = 0;
  private viewportHeight: number = 0;
  @State private topInsetVp: number = 0;
  @State private bottomInsetVp: number = 0;
  // Bumped on every applyViewerSystemBar entry so a slow in-flight call from a
  // superseded page activation cannot overwrite the newer window state.
  private systemBarGeneration: number = 0;
  private readonly controller: PhotoViewerWindowController = new PhotoViewerWindowController(
    new RuntimePhotoViewerWindowLoader(), (): void => { this.controllerChanged(); });
  private readonly refreshListener: () => void = (): void => { this.reloadCurrent(); };
  private readonly memoryListener: (level: number) => void = (_level: number): void => {
    this.controller.shrinkToCurrent();
  };
  private readonly targetLoadedHandler = (generation: number, _auxiliaryGeneration: number,
    captureId: string, uri: string): void => {
    if (this.pageState.isActive() && this.navigationSeed.targetLoaded(generation, captureId, uri)) {
      this.viewerRevision += 1;
    }
  };
  private readonly targetFailedHandler = (generation: number, _auxiliaryGeneration: number,
    captureId: string, uri: string): void => {
    if (this.pageState.isActive() && this.navigationSeed.targetFailed(generation, captureId, uri)) {
      this.viewerRevision += 1;
    }
  };
  private readonly fullLoadedHandler = (generation: number, targetGeneration: number,
    captureId: string, uri: string): void => {
    if (!this.pageState.isActive()) {
      return;
    }
    if (this.fullImage.complete(generation, captureId, uri)) {
      if (this.navigationSeed.targetLoaded(targetGeneration, captureId, uri)) {
        this.viewerRevision += 1;
      }
      this.fullImageRevision += 1;
    }
  };
  private readonly fullFailedHandler = (generation: number, targetGeneration: number,
    captureId: string, uri: string): void => {
    if (!this.pageState.isActive()) {
      return;
    }
    if (this.fullImage.fail(generation, captureId, uri)) {
      this.navigationSeed.targetFailed(targetGeneration, captureId, uri);
      this.fullImageRevision += 1;
    }
  };

  aboutToAppear(): void {
    this.activatePage();
  }

  aboutToDisappear(): void {
    this.deactivatePage();
  }

  private activatePage(): void {
    if (!this.pageState.activate()) {
      return;
    }
    this.applyViewerSystemBar(true);
    this.applyNavigationSeed();
    const runtime = AppRuntime.require();
    runtime.subscribe(this.refreshListener);
    runtime.uiMemory.register(this.memoryListener);
    this.reloadCurrent();
  }

  private deactivatePage(): void {
    if (!this.pageState.deactivate()) {
      return;
    }
    this.applyViewerSystemBar(false);
    this.navigationSeed.invalidateCallbacks();
    this.fullImage.invalidate();
    this.controller.invalidate();
    AppRuntime.current?.unsubscribe(this.refreshListener);
    AppRuntime.current?.uiMemory.unregister(this.memoryListener);
  }

  private applyNavigationSeed(): void {
    const seed = RecordNavigationSeedStore.take(AppRuntime.require().selectedCaptureId);
    if (seed === null) {
      return;
    }
    const contentVersion = this.renderedVersion.versionFor(seed.capture.id,
      seed.capture.status === 'ready', seed.capture.processingAttempts);
    this.navigationSeed.seed(seed.capture.id, seed.uri, contentVersion);
    this.controller.seed(seed.capture);
  }

  private async reloadCurrent(): Promise<void> {
    if (!this.pageState.isActive()) {
      return;
    }
    const captureId = this.controller.currentCaptureId().length > 0 ?
      this.controller.currentCaptureId() : AppRuntime.require().selectedCaptureId;
    if (captureId.length > 0) {
      await this.controller.loadAround(captureId);
    }
  }

  private retry(): void {
    if (this.pageState.isActive()) {
      this.controller.retry();
    }
  }

  private currentCaptureId(): string {
    return this.controller.currentCaptureId();
  }

  private rawPhotoUri(capture: CaptureRecord): string {
    const path = capture.renderedPath.length > 0 ? capture.renderedPath : capture.originalPath;
    return path.length > 0 ? imageUri(path) : '';
  }

  private photoUri(capture: CaptureRecord): string {
    return this.navigationSeed.sourceUriFor(capture.id, this.rawPhotoUri(capture));
  }

  private controllerChanged(): void {
    if (!this.pageState.isActive()) {
      return;
    }
    this.prepareCurrentFullImage();
    this.viewerRevision += 1;
  }

  private prepareCurrentFullImage(): void {
    if (this.controller.currentIndex < 0 || this.controller.currentIndex >= this.controller.rows.length) {
      return;
    }
    const capture = this.controller.rows[this.controller.currentIndex];
    const rawUri = this.rawPhotoUri(capture);
    const contentVersion = this.renderedVersion.versionFor(capture.id,
      capture.status === 'ready', capture.processingAttempts);
    this.navigationSeed.acceptTrustedWindow(capture.id, rawUri, contentVersion,
      this.controller.hasTrustedWindow(capture.id));
    this.fullImage.prepare(capture.id, this.photoUri(capture),
      this.navigationSeed.sourceContentVersionFor(capture.id, contentVersion));
  }

  private fullRequest(capture: CaptureRecord): ViewerFullImageRequest | null {
    const request = this.fullImage.current();
    if (request !== null && request.captureId === capture.id && request.uri === this.photoUri(capture)) {
      return request;
    }
    return null;
  }

  private retryFullImage(): void {
    if (this.pageState.isActive() && this.fullImage.retry() !== null) {
      this.fullImageRevision += 1;
    }
  }

  private beginPinch(): void {
    this.gestureState.beginPinch();
  }

  private updatePinch(scale: number): void {
    this.gestureState.updatePinch(scale);
    this.viewerScale = this.gestureState.scale;
    this.clampPan();
  }

  private animateTransform(update: () => void): void {
    this.getUIContext().animateTo({
      duration: MotionPolicy.duration(UiTokens.MOTION_STANDARD),
      curve: Curve.EaseOut
    }, update);
  }

  private settleZoom(): void {
    const zoomedOut = this.viewerScale < 1.05;
    if (zoomedOut) {
      this.gestureState.resetAfterMove();
    }
    this.animateTransform((): void => {
      if (zoomedOut) {
        this.viewerScale = 1;
      }
      this.clampPan();
    });
  }

  private toggleZoom(): void {
    if (this.viewerScale > 1) {
      this.resetScale();
    } else {
      this.gestureState.zoomTo(2.5);
      this.animateTransform((): void => {
        this.viewerScale = this.gestureState.scale;
        this.panOffsetX = 0;
        this.panOffsetY = 0;
      });
    }
  }

  private resetScale(animate: boolean = true): void {
    this.gestureState.resetAfterMove();
    if (animate) {
      this.animateTransform((): void => {
        this.viewerScale = 1;
        this.panOffsetX = 0;
        this.panOffsetY = 0;
      });
    } else {
      this.viewerScale = 1;
      this.panOffsetX = 0;
      this.panOffsetY = 0;
    }
  }

  private beginPan(): void {
    this.panBaseX = this.panOffsetX;
    this.panBaseY = this.panOffsetY;
  }

  private handleViewerTouch(event: TouchEvent): void {
    if (event.touches.length === 0) {
      return;
    }
    const touch = event.touches[0];
    const progressed = this.panTracker.onTouch(this.viewerScale > 1, event.type,
      event.touches.length, touch.id, touch.x, touch.y);
    if (this.panTracker.sessionBegan) {
      this.beginPan();
      return;
    }
    if (progressed) {
      this.updatePan(this.panTracker.deltaX, this.panTracker.deltaY);
    }
  }

  private updatePan(x: number, y: number): void {
    if (this.viewerScale <= 1) {
      return;
    }
    this.panOffsetX = this.clampAxis(this.panBaseX + x, this.viewportWidth);
    this.panOffsetY = this.clampAxis(this.panBaseY + y, this.viewportHeight);
  }

  private clampPan(): void {
    this.panOffsetX = this.clampAxis(this.panOffsetX, this.viewportWidth);
    this.panOffsetY = this.clampAxis(this.panOffsetY, this.viewportHeight);
  }

  private clampAxis(offset: number, viewportEdge: number): number {
    const maxOffset = Math.max(0, (this.viewerScale - 1) * viewportEdge / 2);
    return Math.max(-maxOffset, Math.min(maxOffset, Number.isFinite(offset) ? offset : 0));
  }

  private async applyViewerSystemBar(lightContent: boolean): Promise<void> {
    this.systemBarGeneration += 1;
    const generation = this.systemBarGeneration;
    const stale = (): boolean => generation !== this.systemBarGeneration;
    try {
      const win = await window.getLastWindow(AppRuntime.require().context);
      if (stale()) return;
      // True immersion while the viewer is on top: hide system bars
      // (immersive-sticky, matching Android). The window stays layout-fullscreen
      // for the rest of the process so the root shell can draw edge-to-edge.
      // Exit only re-enables status and navigation bars. Avoid-area insets are
      // re-read after the visibility change so chrome margins track whatever
      // the platform now reports (zero-height once the bars are hidden).
      if (lightContent) {
        await win.setWindowLayoutFullScreen(true);
        if (stale()) return;
        await win.setWindowSystemBarEnable([]);
        if (stale()) return;
      } else {
        await win.setWindowSystemBarEnable(['status', 'navigation']);
        if (stale()) return;
      }
      const area = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      if (stale()) return;
      // TYPE_SYSTEM reads zero while the system bars are hidden, so the
      // camera cutout must be folded in separately or the top chrome can
      // overlap a punch-hole on cutout devices.
      const cutout = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
      if (stale()) return;
      this.topInsetVp = Math.max(0, this.getUIContext()
        .px2vp(Math.max(area.topRect.height, cutout.topRect.height)));
      this.bottomInsetVp = Math.max(0, this.getUIContext().px2vp(area.bottomRect.height));
      const color = lightContent ? '#FFFFFF' : UiTokens.TEXT;
      if (stale()) return;
      await win.setWindowSystemBarProperties({
        statusBarContentColor: color,
        navigationBarContentColor: color
      });
    } catch (_) {
    }
  }

  private moveTo(index: number): void {
    if (!this.pageState.isActive() || index < 0 || index >= this.controller.rows.length ||
      index === this.controller.currentIndex) {
      return;
    }
    const selected = this.controller.rows[index];
    AppRuntime.require().selectedCaptureId = selected.id;
    this.resetScale(false);
    this.controller.moveTo(index);
  }

  @Builder
  private currentPhoto(capture: CaptureRecord, request: ViewerFullImageRequest | null) {
    Stack() {
      Row().width('100%').height('100%').backgroundColor(Color.Black)
      if (this.navigationSeed.backingUriFor(capture.id).length > 0) {
        AppImage({ uri: this.navigationSeed.backingUriFor(capture.id),
          requestVersion: this.navigationSeed.backingContentVersionFor(capture.id),
          decodeEdge: ViewerNodePolicy.decodeEdge(false), fit: ImageFit.Contain })
          .width('100%').height('100%')
      }
      if (this.navigationSeed.shouldRenderTarget(capture.id)) {
        AppImage({ uri: this.photoUri(capture),
          requestVersion: this.navigationSeed.targetRequestVersionFor(capture.id,
            request === null ? 0 : request.contentVersion),
          decodeEdge: ViewerNodePolicy.decodeEdge(false), fit: ImageFit.Contain,
          transparentPlaceholder: this.navigationSeed.backingUriFor(capture.id).length > 0,
          callbackToken: this.navigationSeed.targetGenerationFor(capture.id), callbackKey: capture.id,
          onLoaded: this.targetLoadedHandler, onFailed: this.targetFailedHandler })
          .width('100%').height('100%')
      }
      if (request !== null) {
        AppImage({ uri: request.uri,
          requestVersion: this.fullImageRevision >= 0 ? request.requestVersion : 0,
          decodeEdge: ViewerNodePolicy.decodeEdge(true), fit: ImageFit.Contain, transparentPlaceholder: true,
          callbackToken: request.generation,
          callbackAuxToken: this.navigationSeed.targetGenerationFor(capture.id), callbackKey: capture.id,
          onLoaded: this.fullLoadedHandler, onFailed: this.fullFailedHandler })
          .width('100%').height('100%')
      }
      if (this.fullImageRevision >= 0 && this.fullImage.isFailedFor(capture.id, this.photoUri(capture))) {
        Button(`↻  ${tr('重试高清图', 'Retry full image')}`)
          .height(UiTokens.TOUCH_TARGET)
          .fontSize(13)
          .fontColor(Color.White)
          .backgroundColor(UiTokens.OVERLAY)
          .borderRadius(UiTokens.CONTROL_RADIUS)
          // Below the "n / N" counter pill (TopEnd, top 26+inset): both
          // rendered over the photo when the full image fails, and at the
          // same top offset they drew on top of each other.
          .margin({ right: 16, top: 78 + this.topInsetVp })
          .align(Alignment.TopEnd)
          .accessibilityText(tr('重新加载当前高清照片', 'Reload the current full-resolution photo'))
          .onClick((): void => { this.retryFullImage(); })
      }
    }
    .width('100%')
    .height('100%')
    .scale({ x: this.viewerScale, y: this.viewerScale })
    .translate({ x: this.panOffsetX, y: this.panOffsetY })
    .onAreaChange((_oldValue: Area, newValue: Area): void => {
      this.viewportWidth = typeof newValue.width === 'number' ? newValue.width : 0;
      this.viewportHeight = typeof newValue.height === 'number' ? newValue.height : 0;
    })
    // Navigation 跨页面共享元素转场：列表卡片 → 详情 → 查看器同 id 匹配；系统控制插值，跟随系统减少动画
    .geometryTransition(`capture-photo-${capture.id}`)
    .accessibilityText(tr(`全屏照片 ${capture.photoNumber}`, `Full-screen photo ${capture.photoNumber}`))
    .gesture(GestureGroup(GestureMode.Parallel,
      PinchGesture()
        .onActionStart((): void => { this.beginPinch(); })
        .onActionUpdate((event: GestureEvent): void => { this.updatePinch(event.scale); })
        .onActionEnd((): void => { this.settleZoom(); }),
      TapGesture({ count: 2 })
        .onAction((): void => { this.toggleZoom(); })
    ))
    .onTouch((event: TouchEvent): void => { this.handleViewerTouch(event); })
    .onClick((): void => {
      if (this.viewerScale > 1) {
        this.resetScale();
      }
    })
  }

  @Builder
  private previewPhoto(capture: CaptureRecord) {
    Stack() {
      Row().width('100%').height('100%').backgroundColor(Color.Black)
      AppImage({ uri: this.photoUri(capture), decodeEdge: ViewerNodePolicy.decodeEdge(false),
        fit: ImageFit.Contain })
        .width('100%').height('100%')
    }
    .width('100%')
    .height('100%')
    .accessibilityText(tr(`照片 ${capture.photoNumber}`, `Photo ${capture.photoNumber}`))
  }

  @Builder
  private photoPage(capture: CaptureRecord) {
    if (capture.id === this.currentCaptureId()) {
      this.currentPhoto(capture, this.fullRequest(capture))
    } else {
      this.previewPhoto(capture)
    }
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.viewerRevision >= 0 && this.controller.rows.length > 0) {
          Swiper() {
            ForEach(this.controller.rows, (capture: CaptureRecord) => {
              this.photoPage(capture)
            }, (capture: CaptureRecord): string => ViewerNodePolicy.key(capture.id,
              capture.id === this.currentCaptureId()))
          }
          .width('100%')
          .height('100%')
          .index(this.controller.currentIndex)
          .cachedCount(1)
          .loop(false)
          .indicator(false)
          .duration(MotionPolicy.duration(ViewerNodePolicy.SWIPE_DURATION))
          .disableSwipe(!this.gestureState.canSwipe())
          .onChange((index: number): void => { this.moveTo(index); })
        } else if (this.controller.loading) {
          Column() {
            LoadingProgress().width(34).height(34).color(Color.White)
          }.width('100%').height('100%').justifyContent(FlexAlign.Center)
        } else if (this.controller.failed) {
          Column() {
            InlineErrorPanel({ message: tr('照片暂时无法加载', 'The photo could not be loaded'),
              retryLabel: tr('重试', 'Retry'), onRetry: (): void => { this.retry(); } })
          }
          .width('100%')
          .height('100%')
          .padding({ left: 24, right: 24 })
          .justifyContent(FlexAlign.Center)
        }
        if (this.controller.rows.length > 0) {
          Text(`${this.controller.absoluteIndex + 1} / ${this.controller.totalCount}`)
            .fontSize(13)
            .fontColor(Color.White)
            .backgroundColor(UiTokens.OVERLAY)
            .padding({ left: 12, right: 12, top: 7, bottom: 7 })
            .borderRadius(16)
            .margin({ right: 16, top: 26 + this.topInsetVp })
            .align(Alignment.TopEnd)
            .hitTestBehavior(HitTestMode.None)
            .accessibilityText(tr(`第 ${this.controller.absoluteIndex + 1} 张，共 ${this.controller.totalCount} 张`,
              `Photo ${this.controller.absoluteIndex + 1} of ${this.controller.totalCount}`))
        }
        Button() {
          Text('‹')
            .fontSize(26)
            .fontColor(Color.White)
            .width('100%')
            .textAlign(TextAlign.Center)
            .accessibilityLevel('no')
        }
        .width(46)
        .height(46)
        .backgroundColor(UiTokens.OVERLAY)
        .borderRadius(23)
        .margin({ left: 16, top: 18 + this.topInsetVp })
        .accessibilityText(tr('返回记录详情', 'Back to record details'))
        .onClick((): void => { this.pathStack.pop(); })
        if (this.controller.failed && this.controller.rows.length > 0) {
          Button() {
            Row({ space: 6 }) {
              Text('↻').fontSize(15).fontColor(Color.White)
                .accessibilityLevel('no')
              Text(tr('重试', 'Retry')).fontSize(13).fontColor(Color.White)
            }
            .alignItems(VerticalAlign.Center)
          }
          .height(UiTokens.TOUCH_TARGET)
          .padding({ left: 12, right: 12 })
          .backgroundColor(UiTokens.OVERLAY)
          .borderRadius(UiTokens.CONTROL_RADIUS)
          .margin({ bottom: 24 + this.bottomInsetVp })
          .align(Alignment.Bottom)
          .accessibilityText(tr('重试加载附近照片', 'Retry loading nearby photos'))
          .onClick((): void => { this.retry(); })
        }
        if (this.controller.needsRefill && !this.controller.loading && !this.controller.failed &&
          this.controller.rows.length > 0) {
          Button(`↔  ${tr('继续浏览', 'Continue browsing')}`)
            .height(UiTokens.TOUCH_TARGET)
            .fontSize(13)
            .fontColor(Color.White)
            .backgroundColor(UiTokens.OVERLAY)
            .borderRadius(UiTokens.CONTROL_RADIUS)
            .margin({ bottom: 24 + this.bottomInsetVp })
            .align(Alignment.Bottom)
            .accessibilityText(tr('加载当前照片附近的照片', 'Load photos near the current photo'))
            .onClick((): void => { this.controller.refill(); })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Black)
      .expandSafeArea([SafeAreaType.SYSTEM])
    }
    .hideTitleBar(true)
    .onShown((): void => { this.activatePage(); })
    .onHidden((): void => { this.deactivatePage(); })
  }
}
