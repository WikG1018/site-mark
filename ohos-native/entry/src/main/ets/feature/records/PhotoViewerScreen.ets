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
import { PhotoViewerGestureState, RecordNavigationSeedStore, ViewerNodePolicy,
  ViewerRenderedVersionTracker } from './RecordUiCoordinator';

class RuntimePhotoViewerWindowLoader implements PhotoViewerWindowLoader {
  captureViewerWindow(captureId: string): Promise<CaptureViewerWindow> {
    return AppRuntime.require().database.captureViewerWindow(captureId, 2);
  }
}

@Component
export struct PhotoViewerScreen {
  @Consume('pathStack') pathStack: NavPathStack;
  @State private viewerRevision: number = 0;
  @State private gestureRevision: number = 0;
  private readonly pageState: ListPageCoordinator = new ListPageCoordinator();
  private readonly gestureState: PhotoViewerGestureState = new PhotoViewerGestureState();
  private readonly renderedVersion: ViewerRenderedVersionTracker = new ViewerRenderedVersionTracker();
  private readonly controller: PhotoViewerWindowController = new PhotoViewerWindowController(
    new RuntimePhotoViewerWindowLoader(), (): void => { this.viewerRevision += 1; });
  private readonly refreshListener: () => void = (): void => { this.reloadCurrent(); };
  private seededCaptureId: string = '';
  private seededUri: string = '';
  private readonly memoryListener: (level: number) => void = (_level: number): void => {
    this.controller.shrinkToCurrent();
  };

  aboutToAppear(): void {
    this.applyNavigationSeed();
    this.activatePage();
  }

  aboutToDisappear(): void {
    this.deactivatePage();
  }

  private activatePage(): void {
    if (!this.pageState.activate()) {
      return;
    }
    const runtime = AppRuntime.require();
    runtime.subscribe(this.refreshListener);
    runtime.uiMemory.register(this.memoryListener);
    this.reloadCurrent();
  }

  private deactivatePage(): void {
    if (!this.pageState.deactivate()) {
      return;
    }
    this.controller.invalidate();
    AppRuntime.current?.unsubscribe(this.refreshListener);
    AppRuntime.current?.uiMemory.unregister(this.memoryListener);
  }

  private applyNavigationSeed(): void {
    const seed = RecordNavigationSeedStore.take(AppRuntime.require().selectedCaptureId);
    if (seed === null) {
      return;
    }
    this.seededCaptureId = seed.capture.id;
    this.seededUri = seed.uri;
    this.controller.seed(seed.capture);
  }

  private reloadCurrent(): void {
    if (!this.pageState.isActive()) {
      return;
    }
    const captureId = this.controller.currentCaptureId().length > 0 ?
      this.controller.currentCaptureId() : AppRuntime.require().selectedCaptureId;
    if (captureId.length > 0) {
      this.controller.loadAround(captureId);
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

  private photoUri(capture: CaptureRecord): string {
    if (capture.id === this.seededCaptureId && this.seededUri.length > 0) {
      return this.seededUri;
    }
    const path = capture.renderedPath.length > 0 ? capture.renderedPath : capture.originalPath;
    return path.length > 0 ? imageUri(path) : '';
  }

  private photoRequestVersion(capture: CaptureRecord): number {
    return this.renderedVersion.versionFor(capture.id, capture.status === 'ready', capture.processingAttempts);
  }

  private beginPinch(): void {
    this.gestureState.beginPinch();
  }

  private updatePinch(scale: number): void {
    this.gestureState.updatePinch(scale);
    this.gestureRevision += 1;
  }

  private resetScale(): void {
    this.gestureState.resetAfterMove();
    this.gestureRevision += 1;
  }

  private moveTo(index: number): void {
    if (!this.pageState.isActive() || index < 0 || index >= this.controller.rows.length ||
      index === this.controller.currentIndex) {
      return;
    }
    const selected = this.controller.rows[index];
    AppRuntime.require().selectedCaptureId = selected.id;
    this.resetScale();
    this.controller.moveTo(index);
  }

  @Builder
  private currentPhoto(capture: CaptureRecord) {
    Stack() {
      Row().width('100%').height('100%').backgroundColor(Color.Black)
      AppImage({ uri: this.photoUri(capture), decodeEdge: ViewerNodePolicy.decodeEdge(false),
        fit: ImageFit.Contain })
        .width('100%').height('100%')
      AppImage({ uri: this.photoUri(capture), requestVersion: this.photoRequestVersion(capture),
        decodeEdge: ViewerNodePolicy.decodeEdge(true), fit: ImageFit.Contain, transparentPlaceholder: true })
        .width('100%').height('100%')
    }
    .width('100%')
    .height('100%')
    .scale({ x: this.gestureRevision >= 0 ? this.gestureState.scale : 1,
      y: this.gestureState.scale })
    .sharedTransition(`capture-photo-${capture.id}`,
      { duration: ViewerNodePolicy.transitionDuration(MotionPolicy.reduceMotion), curve: Curve.Friction })
    .accessibilityText(tr(`全屏照片 ${capture.photoNumber}`, `Full-screen photo ${capture.photoNumber}`))
    .gesture(PinchGesture()
      .onActionStart((): void => { this.beginPinch(); })
      .onActionUpdate((event: GestureEvent): void => { this.updatePinch(event.scale); }))
    .onClick((): void => {
      if (this.gestureState.scale > 1) {
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
      this.currentPhoto(capture)
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
          .duration(MotionPolicy.duration(UiTokens.MOTION_STANDARD))
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
        Button('‹')
          .width(46)
          .height(46)
          .fontSize(32)
          .fontColor(Color.White)
          .backgroundColor('#66000000')
          .borderRadius(23)
          .margin({ left: 16, top: 18 })
          .accessibilityText(tr('返回记录详情', 'Back to record details'))
          .onClick((): void => { this.pathStack.pop(); })
        if (this.controller.rows.length > 0) {
          Text(`${this.controller.absoluteIndex + 1} / ${this.controller.totalCount}`)
            .fontSize(13)
            .fontColor(Color.White)
            .backgroundColor('#66000000')
            .padding({ left: 12, right: 12, top: 7, bottom: 7 })
            .borderRadius(16)
            .margin({ top: 26 })
            .align(Alignment.Top)
            .accessibilityText(tr(`第 ${this.controller.absoluteIndex + 1} 张，共 ${this.controller.totalCount} 张`,
              `Photo ${this.controller.absoluteIndex + 1} of ${this.controller.totalCount}`))
        }
        if (this.controller.failed && this.controller.rows.length > 0) {
          Button(`↻  ${tr('重试', 'Retry')}`)
            .height(UiTokens.TOUCH_TARGET)
            .fontSize(13)
            .fontColor(Color.White)
            .backgroundColor('#66000000')
            .borderRadius(UiTokens.CONTROL_RADIUS)
            .margin({ bottom: 24 })
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
            .backgroundColor('#66000000')
            .borderRadius(UiTokens.CONTROL_RADIUS)
            .margin({ bottom: 24 })
            .align(Alignment.Bottom)
            .accessibilityText(tr('加载当前照片附近的照片', 'Load photos near the current photo'))
            .onClick((): void => { this.controller.refill(); })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Black)
    }
    .hideTitleBar(true)
    .onShown((): void => { this.activatePage(); })
    .onHidden((): void => { this.deactivatePage(); })
  }
}
