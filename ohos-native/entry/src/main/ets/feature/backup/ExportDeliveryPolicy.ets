export enum ExportDeliveryChannel {
  SHARE_PANEL = 'share_panel',
  DOCUMENT_SAVE = 'document_save',
  CANCELLED = 'cancelled'
}

export class ExportDeliveryOutcome {
  readonly delivered: boolean;
  readonly channel: ExportDeliveryChannel;

  constructor(delivered: boolean, channel: ExportDeliveryChannel) {
    this.delivered = delivered;
    this.channel = channel;
  }
}

export class ArchiveDeliveryCoordinator {
  private readonly showSharePanel: (() => Promise<boolean>) | null;
  private readonly saveViaPicker: () => Promise<boolean>;

  constructor(showSharePanel: (() => Promise<boolean>) | null, saveViaPicker: () => Promise<boolean>) {
    this.showSharePanel = showSharePanel;
    this.saveViaPicker = saveViaPicker;
  }

  async deliver(): Promise<ExportDeliveryOutcome> {
    if (this.showSharePanel !== null) {
      let shown = false;
      try {
        shown = await this.showSharePanel();
      } catch (_) {
        shown = false;
      }
      if (shown) {
        return new ExportDeliveryOutcome(true, ExportDeliveryChannel.SHARE_PANEL);
      }
    }
    const saved = await this.saveViaPicker();
    return new ExportDeliveryOutcome(saved,
      saved ? ExportDeliveryChannel.DOCUMENT_SAVE : ExportDeliveryChannel.CANCELLED);
  }
}
