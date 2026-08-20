export interface RenderPhotoRequest {
  sourcePath: string;
  outputPath: string;
  projectName: string;
  workLocation: string;
  workContent: string;
  photographer: string;
  photoNumber: string;
  capturedAt: string;
  address: string;
  coordinates: string;
  notes: string;
  position: string;
  opacity: number;
  accentColorArgb: number;
  fontScale: number;
  localeCode: string;
}

export interface RenderPhotoResult {
  outputPath: string;
  outputSha256: string;
  width: number;
  height: number;
}

export interface ImagePipeline {
  readonly isDegraded: boolean;
  render(request: RenderPhotoRequest): Promise<RenderPhotoResult>;
  sha256(path: string): Promise<string>;
  exportProject(requestJson: string): Promise<string>;
  exportSelection(requestJson: string): Promise<string>;
  exportDiagnostic(requestJson: string): Promise<string>;
  readProjectArchive(path: string): Promise<string>;
  extractArchivePhoto(requestJson: string): Promise<string>;
  exportBundle(requestJson: string): Promise<string>;
  readBundle(path: string): Promise<string>;
  extractBundleEntry(requestJson: string): Promise<void>;
}

export class ImagePipelineFailure extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ImagePipelineFailure';
  }
}

export class UnavailableImagePipeline implements ImagePipeline {
  readonly isDegraded: boolean = true;
  private readonly reason: string;

  constructor(reason: string) {
    this.reason = reason;
  }

  private fail<T>(): Promise<T> {
    return Promise.reject(new ImagePipelineFailure(`invalid_data:${this.reason}`));
  }

  render(_: RenderPhotoRequest): Promise<RenderPhotoResult> {
    return this.fail<RenderPhotoResult>();
  }

  sha256(_: string): Promise<string> {
    return this.fail<string>();
  }

  exportProject(_: string): Promise<string> {
    return this.fail<string>();
  }

  exportSelection(_: string): Promise<string> {
    return this.fail<string>();
  }

  exportDiagnostic(_: string): Promise<string> {
    return this.fail<string>();
  }

  readProjectArchive(_: string): Promise<string> {
    return this.fail<string>();
  }

  extractArchivePhoto(_: string): Promise<string> {
    return this.fail<string>();
  }

  exportBundle(_: string): Promise<string> {
    return this.fail<string>();
  }

  readBundle(_: string): Promise<string> {
    return this.fail<string>();
  }

  extractBundleEntry(_: string): Promise<void> {
    return this.fail<void>();
  }
}
