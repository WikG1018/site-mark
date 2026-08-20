import { tr } from './AppText';
import { MotionPolicy } from './MotionPolicy';
import { UiTokens } from './UiTokens';

export class ImageDecodePolicy {
  static thumbnail(edgeVp: number, density: number): number {
    return Math.min(1024, Math.max(256, Math.ceil(edgeVp * density)));
  }

  static detail(): number {
    return 2048;
  }

  static viewer(current: boolean): number {
    return current ? 2048 : 1024;
  }
}

@Component
export struct AppImage {
  @Prop uri: string = '';
  @Prop decodeEdge: number = 512;
  @Prop fit: ImageFit = ImageFit.Cover;
  @State private loaded: boolean = false;
  @State private failed: boolean = false;

  build() {
    Stack() {
      Row()
        .width('100%')
        .height('100%')
        .backgroundColor(UiTokens.CONTROL)
      if (this.uri.length > 0 && !this.failed) {
        Image(this.uri)
          .width('100%')
          .height('100%')
          .objectFit(this.fit)
          .sourceSize({ width: this.decodeEdge, height: this.decodeEdge })
          .opacity(this.loaded ? 1 : 0)
          .animation({ duration: MotionPolicy.duration(90), curve: Curve.EaseOut })
          .onComplete((): void => {
            this.loaded = true;
            this.failed = false;
          })
          .onError((): void => {
            this.loaded = false;
            this.failed = true;
          })
      }
      if (this.failed) {
        Button('↻')
          .width(44)
          .height(44)
          .fontSize(22)
          .fontColor(UiTokens.TEXT_SECONDARY)
          .backgroundColor(Color.Transparent)
          .accessibilityText(tr('重新加载图片', 'Reload image'))
          .onClick((): void => {
            this.loaded = false;
            this.failed = false;
          })
      }
    }
    .clip(true)
  }
}
