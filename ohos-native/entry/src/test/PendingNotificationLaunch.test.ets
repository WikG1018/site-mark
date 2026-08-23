import { describe, expect, it } from '@ohos/hypium';
import { captureIdFromWantParameters, PendingNotificationLaunch }
  from '../main/ets/shared/PendingNotificationLaunch';

class ConsumerProbe {
  received: string[] = [];

  consume(captureId: string): void {
    this.received.push(captureId);
  }

  last(): string {
    return this.received.length > 0 ? this.received[this.received.length - 1] : '';
  }
}

export default function pendingNotificationLaunchTest(): void {
  describe('PendingNotificationLaunch', () => {
    it('parses the capture id from want parameters', 0, () => {
      PendingNotificationLaunch.reset();
      const empty: Record<string, Object> = {};
      const unrelated: Record<string, Object> = { 'other': 'cap-1' };
      const blankId: Record<string, Object> = { 'captureId': '' };
      const whitespaceId: Record<string, Object> = { 'captureId': '   ' };
      const booleanId: Record<string, Object> = { 'captureId': true };
      const validId: Record<string, Object> = { 'captureId': 'cap-1' };
      const paddedId: Record<string, Object> = { 'captureId': ' cap-1 ' };
      const numericId: Record<string, Object> = { 'captureId': 42 };
      expect(captureIdFromWantParameters(undefined)).assertEqual('');
      expect(captureIdFromWantParameters(empty)).assertEqual('');
      expect(captureIdFromWantParameters(unrelated)).assertEqual('');
      expect(captureIdFromWantParameters(blankId)).assertEqual('');
      expect(captureIdFromWantParameters(whitespaceId)).assertEqual('');
      expect(captureIdFromWantParameters(booleanId)).assertEqual('');
      expect(captureIdFromWantParameters(validId)).assertEqual('cap-1');
      expect(captureIdFromWantParameters(paddedId)).assertEqual('cap-1');
      expect(captureIdFromWantParameters(numericId)).assertEqual('42');
    });

    it('parks a launch until a consumer attaches and replays it once', 0, () => {
      PendingNotificationLaunch.reset();
      const coldStart = new ConsumerProbe();
      PendingNotificationLaunch.put('cap-1');
      expect(coldStart.received.length).assertEqual(0);
      PendingNotificationLaunch.attach((id: string): void => coldStart.consume(id));
      expect(coldStart.last()).assertEqual('cap-1');
      const replay = new ConsumerProbe();
      PendingNotificationLaunch.attach((id: string): void => replay.consume(id));
      expect(replay.received.length).assertEqual(0);
    });

    it('dispatches directly to an attached consumer without parking', 0, () => {
      PendingNotificationLaunch.reset();
      const probe = new ConsumerProbe();
      PendingNotificationLaunch.attach((id: string): void => probe.consume(id));
      PendingNotificationLaunch.put('cap-2');
      expect(probe.last()).assertEqual('cap-2');
    });

    it('keeps only the most recent pending launch', 0, () => {
      PendingNotificationLaunch.reset();
      const probe = new ConsumerProbe();
      PendingNotificationLaunch.put('cap-a');
      PendingNotificationLaunch.put('cap-b');
      PendingNotificationLaunch.attach((id: string): void => probe.consume(id));
      expect(probe.last()).assertEqual('cap-b');
      expect(probe.received.length).assertEqual(1);
    });

    it('ignores empty capture ids whether parked or live', 0, () => {
      PendingNotificationLaunch.reset();
      const probe = new ConsumerProbe();
      PendingNotificationLaunch.attach((id: string): void => probe.consume(id));
      PendingNotificationLaunch.put('   ');
      expect(probe.received.length).assertEqual(0);
      PendingNotificationLaunch.reset();
      PendingNotificationLaunch.put('');
      PendingNotificationLaunch.attach((id: string): void => probe.consume(id));
      expect(probe.received.length).assertEqual(0);
    });
  });
}
