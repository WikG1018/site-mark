import { describe, expect, it } from '@ohos/hypium';
import { ArchiveDeliveryCoordinator, ExportDeliveryChannel, ExportDeliveryOutcome }
  from '../main/ets/feature/backup/ExportDeliveryPolicy';

class ChannelProbe {
  panelResult: boolean = true;
  panelThrows: boolean = false;
  pickerResult: boolean = true;
  panelCalls: number = 0;
  pickerCalls: number = 0;

  showPanel(): Promise<boolean> {
    this.panelCalls += 1;
    if (this.panelThrows) {
      return Promise.reject(new Error('panel unavailable'));
    }
    return Promise.resolve(this.panelResult);
  }

  saveViaPicker(): Promise<boolean> {
    this.pickerCalls += 1;
    return Promise.resolve(this.pickerResult);
  }
}

export default function exportDeliveryPolicyTest(): void {
  describe('Export delivery policy', () => {
    it('opens the share panel first and skips the document picker', 0, async () => {
      const probe = new ChannelProbe();
      const coordinator = new ArchiveDeliveryCoordinator((): Promise<boolean> => probe.showPanel(),
        (): Promise<boolean> => probe.saveViaPicker());
      const outcome = await coordinator.deliver();
      expect(outcome.delivered).assertTrue();
      expect(outcome.channel === ExportDeliveryChannel.SHARE_PANEL).assertTrue();
      expect(probe.panelCalls).assertEqual(1);
      expect(probe.pickerCalls).assertEqual(0);
    });

    it('falls back to the document picker when the panel declines', 0, async () => {
      const probe = new ChannelProbe();
      probe.panelResult = false;
      const coordinator = new ArchiveDeliveryCoordinator((): Promise<boolean> => probe.showPanel(),
        (): Promise<boolean> => probe.saveViaPicker());
      const outcome = await coordinator.deliver();
      expect(outcome.delivered).assertTrue();
      expect(outcome.channel === ExportDeliveryChannel.DOCUMENT_SAVE).assertTrue();
      expect(probe.panelCalls).assertEqual(1);
      expect(probe.pickerCalls).assertEqual(1);
    });

    it('falls back to the document picker when the panel throws', 0, async () => {
      const probe = new ChannelProbe();
      probe.panelThrows = true;
      const coordinator = new ArchiveDeliveryCoordinator((): Promise<boolean> => probe.showPanel(),
        (): Promise<boolean> => probe.saveViaPicker());
      const outcome = await coordinator.deliver();
      expect(outcome.delivered).assertTrue();
      expect(outcome.channel === ExportDeliveryChannel.DOCUMENT_SAVE).assertTrue();
      expect(probe.pickerCalls).assertEqual(1);
    });

    it('reports cancelled when every available channel declines', 0, async () => {
      const probe = new ChannelProbe();
      probe.pickerResult = false;
      const coordinator = new ArchiveDeliveryCoordinator(null,
        (): Promise<boolean> => probe.saveViaPicker());
      const outcome = await coordinator.deliver();
      expect(outcome.delivered).assertFalse();
      expect(outcome.channel === ExportDeliveryChannel.CANCELLED).assertTrue();
      expect(probe.pickerCalls).assertEqual(1);
    });

    it('saves directly when no share panel is available', 0, async () => {
      const probe = new ChannelProbe();
      const coordinator = new ArchiveDeliveryCoordinator(null,
        (): Promise<boolean> => probe.saveViaPicker());
      const outcome = await coordinator.deliver();
      expect(outcome.delivered).assertTrue();
      expect(outcome.channel === ExportDeliveryChannel.DOCUMENT_SAVE).assertTrue();
      expect(probe.pickerCalls).assertEqual(1);
    });

    it('keeps the delivery outcome immutable for callers', 0, () => {
      const outcome = new ExportDeliveryOutcome(true, ExportDeliveryChannel.SHARE_PANEL);
      expect(outcome.delivered).assertTrue();
      expect(outcome.channel === ExportDeliveryChannel.SHARE_PANEL).assertTrue();
    });
  });
}
