import { UiTokens } from './UiTokens';
import { tr } from './AppText';

export class FormLayoutMetrics {
  static readonly SINGLE_LINE_HEIGHT: number = 50;
  static readonly TEXT_AREA_HEIGHT: number = 112;
  // One line of 12sp/18lh supporting text. The old 50vp reserved ~3 blank
  // lines under every field (≈150vp of dead space on the capture form);
  // multi-line errors still grow naturally from here.
  static readonly SUPPORTING_TEXT_MIN_HEIGHT: number = 18;
  static readonly TOUCH_TARGET: number = 44;
}

export class FormLengthPolicy {
  static shouldApply(maxLength: number): boolean {
    return Number.isFinite(maxLength) && maxLength > 0;
  }
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
  @Prop fieldEnabled: boolean = true;
  @Prop obscure: boolean = false;
  onChange: (value: string) => void = (_value: string): void => {};
  onFieldFocus: () => void = (): void => {};

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
        .type(this.obscure ? InputType.Password : InputType.Normal)
        .width('100%')
        .height(FormLayoutMetrics.SINGLE_LINE_HEIGHT)
        .fontSize(15)
        .fontColor(UiTokens.TEXT)
        .backgroundColor(UiTokens.SURFACE_MUTED)
        .border({ width: 1, color: this.error.length > 0 ? UiTokens.DANGER : UiTokens.OUTLINE_SUBTLE })
        .borderRadius(UiTokens.CONTROL_RADIUS)
        .padding({ left: 13, right: 13 })
        .enabled(this.fieldEnabled)
        .maxLength(this.maxLength)
        .accessibilityText(this.required ? `${this.label}${tr('，必填', ', required')}` : this.label)
        .onFocus((): void => { this.onFieldFocus(); })
        .onChange(this.onChange)
      Text(this.error.length > 0 ? this.error : (this.helper.length > 0 ? this.helper : ' '))
        .width('100%')
        .constraintSize({ minHeight: FormLayoutMetrics.SUPPORTING_TEXT_MIN_HEIGHT })
        .fontSize(12)
        .fontColor(this.error.length > 0 ? UiTokens.DANGER : UiTokens.TEXT_SECONDARY)
        .lineHeight(18)
        .maxLines(5)
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
  @Prop maxLength: number = 0;
  @Prop fieldEnabled: boolean = true;
  onChange: (value: string) => void = (_value: string): void => {};
  onFieldFocus: () => void = (): void => {};

  @Builder
  private unlimitedInput() {
    TextArea({ text: this.value, placeholder: this.placeholder })
      .width('100%')
      .height(FormLayoutMetrics.TEXT_AREA_HEIGHT)
      .fontSize(15)
      .fontColor(UiTokens.TEXT)
      .backgroundColor(UiTokens.SURFACE_MUTED)
      .border({ width: 1, color: this.error.length > 0 ? UiTokens.DANGER : UiTokens.OUTLINE_SUBTLE })
      .borderRadius(UiTokens.CONTROL_RADIUS)
      .padding(13)
      .enabled(this.fieldEnabled)
      .accessibilityText(this.required ? `${this.label}${tr('，必填', ', required')}` : this.label)
      .onFocus((): void => { this.onFieldFocus(); })
      .onChange(this.onChange)
  }

  @Builder
  private limitedInput() {
    TextArea({ text: this.value, placeholder: this.placeholder })
      .width('100%')
      .height(FormLayoutMetrics.TEXT_AREA_HEIGHT)
      .fontSize(15)
      .fontColor(UiTokens.TEXT)
      .backgroundColor(UiTokens.SURFACE_MUTED)
      .border({ width: 1, color: this.error.length > 0 ? UiTokens.DANGER : UiTokens.OUTLINE_SUBTLE })
      .borderRadius(UiTokens.CONTROL_RADIUS)
      .padding(13)
      .enabled(this.fieldEnabled)
      .maxLength(this.maxLength)
      .accessibilityText(this.required ? `${this.label}${tr('，必填', ', required')}` : this.label)
      .onFocus((): void => { this.onFieldFocus(); })
      .onChange(this.onChange)
  }

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
      if (FormLengthPolicy.shouldApply(this.maxLength)) {
        this.limitedInput()
      } else {
        this.unlimitedInput()
      }
      Text(this.error.length > 0 ? this.error : (this.helper.length > 0 ? this.helper : ' '))
        .width('100%')
        .constraintSize({ minHeight: FormLayoutMetrics.SUPPORTING_TEXT_MIN_HEIGHT })
        .fontSize(12)
        .fontColor(this.error.length > 0 ? UiTokens.DANGER : UiTokens.TEXT_SECONDARY)
        .lineHeight(18)
        .maxLines(5)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
