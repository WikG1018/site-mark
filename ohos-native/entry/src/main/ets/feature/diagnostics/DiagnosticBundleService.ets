import { deviceInfo } from '@kit.BasicServicesKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { AppRuntime } from '../../app/AppRuntime';
import { DiagnosticEventRecord } from '../../data/database/AppDatabase';

interface DiagnosticEnvironmentJson {
  app_version: string;
  build_number: string;
  operating_system: string;
  operating_system_version: string;
  sdk_api_version: number;
  locale: string;
  engine: string;
}

interface DiagnosticEventJson {
  category: string;
  outcome: string;
  duration_ms: number;
  created_at: string;
}

interface DiagnosticManifestJson {
  schema_version: number;
  generated_at: string;
  retention_days: number;
  max_event_count: number;
  privacy_profile: string;
}

interface ExportDiagnosticJson {
  output_zip_path: string;
  summary: string;
  environment_json: string;
  events_jsonl: string;
  manifest_json: string;
}

export class DiagnosticBundleResult {
  path: string;
  fileName: string;
  eventCount: number;

  constructor(path: string, fileName: string, eventCount: number) {
    this.path = path;
    this.fileName = fileName;
    this.eventCount = eventCount;
  }
}

export class DiagnosticBundleService {
  private readonly runtime: AppRuntime;

  constructor(runtime: AppRuntime) {
    this.runtime = runtime;
  }

  async generate(): Promise<DiagnosticBundleResult> {
    const events = await this.runtime.database.diagnosticEvents();
    const generatedAt = new Date().toISOString();
    const environment: DiagnosticEnvironmentJson = {
      app_version: '1.0.0',
      build_number: '1',
      operating_system: 'HarmonyOS',
      operating_system_version: deviceInfo.osFullName,
      sdk_api_version: deviceInfo.sdkApiVersion,
      locale: (await this.runtime.database.settings()).localeCode || 'system',
      engine: this.runtime.pipeline.isDegraded ? 'unavailable' : 'sitemark_core'
    };
    const eventLines: string[] = [];
    for (const event of events) {
      const value: DiagnosticEventJson = this.eventJson(event);
      eventLines.push(JSON.stringify(value));
    }
    const manifest: DiagnosticManifestJson = {
      schema_version: 1,
      generated_at: generatedAt,
      retention_days: 7,
      max_event_count: 200,
      privacy_profile: 'no_business_content_v1'
    };
    const summary = `SiteMark diagnostic bundle\nGenerated at: ${generatedAt}\nEvents: ${events.length}\n\n` +
      `SiteMark 诊断包\n生成时间：${generatedAt}\n事件数量：${events.length}\n` +
      '不包含照片、项目名称、工程内容、拍摄人、位置、文件路径、哈希、原始异常或堆栈。';
    const directory = `${this.runtime.context.filesDir}/diagnostics`;
    if (!fileIo.accessSync(directory)) {
      fileIo.mkdirSync(directory, true);
    }
    const fileName = `SiteMark-Diagnostics-${this.fileStamp(Date.now())}.zip`;
    const path = `${directory}/${fileName}`;
    const request: ExportDiagnosticJson = {
      output_zip_path: path,
      summary: summary,
      environment_json: JSON.stringify(environment),
      events_jsonl: eventLines.join('\n'),
      manifest_json: JSON.stringify(manifest)
    };
    try {
      await this.runtime.pipeline.exportDiagnostic(JSON.stringify(request));
      await this.runtime.recordDiagnosticBestEffort('diagnostics', 'success', 0);
      return new DiagnosticBundleResult(path, fileName, events.length);
    } catch (_) {
      await this.runtime.recordDiagnosticBestEffort('diagnostics', 'failure', 0);
      throw new Error('诊断包生成失败，请检查存储空间后重试');
    }
  }

  async saveAs(result: DiagnosticBundleResult): Promise<boolean> {
    const documentPicker = new picker.DocumentViewPicker(this.runtime.context);
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [result.fileName];
    options.fileSuffixChoices = ['ZIP|.zip'];
    const uris = await documentPicker.save(options);
    if (uris.length === 0) {
      return false;
    }
    await fileIo.copyFile(result.path, uris[0]);
    return true;
  }

  private eventJson(event: DiagnosticEventRecord): DiagnosticEventJson {
    return {
      category: event.category,
      outcome: event.outcome,
      duration_ms: Math.max(0, event.durationMs),
      created_at: new Date(event.createdAt).toISOString()
    };
  }

  private fileStamp(value: number): string {
    const date = new Date(value);
    const part = (number: number): string => number.toString().padStart(2, '0');
    return `${date.getFullYear()}${part(date.getMonth() + 1)}${part(date.getDate())}-` +
      `${part(date.getHours())}${part(date.getMinutes())}${part(date.getSeconds())}`;
  }
}
