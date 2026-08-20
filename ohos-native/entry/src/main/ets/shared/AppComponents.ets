import { UiTokens } from './UiTokens';

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

  constructor(id: string, icon: string, label: string, danger: boolean = false, disabled: boolean = false) {
    this.id = id;
    this.icon = icon;
    this.label = label;
    this.danger = danger;
    this.disabled = disabled;
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
  onBack: () => void = (): void => {};
  onAction: () => void = (): void => {};

  build() {
    Row({ space: 12 }) {
      if (this.showBack) {
        Button('‹')
          .width(UiTokens.TOUCH_TARGET)
          .height(UiTokens.TOUCH_TARGET)
          .fontSize(32)
          .fontColor(UiTokens.TEXT)
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
          .onClick(this.onAction)
      }
    }
    .width('100%')
    .height(UiTokens.TOP_BAR_HEIGHT)
    .padding({ left: this.showBack ? 4 : UiTokens.PAGE_PADDING,
      right: UiTokens.PAGE_PADDING, top: 6, bottom: 6 })
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
    .backdropBlur(18)
    .borderRadius(UiTokens.CARD_RADIUS)
    .border({ width: 1, color: UiTokens.OUTLINE_SUBTLE })
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
export struct ChoiceButton {
  @Prop label: string = '';
  @Prop selected: boolean = false;
  onSelect: () => void = (): void => {};

  build() {
    Button(this.label).layoutWeight(1).height(UiTokens.TOUCH_TARGET).fontSize(13)
      .backgroundColor(this.selected ? UiTokens.PRIMARY_CONTAINER : UiTokens.CONTROL)
      .fontColor(this.selected ? UiTokens.PRIMARY : UiTokens.TEXT)
      .borderRadius(UiTokens.CONTROL_RADIUS)
      .accessibilityText(this.label)
      .onClick(this.onSelect)
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
      .accessibilityText(this.subtitle.length > 0 ? `${this.title}，${this.subtitle}` : this.title)
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
  onSelect: (value: string) => void = (_value: string): void => {};

  build() {
    Row({ space: 4 }) {
      ForEach(this.options, (option: SegmentOption) => {
        Button(option.label)
          .layoutWeight(1)
          .height(UiTokens.TOUCH_TARGET)
          .fontSize(14)
          .fontWeight(this.selectedValue === option.value ? FontWeight.Bold : FontWeight.Regular)
          .fontColor(this.selectedValue === option.value ? UiTokens.PRIMARY : UiTokens.TEXT_SECONDARY)
          .backgroundColor(this.selectedValue === option.value ? UiTokens.PRIMARY_CONTAINER : Color.Transparent)
          .borderRadius(UiTokens.CONTROL_RADIUS)
          .accessibilityText(option.label)
          .onClick((): void => this.onSelect(option.value))
      }, (option: SegmentOption): string => option.value)
    }
    .width('100%')
    .padding(3)
    .backgroundColor(UiTokens.SURFACE_MUTED)
    .borderRadius(UiTokens.CONTROL_RADIUS + 3)
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
      Button(`≡  ${this.label}`)
        .height(UiTokens.TOUCH_TARGET)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.active ? UiTokens.PRIMARY : UiTokens.TEXT)
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
  onAction: (id: string) => void = (_id: string): void => {};

  build() {
    Column({ space: 7 }) {
      if (this.selectedLabel.length > 0) {
        Text(this.selectedLabel)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(UiTokens.TEXT_SECONDARY)
      }
      Row() {
        ForEach(this.actions, (item: BatchActionItem) => {
          Button() {
            Column({ space: 3 }) {
              Text(item.icon)
                .fontSize(22)
                .fontColor(item.danger ? UiTokens.DANGER : UiTokens.TEXT)
              Text(item.label)
                .fontSize(12)
                .fontColor(item.danger ? UiTokens.DANGER : UiTokens.TEXT)
                .maxLines(1)
            }
          }
          .layoutWeight(1)
          .height(52)
          .enabled(!item.disabled)
          .backgroundColor(Color.Transparent)
          .borderRadius(UiTokens.CONTROL_RADIUS)
          .accessibilityText(item.label)
          .onClick((): void => this.onAction(item.id))
        }, (item: BatchActionItem): string => item.id)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 10, bottom: 9 })
    .backgroundColor(UiTokens.GLASS_STRONG)
    .backdropBlur(18)
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
  }
}

@Component
export struct ListSkeleton {
  @Prop rows: number = 3;

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
    .width('100%').opacity(0.72)
  }
}
