import { describe, expect, it } from '@ohos/hypium';
import { AsyncOnce } from '../main/ets/core/concurrency/AsyncOnce';

class OnceValue {
  readonly id: string;

  constructor(id: string) {
    this.id = id;
  }
}

class DeferredOnceValue {
  readonly promise: Promise<OnceValue>;
  private resolveValue: (value: OnceValue) => void = (_value: OnceValue): void => {};
  private rejectValue: (error: Error) => void = (_error: Error): void => {};

  constructor() {
    this.promise = new Promise<OnceValue>((resolve: (value: OnceValue) => void,
      reject: (error: Error) => void): void => {
      this.resolveValue = resolve;
      this.rejectValue = reject;
    });
  }

  resolve(value: OnceValue): void {
    this.resolveValue(value);
  }

  reject(error: Error): void {
    this.rejectValue(error);
  }
}

export default function asyncOnceTest(): void {
  describe('AsyncOnce', () => {
    it('shares one delayed startup when a resumed caller arrives during initialization', 0, async () => {
      const gate = new AsyncOnce<OnceValue>();
      const deferred = new DeferredOnceValue();
      let calls = 0;

      const first = gate.run((): Promise<OnceValue> => {
        calls += 1;
        return deferred.promise;
      });
      const second = gate.run((): Promise<OnceValue> => {
        calls += 1;
        return Promise.resolve(new OnceValue('unexpected-second'));
      });

      expect(calls).assertEqual(1);
      expect(first === second).assertTrue();
      const expected = new OnceValue('shared');
      deferred.resolve(expected);
      const firstValue = await first;
      const secondValue = await second;
      expect(firstValue === expected).assertTrue();
      expect(secondValue === expected).assertTrue();

      const afterSuccess = new OnceValue('after-success');
      const nextValue = await gate.run((): Promise<OnceValue> => {
        calls += 1;
        return Promise.resolve(afterSuccess);
      });
      expect(calls).assertEqual(2);
      expect(nextValue === afterSuccess).assertTrue();
    });

    it('clears a failed task and allows exactly one retry factory', 0, async () => {
      const gate = new AsyncOnce<OnceValue>();
      const deferred = new DeferredOnceValue();
      let calls = 0;
      let firstFailed = false;
      let secondFailed = false;

      const first = gate.run((): Promise<OnceValue> => {
        calls += 1;
        return deferred.promise;
      });
      const second = gate.run((): Promise<OnceValue> => {
        calls += 1;
        return Promise.resolve(new OnceValue('unexpected-second'));
      });
      expect(first === second).assertTrue();
      expect(calls).assertEqual(1);
      deferred.reject(new Error('expected_initialization_failure'));

      try {
        await first;
      } catch (_) {
        firstFailed = true;
      }
      try {
        await second;
      } catch (_) {
        secondFailed = true;
      }

      const expected = new OnceValue('retry');
      const retried = await gate.run((): Promise<OnceValue> => {
        calls += 1;
        return Promise.resolve(expected);
      });
      expect(firstFailed).assertTrue();
      expect(secondFailed).assertTrue();
      expect(calls).assertEqual(2);
      expect(retried === expected).assertTrue();
    });
  });
}
