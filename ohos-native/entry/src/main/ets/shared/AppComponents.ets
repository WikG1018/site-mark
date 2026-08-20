import { UiTokens } from './UiTokens';

@Component
export struct AppTopBar {
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop showBack: boolean = false;
  @Prop actionLabel: string = '';
  onBack: () => void = (): void => {};
  onAction: () => void = (): void => {};

  build() {
    Row({ space: 12 }) {
      if (this.showBack) {
        Button('‹')
          .width(44)
          .height(44)
          .fontSize(32)
          .fontColor(UiTokens.TEXT)
          .backgroundColor(Color.Transparent)
          .onClick(this.onBack)
      }
      Column({ space: 2 }) {
        Text(this.title)
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(UiTokens.TEXT)
          .maxLines(1)
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
          .height(40)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(UiTokens.PRIMARY)
          .backgroundColor(UiTokens.PRIMARY_CONTAINER)
          .borderRadius(20)
          .onClick(this.onAction)
      }
    }
    .width('100%')
    .height(76)
    .padding({ left: this.showBack ? 4 : UiTokens.PAGE_PADDING,
      right: UiTokens.PAGE_PADDING, top: 10, bottom: 8 })
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
    .border({ width: 1, color: '#DDEAE2' })
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
    Button(this.label).layoutWeight(1).height(40).fontSize(13)
      .backgroundColor(this.selected ? UiTokens.PRIMARY_CONTAINER : UiTokens.CONTROL)
      .fontColor(this.selected ? UiTokens.PRIMARY : UiTokens.TEXT)
      .borderRadius(16)
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
  action: () => void = (): void => {};

  build() {
    Row({ space: 14 }) {
      Text(this.icon)
        .fontSize(24)
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
            .fontSize(12)
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
    .height(72)
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .onClick(this.action)
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
          .border({ width: 1, color: UiTokens.OUTLINE })
        }, (_index: number): string => _index.toString())
    }
    .padding({ left: UiTokens.PAGE_PADDING, right: UiTokens.PAGE_PADDING, top: 6 })
    .width('100%').opacity(0.72)
  }
}
