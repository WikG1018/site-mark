import { CaptureRecord } from '../../domain/Models';
import { CaptureStatus } from '../../domain/StateMachine';
import { formatDay, imageUri, statusLabel } from '../../shared/Formatters';
import { UiTokens } from '../../shared/UiTokens';
import { tr } from '../../shared/AppText';
import { AppImage, ImageDecodePolicy } from '../../shared/AppImage';
import { MotionPolicy } from '../../shared/MotionPolicy';
import { ViewerNodePolicy } from './RecordUiCoordinator';

@Component
export struct CaptureInfoRow {
  @Prop label: string = '';
  @Prop value: string = '';

  build() {
    Row({ space: 12 }) {
      Text(this.label).fontSize(13).fontColor(UiTokens.TEXT_SECONDARY).width(78)
      Text(this.value.length > 0 ? this.value : '—').fontSize(14).fontColor(UiTokens.TEXT)
        .layoutWeight(1).maxLines(4)
    }.width('100%').alignItems(VerticalAlign.Top)
  }
}

@Component
export struct CaptureCard {
  @Prop capture: CaptureRecord = new CaptureRecord({
    id: '', projectId: '', projectName: '', photoNumber: '', workLocation: '', workContent: '',
    photographer: '', notes: '', originalPath: '', renderedPath: '', publishedUri: '',
    originalSha256: '', status: CaptureStatus.CAPTURED, failureReason: '', createdAt: 0, capturedAt: 0,
    latitude: null, longitude: null, accuracyMeters: null, address: '', locationOutcome: '',
    processingAttempts: 0, watermarkLocaleCode: 'zh', locationResolution: 'resolved',
    originalDeletedAt: null
  });
  @Prop selectionMode: boolean = false;
  @Prop selected: boolean = false;
  @Prop showProject: boolean = false;
  @State private pressed: boolean = false;
  onOpen: () => void = (): void => {};
  onToggle: () => void = (): void => {};

  private cardAccessibilityText(): string {
    const details = tr(`照片 ${this.capture.photoNumber}，${this.capture.workLocation}，${this.capture.workContent}`,
      `Photo ${this.capture.photoNumber}, ${this.capture.workLocation}, ${this.capture.workContent}`);
    if (!this.selectionMode) {
      return details;
    }
    return this.selected ? tr(`${details}，已选择`, `${details}, selected`) :
      tr(`${details}，未选择`, `${details}, not selected`);
  }

  @Builder
  private thumbnail() {
    Stack({ alignContent: Alignment.TopStart }) {
      AppImage({ uri: this.capture.renderedPath.length > 0 ? imageUri(this.capture.renderedPath) :
        (this.capture.originalPath.length > 0 ? imageUri(this.capture.originalPath) : ''),
        decodeEdge: ImageDecodePolicy.thumbnail(112, this.getUIContext().vp2px(1)) })
        .width(112)
        .height(112)
      if (this.capture.renderedPath.length === 0 && this.capture.originalPath.length === 0) {
        Column() {
          Text('▣').fontSize(30).fontColor(UiTokens.TEXT_SECONDARY)
            .accessibilityLevel('no')
        }
        .justifyContent(FlexAlign.Center).width(112).height(112)
        .backgroundColor(UiTokens.IMAGE_PLACEHOLDER).borderRadius(18)
      }
      if (this.selectionMode) {
        Text(this.selected ? '✓' : '')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .textAlign(TextAlign.Center)
          .accessibilityLevel('no')
          .width(32).height(32)
          .backgroundColor(this.selected ? UiTokens.PRIMARY : UiTokens.OVERLAY)
          .border({ width: 2, color: Color.White })
          .borderRadius(16)
          .margin(7)
      }
      if (this.capture.status === 'failed') {
        Text(tr('失败', 'Failed'))
          .fontSize(11).fontColor(Color.White).padding({ left: 9, right: 9, top: 4, bottom: 4 })
          .backgroundColor('#CCB3261E').borderRadius({ bottomLeft: 12, topRight: 12 })
          .align(Alignment.BottomEnd)
      }
    }
    .width(112)
    .height(112)
    .clip(true)
    .borderRadius(18)
    .sharedTransition(`capture-photo-${this.capture.id}`,
      { duration: MotionPolicy.duration(ViewerNodePolicy.SHARED_TRANSITION_DURATION), curve: Curve.Friction })
    .accessibilityText(tr(`照片 ${this.capture.photoNumber}`, `Photo ${this.capture.photoNumber}`))
  }

  build() {
    Row({ space: 14 }) {
      this.thumbnail()
      Column({ space: 5 }) {
        Row({ space: 6 }) {
          Text(this.capture.photoNumber.length > 0 ? this.capture.photoNumber.split('-').slice(-2).join(' · ') :
            formatDay(this.capture.capturedAt))
            .fontSize(17).fontWeight(FontWeight.Bold).fontColor(UiTokens.TEXT)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          Text(statusLabel(this.capture.status))
            .fontSize(12)
            .fontColor(this.capture.status === 'failed' ? UiTokens.DANGER :
              (this.capture.status === 'ready' ? UiTokens.SUCCESS : UiTokens.WARNING))
        }.width('100%')
        if (this.showProject) {
          Text(this.capture.projectName).fontSize(13).fontWeight(FontWeight.Medium)
            .fontColor(UiTokens.PRIMARY).maxLines(1).width('100%')
        }
        Text(`${this.capture.workLocation} · ${this.capture.workContent}`)
          .fontSize(14).fontColor(UiTokens.TEXT).maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        Text(this.capture.photographer)
          .fontSize(13).fontColor(UiTokens.TEXT_SECONDARY).maxLines(1).width('100%')
        Text(this.capture.hasOriginal() ? tr('原图已保留', 'Original retained') :
          tr('原图已清理', 'Original cleared'))
          .fontSize(12).fontColor(UiTokens.TEXT_SECONDARY).width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .padding(14)
    .width('100%')
    .backgroundColor(this.pressed ? UiTokens.SURFACE_MUTED : UiTokens.GLASS)
    .animation({ duration: MotionPolicy.duration(90), curve: Curve.EaseOut })
    .borderRadius(UiTokens.CARD_RADIUS)
    .border({ width: 1, color: this.selected ? UiTokens.PRIMARY : UiTokens.OUTLINE_SUBTLE })
    .shadow({ radius: 12, color: UiTokens.CARD_SHADOW, offsetY: 4 })
    .accessibilityText(this.cardAccessibilityText())
    .onTouch((event: TouchEvent): void => {
      this.pressed = event.type === TouchType.Down || event.type === TouchType.Move;
    })
    .onClick((): void => this.selectionMode ? this.onToggle() : this.onOpen())
  }
}
