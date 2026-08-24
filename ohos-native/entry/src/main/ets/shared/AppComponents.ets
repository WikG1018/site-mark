import { UiTokens } from './UiTokens';
import { choiceAccessibilityText, joinAccessibilityText } from './AccessibilityText';
import { MotionPolicy } from './MotionPolicy';
import { AccentSwatch, AccentSwatches } from './AccentSwatches';
import { themeSeedAccessibilityText, watermarkAccentAccessibilityText, WatermarkAccentOption }
  from './AccentAccessibility';
import { tr } from './AppText';
import { SAFE_AREA_TOP_VP, topPaddingVp } from './SystemBars';

/**
 * 条件面板统一转场：出现时淡入并上移 distanceVp，消失时淡出并下移。
 * 时长走 MotionPolicy，系统减少动画开启时归零。distanceVp 传 0 表示纯淡入淡出。
 */
export function panelTransition(distanceVp: number = 24): TransitionEffect {
  return TransitionEffect.asymmetric(
    TransitionEffect.opacity(0).combine(TransitionEffect.translate({ y: distanceVp }))
      .animation({ duration: MotionPolicy.duration(UiTokens.MOTION_STANDARD), curve: Curve.EaseOut }),
    TransitionEffect.opacity(0).combine(TransitionEffect.translate({ y: distanceVp }))
      .animation({ duration: MotionPolicy.duration(UiTokens.MOTION_FAST), curve: Curve.EaseIn }));
}

export class SegmentOption {
  value: string;
  label: string;

  constructor(value: string, label: string) {
    this.value = value;
    this.label = label;
  }
}

export class BatchActionItem {
  id: string;
  icon: string;
  label: string;
  danger: boolean;
  disabled: boolean;
  accessibilityLabel: string;

  constructor(id: string, icon: string, label: string, danger: boolean = false, disabled: boolean = false,
    accessibilityLabel: string = '') {
    this.id = id;
    this.icon = icon;
    this.label = label;
    this.danger = danger;
    this.disabled = disabled;
    this.accessibilityLabel = accessibilityLabel;
  }
}

@Component
export struct AppTopBar {
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop showBack: boolean = false;
  @Prop actionLabel: string = '';
  @Prop backAccessibilityText: string = '返回';
  @Prop actionAccessibilityText: string = '';
  @Prop actionEnabled: boolean = true;
  @StorageLink(SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  onBack: () => void = (): void => {};
  onAction: () => void = (): void => {};

  build() {
    Row({ space: 12 }) {
      if (this.showBack) {
        Button() {
          // Explicit full-width centering: the ‹ glyph's ink sits slightly
          // off-center in most fonts, and a raw string label at fontSize 32
          // could clip inside the 44vp target.
          Text('‹')
            .fontSize(26)
            .fontColor(UiTokens.TEXT)
            .width('100%')
            .textAlign(TextAlign.Center)
            .accessibilityLevel('no')
        }
        .width(UiTokens.TOUCH_TARGET)
        .height(UiTokens.TOUCH_TARGET)
        .backgroundColor(Color.Transparent)
        .accessibilityText(this.backAccessibilityText)
        .onClick(this.onBack)
      }
      Column({ space: 2 }) {
        Text(this.title)
          .fontSize(this.title.length > 20 ? 22 : 24)
          .fontWeight(FontWeight.Bold)
          .fontColor(UiTokens.TEXT)
          .maxLines(this.subtitle.length > 0 ? 1 : 2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (this.subtitle.length > 0) {
          Text(this.subtitle)
            .fontSize(13)
            .fontColor(UiTokens.TEXT_SECONDARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (this.actionLabel.length > 0) {
        Button(this.actionLabel)
          .height(UiTokens.TOUCH_TARGET)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(UiTokens.PRIMARY)
          .backgroundColor(Color.Transparent)
          .borderRadius(UiTokens.CONTROL_RADIUS)
          .accessibilityText(this.actionAccessibilityText.length > 0 ?
            this.actionAccessibilityText : this.actionLabel)
          .enabled(this.actionEnabled)
          .onClick(this.onAction)
      }
    }
    .width('100%')
    .height(UiTokens.TOP_BAR_HEIGHT + this.safeAreaTopVp)
    .padding({ left: this.showBack ? 4 : UiTokens.PAGE_PADDING,
      right: UiTokens.PAGE_PADDING, top: topPaddingVp(this.safeAreaTopVp, 6), bottom: 6 })
    .alignItems(VerticalAlign.Center)
  }
}

@Component
export struct EmptyPanel {
  @Prop icon: string = '◇';
  @Prop title: string = '';
  @Prop message: string = '';
  @Prop actionLabel: string = '';
  onAction: () => void = (): void => {};

  build() {
    Column({ space: 12 }) {
      Text(this.icon)
        .fontSize(42)
        .fontColor(UiTokens.PRIMARY)
        .accessibilityLevel('no')
      Text(this.title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(UiTokens.TEXT)
        .textAlign(TextAlign.Center)
      Text(this.message)
        .fontSize(14)
        .fontColor(UiTokens.TEXT_SECONDARY)
        .textAlign(TextAlign.Center)
        .lineHeight(21)
      if (this.actionLabel.length > 0) {
        Button(this.actionLabel)
          .margin({ top: 6 })
          .height(44)
          .fontColor(Color.White)
          .backgroundColor(UiTokens.PRIMARY)
          .borderRadius(22)
          .onClick(this.onAction)
      }
    }
    .padding(28)
    .margin({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING, top: 34 })
    .width(`calc(100% - ${UiTokens.PAGE_PADDING * 2}vp)`)
    .backgroundColor(UiTokens.GLASS)
    .borderRadius(UiTokens.CARD_RADIUS)
    .border({ width: 1, color: UiTokens.OUTLINE_SUBTLE })
    .transition(panelTransition(0))
  }
}

@Component
export struct SectionHeader {
  @Prop title: string = '';
  @Prop detail: string = '';

  build() {
    Row() {
      Text(this.title)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(UiTokens.TEXT)
        .layoutWeight(1)
      if (this.detail.length > 0) {
        Text(this.detail)
          .fontSize(13)
          .fontColor(UiTokens.TEXT_SECONDARY)
      }
    }
    .width('100%')
    .padding({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING, top: 16, bottom: 8 })
  }
}

@Component
export struct ValueTextRow {
  @Prop label: string = '';
  @Prop value: string = '';

  build() {
    Row() {
      Text(this.label).fontSize(15).fontColor(UiTokens.TEXT).layoutWeight(1)
      Text(this.value).fontSize(14).fontColor(UiTokens.TEXT_SECONDARY)
    }.width('100%').padding({ top: 12, bottom: 12 })
  }
}

@Component
export struct SettingRow {
  @Prop icon: string = '';
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop trailing: string = '›';
  @Prop showDivider: boolean = false;
  @State private pressed: boolean = false;
  action: () => void = (): void => {};

  build() {
    Column() {
      Row({ space: 14 }) {
        Text(this.icon)
          .fontSize(22)
          .fontColor(UiTokens.PRIMARY)
          .width(36)
          .textAlign(TextAlign.Center)
        Column({ space: 3 }) {
          Text(this.title)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(UiTokens.TEXT)
            .width('100%')
          if (this.subtitle.length > 0) {
            Text(this.subtitle)
              .fontSize(13)
              .fontColor(UiTokens.TEXT_SECONDARY)
              .maxLines(2)
              .width('100%')
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Text(this.trailing)
          .fontSize(22)
          .fontColor(UiTokens.TEXT_SECONDARY)
      }
      .width('100%')
      .constraintSize({ minHeight: 64 })
      .padding({ left: 16, right: 16, top: 9, bottom: 9 })
      .backgroundColor(this.pressed ? UiTokens.SURFACE_MUTED : Color.Transparent)
      .animation({ duration: MotionPolicy.duration(90), curve: Curve.EaseOut })
      .onTouch((event: TouchEvent): void => {
        this.pressed = event.type === TouchType.Down || event.type === TouchType.Move;
      })
      .accessibilityText(this.subtitle.length > 0 ? joinAccessibilityText([this.title, this.subtitle]) : this.title)
      .onClick(this.action)
      if (this.showDivider) {
        Divider()
          .strokeWidth(1)
          .color(UiTokens.OUTLINE_SUBTLE)
          .margin({ left: 66 })
      }
    }
    .width('100%')
  }
}

@Component
export struct AppSearchField {
  @Prop value: string = '';
  @Prop placeholder: string = '';
  @Prop accessibilityLabel: string = '';
  onChange: (value: string) => void = (_value: string): void => {};

  build() {
    Row({ space: 8 }) {
      Text('⌕')
        .width(24)
        .fontSize(21)
        .fontColor(UiTokens.TEXT_SECONDARY)
        .textAlign(TextAlign.Center)
        .accessibilityLevel('no')
      TextInput({ text: this.value, placeholder: this.placeholder })
        .layoutWeight(1)
        .height(UiTokens.TOUCH_TARGET)
        .fontSize(15)
        .fontColor(UiTokens.TEXT)
        .backgroundColor(Color.Transparent)
        .accessibilityText(this.accessibilityLabel.length > 0 ? this.accessibilityLabel : this.placeholder)
        .onChange(this.onChange)
    }
    .width('100%')
    .height(UiTokens.TOUCH_TARGET + 4)
    .padding({ left: 12, right: 8 })
    .backgroundColor(UiTokens.SURFACE_MUTED)
    .border({ width: 1, color: UiTokens.OUTLINE_SUBTLE })
    .borderRadius(UiTokens.CONTROL_RADIUS)
  }
}

@Component
export struct LifecycleSegment {
  @Prop options: SegmentOption[] = [];
  @Prop selectedValue: string = '';
  // pill 复现原 statusChip 全圆胶囊；默认 segment 为圆角容器分段形态（原 ChoiceButton 行）
  @Prop pill: boolean = false;
  @Prop controlEnabled: boolean = true;
  onSelect: (value: string) => void = (_value: string): void => {};

  private chipSpace(): number {
    return this.pill ? 6 : 7;
  }

  private chipPadding(): number {
    return this.pill ? 4 : 3;
  }

  private chipRadius(): number {
    return this.pill ? UiTokens.TOUCH_TARGET / 2 : UiTokens.CONTROL_RADIUS;
  }

  private chipFontSize(): number {
    return this.pill ? 14 : 13;
  }

  build() {
    Row({ space: this.chipSpace() }) {
      ForEach(this.options, (option: SegmentOption) => {
        Button(option.label)
          .layoutWeight(1)
          .height(UiTokens.TOUCH_TARGET)
          .fontSize(this.chipFontSize())
          // Fixed weight: switching Bold/Regular between states changes the
          // text advance width and makes labels jitter inside equal-width chips.
          .fontWeight(FontWeight.Medium)
          .fontColor(this.selectedValue === option.value ? UiTokens.PRIMARY : UiTokens.TEXT_SECONDARY)
          .backgroundColor(this.selectedValue === option.value ? UiTokens.PRIMARY_CONTAINER : Color.Transparent)
          .borderRadius(this.chipRadius())
          .enabled(this.controlEnabled)
          .accessibilityText(choiceAccessibilityText(option.label, this.selectedValue === option.value))
          .onClick((): void => this.onSelect(option.value))
      }, (option: SegmentOption): string => option.value)
    }
    .width('100%')
    .padding(this.chipPadding())
    .backgroundColor(this.pill ? UiTokens.CONTROL : UiTokens.SURFACE_MUTED)
    .borderRadius(this.chipRadius() + (this.pill ? 2 : 3))
  }
}

@Component
export struct FilterToolbar {
  @Prop label: string = '';
  @Prop summary: string = '';
  @Prop active: boolean = false;
  onOpen: () => void = (): void => {};

  build() {
    Row({ space: 10 }) {
      Button() {
        Row({ space: 6 }) {
          Text('≡').fontSize(16).fontColor(this.active ? UiTokens.PRIMARY : UiTokens.TEXT)
            .accessibilityLevel('no')
          Text(this.label).fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor(this.active ? UiTokens.PRIMARY : UiTokens.TEXT)
        }
        .alignItems(VerticalAlign.Center)
      }
      .height(UiTokens.TOUCH_TARGET)
      .padding({ left: 12, right: 12 })
      .backgroundColor(this.active ? UiTokens.PRIMARY_CONTAINER : UiTokens.SURFACE_MUTED)
      .border({ width: 1, color: this.active ? UiTokens.PRIMARY : UiTokens.OUTLINE_SUBTLE })
      .borderRadius(UiTokens.CONTROL_RADIUS)
      .accessibilityText(this.label)
      .onClick(this.onOpen)
      if (this.summary.length > 0) {
        Text(this.summary)
          .fontSize(13)
          .fontColor(UiTokens.TEXT_SECONDARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.End)
          .layoutWeight(1)
      } else {
        Blank().layoutWeight(1)
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }
}

@Component
export struct BatchActionBar {
  @Prop selectedLabel: string = '';
  @Prop actions: BatchActionItem[] = [];
  @Prop actionHeight: number = 68;
  @Prop actionLabelMaxLines: number = 2;
  onAction: (id: string) => void = (_id: string): void => {};

  build() {
    Column({ space: 3 }) {
      if (this.selectedLabel.length > 0) {
        Text(this.selectedLabel)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(UiTokens.TEXT_SECONDARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      Row() {
        ForEach(this.actions, (item: BatchActionItem) => {
          Button() {
            Column({ space: 1 }) {
              Text(item.icon)
                .fontSize(19)
                .fontColor(item.danger ? UiTokens.DANGER : UiTokens.TEXT)
              Text(item.label)
                .fontSize(11)
                .fontColor(item.danger ? UiTokens.DANGER : UiTokens.TEXT)
                .textAlign(TextAlign.Center)
                .maxLines(this.actionLabelMaxLines)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
          }
          .layoutWeight(1)
          .height(this.actionHeight)
          .enabled(!item.disabled)
          .backgroundColor(Color.Transparent)
          .borderRadius(UiTokens.CONTROL_RADIUS)
          .accessibilityText(item.accessibilityLabel.length > 0 ? item.accessibilityLabel : item.label)
          .onClick((): void => this.onAction(item.id))
        }, (item: BatchActionItem): string => item.id)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 4, bottom: 4 })
    .backgroundColor(UiTokens.GLASS_STRONG)
    .border({ width: 1, color: UiTokens.OUTLINE_SUBTLE })
    .borderRadius(UiTokens.CARD_RADIUS)
  }
}

@Component
export struct InlineErrorPanel {
  @Prop message: string = '';
  @Prop retryLabel: string = '';
  onRetry: () => void = (): void => {};

  build() {
    Row({ space: 10 }) {
      Text('!')
        .width(24)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(UiTokens.DANGER)
        .textAlign(TextAlign.Center)
        .accessibilityLevel('no')
      Text(this.message)
        .fontSize(13)
        .fontColor(UiTokens.TEXT_SECONDARY)
        .maxLines(3)
        .layoutWeight(1)
      if (this.retryLabel.length > 0) {
        Button(this.retryLabel)
          .height(UiTokens.TOUCH_TARGET)
          .fontSize(13)
          .fontColor(UiTokens.PRIMARY)
          .backgroundColor(Color.Transparent)
          .accessibilityText(this.retryLabel)
          .onClick(this.onRetry)
      }
    }
    .width('100%')
    .padding({ left: 12, right: 8, top: 8, bottom: 8 })
    .backgroundColor(UiTokens.SURFACE_MUTED)
    .border({ width: 1, color: UiTokens.OUTLINE_SUBTLE })
    .borderRadius(UiTokens.CONTROL_RADIUS)
    .transition(panelTransition(0))
  }
}

@Component
export struct ListSkeleton {
  @Prop rows: number = 3;
  @State private shimmerActive: boolean = false;
  private shimmerTimer: number = -1;

  aboutToAppear(): void {
    // Reduce-motion keeps the skeleton static — the pulse is decorative only.
    if (MotionPolicy.reduceMotion) {
      return;
    }
    // .animation() only plays on attribute *changes*, so the pulse needs a
    // state flip; the initial build alone never animates.
    this.shimmerTimer = setInterval((): void => {
      this.shimmerActive = !this.shimmerActive;
    }, 700);
  }

  aboutToDisappear(): void {
    if (this.shimmerTimer >= 0) {
      clearInterval(this.shimmerTimer);
      this.shimmerTimer = -1;
    }
  }

  build() {
    Column({ space: 12 }) {
      ForEach([0, 1, 2, 3, 4].slice(0, this.rows),
        (_index: number) => {
          Row({ space: 14 }) {
            Row().width(92).height(92).backgroundColor(UiTokens.CONTROL).borderRadius(18)
            Column({ space: 10 }) {
              Row().width('72%').height(16).backgroundColor(UiTokens.CONTROL).borderRadius(8)
              Row().width('94%').height(13).backgroundColor(UiTokens.CONTROL).borderRadius(7)
              Row().width('62%').height(13).backgroundColor(UiTokens.CONTROL).borderRadius(7)
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          }
          .width('100%').padding(14).backgroundColor(UiTokens.GLASS).borderRadius(UiTokens.CARD_RADIUS)
          .border({ width: 1, color: UiTokens.OUTLINE_SUBTLE })
        }, (_index: number): string => _index.toString())
    }
    .padding({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING, top: 6 })
    .width('100%')
    .opacity(this.shimmerActive ? 1 : 0.55)
    .animation({ duration: MotionPolicy.duration(600), curve: Curve.EaseInOut })
    .transition(panelTransition(0))
  }
}

@Component
export struct AccentSwatchRow {
  @Prop selectedArgb: number = 0xFF37C58B;
  @Prop controlEnabled: boolean = true;
  @Prop accessibilityKind: string = 'watermark';
  onSelect: (argb: number) => void = (_argb: number): void => {};

  build() {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(AccentSwatches.values(), (swatch: AccentSwatch) => {
        Button()
          .width(UiTokens.TOUCH_TARGET)
          .height(UiTokens.TOUCH_TARGET)
          .borderRadius(UiTokens.TOUCH_TARGET / 2)
          .backgroundColor(swatch.argb)
          .border({
            width: AccentSwatches.nearest(this.selectedArgb) === swatch.argb ? 4 : 1,
            color: Color.White
          })
          .margin({ right: 11, bottom: 11 })
          .enabled(this.controlEnabled)
          .accessibilityText(this.swatchText(swatch))
          .onClick((): void => { this.onSelect(swatch.argb); })
      }, (swatch: AccentSwatch): string => swatch.argb.toString())
    }.width('100%')
  }

  private swatchText(swatch: AccentSwatch): string {
    const option = new WatermarkAccentOption(
      swatch.argb,
      AccentSwatches.label(swatch.argb, false),
      AccentSwatches.label(swatch.argb, true));
    const selected: boolean = AccentSwatches.nearest(this.selectedArgb) === swatch.argb;
    if (this.accessibilityKind === 'theme') {
      return themeSeedAccessibilityText(option, selected);
    }
    return watermarkAccentAccessibilityText(option, selected);
  }
}

@Component
export struct DateFilterRow {
  @Prop year: string = '';
  @Prop month: string = '';
  @Prop day: string = '';
  @Prop controlEnabled: boolean = true;
  onChange: (year: string, month: string, day: string) => void =
    (_year: string, _month: string, _day: string): void => {};

  build() {
    Row({ space: 8 }) {
      TextInput({ text: this.year, placeholder: tr('年', 'Year') }).layoutWeight(1)
        .height(UiTokens.TOUCH_TARGET)
        .enabled(this.controlEnabled)
        .type(InputType.Number)
        .backgroundColor(UiTokens.SURFACE_MUTED)
        .border({ width: 1, color: UiTokens.OUTLINE_SUBTLE })
        .borderRadius(UiTokens.CONTROL_RADIUS)
        .onChange((value: string): void => { this.onChange(value, this.month, this.day); })
      TextInput({ text: this.month, placeholder: tr('月', 'Month') }).layoutWeight(1)
        .height(UiTokens.TOUCH_TARGET)
        .enabled(this.controlEnabled)
        .type(InputType.Number)
        .backgroundColor(UiTokens.SURFACE_MUTED)
        .border({ width: 1, color: UiTokens.OUTLINE_SUBTLE })
        .borderRadius(UiTokens.CONTROL_RADIUS)
        .onChange((value: string): void => { this.onChange(this.year, value, this.day); })
      TextInput({ text: this.day, placeholder: tr('日', 'Day') }).layoutWeight(1)
        .height(UiTokens.TOUCH_TARGET)
        .enabled(this.controlEnabled)
        .type(InputType.Number)
        .backgroundColor(UiTokens.SURFACE_MUTED)
        .border({ width: 1, color: UiTokens.OUTLINE_SUBTLE })
        .borderRadius(UiTokens.CONTROL_RADIUS)
        .onChange((value: string): void => { this.onChange(this.year, this.month, value); })
    }.width('100%')
  }
}
