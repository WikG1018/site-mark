import { describe, expect, it } from '@ohos/hypium';
import { PressGesturePolicy, PressGestureState } from '../main/ets/shared/PressGesture';
import { MotionPolicy } from '../main/ets/shared/MotionPolicy';

export default function pressGestureTest(): void {
  describe('PressGesturePolicy', () => {
    it('presses on Down and releases on Up', 0, () => {
      let state = PressGesturePolicy.next(PressGestureState.idle(), { type: 'Down', x: 10, y: 10 });
      expect(state.pressed).assertTrue();
      state = PressGesturePolicy.next(state, { type: 'Up', x: 12, y: 10 });
      expect(state.pressed).assertFalse();
      expect(state.cancelled).assertFalse();
    });

    it('keeps the press while moving within the slop', 0, () => {
      let state = PressGesturePolicy.next(PressGestureState.idle(), { type: 'Down', x: 0, y: 0 });
      state = PressGesturePolicy.next(state, { type: 'Move', x: 6, y: 0 });
      expect(state.pressed).assertTrue();
      state = PressGesturePolicy.next(state, { type: 'Move', x: 5, y: 5 });
      expect(state.pressed).assertTrue();
    });

    it('cancels permanently once the slop is crossed', 0, () => {
      let state = PressGesturePolicy.next(PressGestureState.idle(), { type: 'Down', x: 0, y: 0 });
      state = PressGesturePolicy.next(state, { type: 'Move', x: 30, y: 0 });
      expect(state.pressed).assertFalse();
      expect(state.cancelled).assertTrue();
      // Moving back inside the slop must not resurrect the press.
      state = PressGesturePolicy.next(state, { type: 'Move', x: 1, y: 0 });
      expect(state.pressed).assertFalse();
      expect(state.cancelled).assertTrue();
    });

    it('re-arms after Cancel', 0, () => {
      let state = PressGesturePolicy.next(PressGestureState.idle(), { type: 'Down', x: 0, y: 0 });
      state = PressGesturePolicy.next(state, { type: 'Cancel', x: 0, y: 0 });
      expect(state.pressed).assertFalse();
      state = PressGesturePolicy.next(state, { type: 'Down', x: 5, y: 5 });
      expect(state.pressed).assertTrue();
    });

    it('applies the 0.96 press scale only while pressed', 0, () => {
      expect(PressGesturePolicy.SCALE).assertEqual(0.96);
      const pressed = new PressGestureState(true, false, 0, 0);
      expect(PressGesturePolicy.scaleOf(pressed)).assertEqual(0.96);
      expect(PressGesturePolicy.scaleOf(PressGestureState.idle())).assertEqual(1);
    });

    it('stays completely still under reduce-motion', 0, () => {
      MotionPolicy.commit(true);
      const pressed = new PressGestureState(true, false, 0, 0);
      expect(PressGesturePolicy.scaleOf(pressed)).assertEqual(1);
      MotionPolicy.commit(false);
      expect(PressGesturePolicy.scaleOf(pressed)).assertEqual(0.96);
    });
  });
}
