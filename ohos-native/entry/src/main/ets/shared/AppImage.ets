import { tr } from './AppText';
import { MotionPolicy } from './MotionPolicy';
import { UiTokens } from './UiTokens';

export class ImageDecodePolicy {
  static thumbnail(edgeVp: number, density: number): number {
    const edge = edgeVp * density;
    if (!Number.isFinite(edge) || edge <= 0) {
      return 256;
    }
    return Math.min(1024, Math.max(256, Math.ceil(edge)));
  }

  static sourceSizeEdge(edge: number): number {
    if (!Number.isFinite(edge) || edge <= 0) {
      return 256;
    }
    return Math.min(2048, Math.max(1, Math.ceil(edge)));
  }

  static detail(): number {
    return 2048;
  }

  static viewer(current: boolean): number {
    return current ? 2048 : 1024;
  }
}

export class ImageRequestState {
  uri: string;
  generation: number;
  loaded: boolean;
  failed: boolean;

  constructor(uri: string, generation: number, loaded: boolean, failed: boolean) {
    this.uri = uri;
    this.generation = generation;
    this.loaded = loaded;
    this.failed = failed;
  }

  static initial(): ImageRequestState {
    return new ImageRequestState('', 0, false, false);
  }

  forUri(uri: string): ImageRequestState {
    if (uri === this.uri) {
      return this;
    }
    return new ImageRequestState(uri, this.generation + 1, false, false);
  }

  complete(generation: number): ImageRequestState {
    if (generation !== this.generation) {
      return this;
    }
    return new ImageRequestState(this.uri, this.generation, true, false);
  }

  fail(generation: number): ImageRequestState {
    if (generation !== this.generation) {
      return this;
    }
    return new ImageRequestState(this.uri, this.generation, false, true);
  }

  retry(): ImageRequestState {
    return new ImageRequestState(this.uri, this.generation + 1, false, false);
  }
}

@Component
export struct AppImage {
  @Watch('onUriChanged')
  @Prop uri: string = '';
  @Prop decodeEdge: number = 512;
  @Prop fit: ImageFit = ImageFit.Cover;
  @State private request: ImageRequestState = ImageRequestState.initial();

  aboutToAppear(): void {
    this.onUriChanged();
  }

  private onUriChanged(): void {
    this.request = this.request.forUri(this.uri);
  }

  private completeCallback(generation: number): () => void {
    return (): void => {
      this.request = this.request.complete(generation);
    };
  }

  private failCallback(generation: number): () => void {
    return (): void => {
      this.request = this.request.fail(generation);
    };
  }

  build() {
    Stack() {
      Row()
        .width('100%')
        .height('100%')
        .backgroundColor(UiTokens.IMAGE_PLACEHOLDER)
      if (this.request.uri.length > 0 && !this.request.failed) {
        Image(this.request.uri)
          .key(`app-image-${this.request.generation}`)
          .width('100%')
          .height('100%')
          .objectFit(this.fit)
          .sourceSize({ width: ImageDecodePolicy.sourceSizeEdge(this.decodeEdge),
            height: ImageDecodePolicy.sourceSizeEdge(this.decodeEdge) })
          .opacity(this.request.loaded ? 1 : 0)
          .animation({ duration: MotionPolicy.duration(90), curve: Curve.EaseOut })
          .onComplete(this.completeCallback(this.request.generation))
          .onError(this.failCallback(this.request.generation))
      }
      if (this.request.failed) {
        Button('↻')
          .width(44)
          .height(44)
          .fontSize(22)
          .fontColor(UiTokens.TEXT_SECONDARY)
          .backgroundColor(Color.Transparent)
          .accessibilityText(tr('重新加载图片', 'Reload image'))
          .onClick((): void => {
            this.request = this.request.retry();
          })
      }
    }
    .clip(true)
  }
}
