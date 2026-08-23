import { ExportDeliveryChannel } from '../backup/ExportDeliveryPolicy';

export enum DiagnosticsGenerationStatus {
  SAVED = 'saved',
  CANCELLED = 'cancelled',
  FAILED = 'failed'
}

export class DiagnosticsGenerationOutcome {
  readonly status: DiagnosticsGenerationStatus;
  readonly eventCount: number;
  readonly channel: ExportDeliveryChannel;

  constructor(status: DiagnosticsGenerationStatus, eventCount: number,
    channel: ExportDeliveryChannel = ExportDeliveryChannel.DOCUMENT_SAVE) {
    this.status = status;
    this.eventCount = eventCount;
    this.channel = channel;
  }
}

export class DiagnosticsGenerationOutcomeStore {
  private pending: DiagnosticsGenerationOutcome | null = null;

  publish(outcome: DiagnosticsGenerationOutcome): void {
    this.pending = outcome;
  }

  consume(): DiagnosticsGenerationOutcome | null {
    const outcome: DiagnosticsGenerationOutcome | null = this.pending;
    this.pending = null;
    return outcome;
  }

  clear(): void {
    this.pending = null;
  }
}
