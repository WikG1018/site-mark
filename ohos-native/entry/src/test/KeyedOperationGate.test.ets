import { describe, expect, it } from '@ohos/hypium';
import { KeyedOperationGate } from '../main/ets/core/concurrency/KeyedOperationGate';

export default function keyedOperationGateTest(): void {
  describe('KeyedOperationGate', () => {
    it('allows only one active operation for each capture id', 0, () => {
      const gate = new KeyedOperationGate();

      expect(gate.tryEnter('capture-a')).assertTrue();
      expect(gate.tryEnter('capture-a')).assertFalse();
      expect(gate.tryEnter('capture-b')).assertTrue();

      gate.leave('capture-a');
      expect(gate.tryEnter('capture-a')).assertTrue();
    });

    it('ignores empty keys and makes repeated leave idempotent', 0, () => {
      const gate = new KeyedOperationGate();

      expect(gate.tryEnter('  ')).assertFalse();
      gate.leave('capture-a');
      gate.leave('capture-a');
      expect(gate.tryEnter('capture-a')).assertTrue();
    });
  });
}
