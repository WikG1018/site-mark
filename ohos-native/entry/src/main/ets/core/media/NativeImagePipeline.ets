import sitemarkNative from 'libsitemark_native.so';
import { ImagePipeline, ImagePipelineFailure, RenderPhotoRequest,
  RenderPhotoResult } from './ImagePipeline';

interface NativeCall<T> {
  operation: string;
  payload: T;
}

interface NativeResponse<T> {
  ok: boolean;
  value: T | null;
  error: string | null;
}

interface NativePathRequest {
  path: string;
}

interface NativeRenderRequest {
  source_path: string;
  output_path: string;
  project_name: string;
  work_location: string;
  work_content: string;
  photographer: string;
  photo_number: string;
  captured_at: string;
  address: string | null;
  coordinates: string | null;
  notes: string | null;
  position: string;
  opacity: number;
  accent_color_argb: number;
  font_scale: number;
  locale_code: string;
}

interface NativeRenderResult {
  output_path: string;
  output_sha256: string;
  width: number;
  height: number;
}

export class NativeImagePipeline implements ImagePipeline {
  readonly isDegraded: boolean = false;

  private async call<TPayload, TValue>(operation: string, payload: TPayload): Promise<TValue> {
    const request: NativeCall<TPayload> = { operation: operation, payload: payload };
    const encoded = await sitemarkNative.call(JSON.stringify(request));
    const response = JSON.parse(encoded) as NativeResponse<TValue>;
    if (!response.ok || response.value === null) {
      throw new ImagePipelineFailure(response.error ?? 'invalid_data:empty native response');
    }
    return response.value;
  }

  private async callRaw(operation: string, payloadJson: string): Promise<string> {
    const encoded = await sitemarkNative.call(`{"operation":${JSON.stringify(operation)},"payload":${payloadJson}}`);
    const response = JSON.parse(encoded) as NativeResponse<Object>;
    if (!response.ok) {
      throw new ImagePipelineFailure(response.error ?? 'invalid_data:empty native response');
    }
    return JSON.stringify(response.value);
  }

  async render(request: RenderPhotoRequest): Promise<RenderPhotoResult> {
    const payload: NativeRenderRequest = {
      source_path: request.sourcePath,
      output_path: request.outputPath,
      project_name: request.projectName,
      work_location: request.workLocation,
      work_content: request.workContent,
      photographer: request.photographer,
      photo_number: request.photoNumber,
      captured_at: request.capturedAt,
      address: request.address.length === 0 ? null : request.address,
      coordinates: request.coordinates.length === 0 ? null : request.coordinates,
      notes: request.notes.length === 0 ? null : request.notes,
      position: request.position === 'bottomRight' ? 'BottomRight' : 'BottomLeft',
      opacity: request.opacity,
      accent_color_argb: request.accentColorArgb,
      font_scale: request.fontScale,
      locale_code: request.localeCode
    };
    const value = await this.call<NativeRenderRequest, NativeRenderResult>('render', payload);
    return {
      outputPath: value.output_path,
      outputSha256: value.output_sha256,
      width: value.width,
      height: value.height
    };
  }

  sha256(path: string): Promise<string> {
    const payload: NativePathRequest = { path: path };
    return this.call<NativePathRequest, string>('sha256', payload);
  }

  exportProject(requestJson: string): Promise<string> {
    return this.callRaw('export', requestJson);
  }

  exportSelection(requestJson: string): Promise<string> {
    return this.callRaw('exportSelection', requestJson);
  }

  exportDiagnostic(requestJson: string): Promise<string> {
    return this.callRaw('exportDiagnostic', requestJson);
  }

  readProjectArchive(path: string): Promise<string> {
    const payload: NativePathRequest = { path: path };
    return this.call<NativePathRequest, Object>('readProjectArchive', payload)
      .then((value: Object): string => JSON.stringify(value));
  }

  extractArchivePhoto(requestJson: string): Promise<string> {
    return this.callRaw('extractArchivePhoto', requestJson);
  }

  exportBundle(requestJson: string): Promise<string> {
    return this.callRaw('exportBundle', requestJson);
  }

  readBundle(path: string): Promise<string> {
    const payload: NativePathRequest = { path: path };
    return this.call<NativePathRequest, Object>('readBundle', payload)
      .then((value: Object): string => JSON.stringify(value));
  }

  async extractBundleEntry(requestJson: string): Promise<void> {
    await this.callRaw('extractBundleEntry', requestJson);
  }
}
