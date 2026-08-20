import { UiTokens } from './UiTokens';
import { tr } from './AppText';

export class FormLayoutMetrics {
  static readonly SINGLE_LINE_HEIGHT: number = 50;
  static readonly TEXT_AREA_HEIGHT: number = 112;
  static readonly SUPPORTING_TEXT_MIN_HEIGHT: number = 34;
  static readonly TOUCH_TARGET: number = 44;
}

@Component
export struct FormField {
  @Prop label: string = '';
  @Prop value: string = '';
  @Prop placeholder: string = '';
  @Prop required: boolean = false;
  @Prop error: string = '';
  @Prop helper: string = '';
  @Prop maxLength: number = 256;
  onChange: (value: string) => void = (_value: string): void => {};

  build() {
    Column({ space: 7 }) {
      Row({ space: 3 }) {
        Text(this.label)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(UiTokens.TEXT_SECONDARY)
          .maxLines(2)
          .layoutWeight(1)
        if (this.required) {
          Text('*')
            .fontSize(13)
            .fontColor(UiTokens.DANGER)
        }
      }
      .width('100%')
      TextInput({ text: this.value, placeholder: this.placeholder })
        .width('100%')
        .height(FormLayoutMetrics.SINGLE_LINE_HEIGHT)
        .fontSize(15)
        .fontColor(UiTokens.TEXT)
        .backgroundColor(UiTokens.SURFACE_MUTED)
        .border({ width: 1, color: this.error.length > 0 ? UiTokens.DANGER : UiTokens.OUTLINE_SUBTLE })
        .borderRadius(UiTokens.CONTROL_RADIUS)
        .padding({ left: 13, right: 13 })
        .maxLength(this.maxLength)
        .accessibilityText(this.required ? `${this.label}${tr('，必填', ', required')}` : this.label)
        .onChange(this.onChange)
      Text(this.error.length > 0 ? this.error : (this.helper.length > 0 ? this.helper : ' '))
        .width('100%')
        .constraintSize({ minHeight: FormLayoutMetrics.SUPPORTING_TEXT_MIN_HEIGHT })
        .fontSize(12)
        .fontColor(this.error.length > 0 ? UiTokens.DANGER : UiTokens.TEXT_SECONDARY)
        .lineHeight(16)
        .maxLines(2)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

@Component
export struct FormTextArea {
  @Prop label: string = '';
  @Prop value: string = '';
  @Prop placeholder: string = '';
  @Prop required: boolean = false;
  @Prop error: string = '';
  @Prop helper: string = '';
  @Prop maxLength: number = 1000;
  onChange: (value: string) => void = (_value: string): void => {};

  build() {
    Column({ space: 7 }) {
      Row({ space: 3 }) {
        Text(this.label)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(UiTokens.TEXT_SECONDARY)
          .maxLines(2)
          .layoutWeight(1)
        if (this.required) {
          Text('*')
            .fontSize(13)
            .fontColor(UiTokens.DANGER)
        }
      }
      .width('100%')
      TextArea({ text: this.value, placeholder: this.placeholder })
        .width('100%')
        .height(FormLayoutMetrics.TEXT_AREA_HEIGHT)
        .fontSize(15)
        .fontColor(UiTokens.TEXT)
        .backgroundColor(UiTokens.SURFACE_MUTED)
        .border({ width: 1, color: this.error.length > 0 ? UiTokens.DANGER : UiTokens.OUTLINE_SUBTLE })
        .borderRadius(UiTokens.CONTROL_RADIUS)
        .padding(13)
        .maxLength(this.maxLength)
        .accessibilityText(this.required ? `${this.label}${tr('，必填', ', required')}` : this.label)
        .onChange(this.onChange)
      Text(this.error.length > 0 ? this.error : (this.helper.length > 0 ? this.helper : ' '))
        .width('100%')
        .constraintSize({ minHeight: FormLayoutMetrics.SUPPORTING_TEXT_MIN_HEIGHT })
        .fontSize(12)
        .fontColor(this.error.length > 0 ? UiTokens.DANGER : UiTokens.TEXT_SECONDARY)
        .lineHeight(16)
        .maxLines(2)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
