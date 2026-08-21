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
  requestVersion: number;

  constructor(uri: string, generation: number, loaded: boolean, failed: boolean, requestVersion: number = 0) {
    this.uri = uri;
    this.generation = generation;
    this.loaded = loaded;
    this.failed = failed;
    this.requestVersion = requestVersion;
  }

  static initial(): ImageRequestState {
    return new ImageRequestState('', 0, false, false);
  }

  forUri(uri: string): ImageRequestState {
    return this.forRequest(uri, this.requestVersion);
  }

  forRequest(uri: string, requestVersion: number): ImageRequestState {
    if (uri === this.uri && requestVersion === this.requestVersion) {
      return this;
    }
    return new ImageRequestState(uri, this.generation + 1, false, false, requestVersion);
  }

  complete(generation: number): ImageRequestState {
    if (generation !== this.generation) {
      return this;
    }
    return new ImageRequestState(this.uri, this.generation, true, false, this.requestVersion);
  }

  fail(generation: number): ImageRequestState {
    if (generation !== this.generation) {
      return this;
    }
    return new ImageRequestState(this.uri, this.generation, false, true, this.requestVersion);
  }

  retry(): ImageRequestState {
    return new ImageRequestState(this.uri, this.generation + 1, false, false, this.requestVersion);
  }

  accepts(generation: number, uri: string): boolean {
    return generation === this.generation && uri === this.uri;
  }

  nodeIdentity(): string {
    return `app-image-${this.generation}-${this.requestVersion}`;
  }
}

@Component
export struct AppImage {
  @Watch('onRequestChanged')
  @Prop uri: string = '';
  @Watch('onRequestChanged')
  @Prop requestVersion: number = 0;
  @Prop decodeEdge: number = 512;
  @Prop fit: ImageFit = ImageFit.Cover;
  @Prop transparentPlaceholder: boolean = false;
  @Prop callbackToken: number = 0;
  @Prop callbackAuxToken: number = 0;
  @Prop callbackKey: string = '';
  @State private request: ImageRequestState = ImageRequestState.initial();
  onLoaded: (token: number, auxiliaryToken: number, key: string, uri: string) => void =
    (_token: number, _auxiliaryToken: number, _key: string, _uri: string): void => {};
  onFailed: (token: number, auxiliaryToken: number, key: string, uri: string) => void =
    (_token: number, _auxiliaryToken: number, _key: string, _uri: string): void => {};

  aboutToAppear(): void {
    this.onRequestChanged();
  }

  private onRequestChanged(): void {
    this.request = this.request.forRequest(this.uri, this.requestVersion);
  }

  private completeCallback(generation: number, uri: string, callbackToken: number,
    callbackAuxToken: number, callbackKey: string): () => void {
    return (): void => {
      if (!this.request.accepts(generation, uri)) {
        return;
      }
      this.request = this.request.complete(generation);
      this.onLoaded(callbackToken, callbackAuxToken, callbackKey, uri);
    };
  }

  private failCallback(generation: number, uri: string, callbackToken: number,
    callbackAuxToken: number, callbackKey: string): () => void {
    return (): void => {
      if (!this.request.accepts(generation, uri)) {
        return;
      }
      this.request = this.request.fail(generation);
      this.onFailed(callbackToken, callbackAuxToken, callbackKey, uri);
    };
  }

  build() {
    Stack() {
      Row()
        .width('100%')
        .height('100%')
        .backgroundColor(this.transparentPlaceholder ? Color.Transparent : UiTokens.IMAGE_PLACEHOLDER)
      if (this.request.uri.length > 0 && !this.request.failed) {
        Stack() {
          ForEach([this.request], (request: ImageRequestState) => {
            Image(request.uri)
              .width('100%')
              .height('100%')
              .objectFit(this.fit)
              .sourceSize({ width: ImageDecodePolicy.sourceSizeEdge(this.decodeEdge),
                height: ImageDecodePolicy.sourceSizeEdge(this.decodeEdge) })
              .onComplete(this.completeCallback(request.generation, request.uri, this.callbackToken,
                this.callbackAuxToken, this.callbackKey))
              .onError(this.failCallback(request.generation, request.uri, this.callbackToken,
                this.callbackAuxToken, this.callbackKey))
          }, (request: ImageRequestState): string => request.nodeIdentity())
        }
        .width('100%')
        .height('100%')
        .opacity(this.request.loaded ? 1 : 0)
        .animation({ duration: MotionPolicy.duration(this.transparentPlaceholder ? 0 : 90), curve: Curve.EaseOut })
      }
      if (this.request.failed && !this.transparentPlaceholder) {
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
