import { describe, expect, it } from '@ohos/hypium';
import { LazyListDataSource } from '../main/ets/shared/LazyListDataSource';

class RecordingListener implements DataChangeListener {
  reloads: number = 0;
  added: number[] = [];
  changed: number[] = [];

  onDataReloaded(): void { this.reloads += 1; }
  onDataAdded(index: number): void { this.added.push(index); }
  onDataAdd(index: number): void { this.added.push(index); }
  onDataMoved(_from: number, _to: number): void {}
  onDataMove(_from: number, _to: number): void {}
  onDataDeleted(_index: number): void {}
  onDataDelete(_index: number): void {}
  onDataChanged(index: number): void { this.changed.push(index); }
  onDataChange(index: number): void { this.changed.push(index); }
  onDatasetChange(_operations: DataOperation[]): void {}
}

function rejectsIndex(source: LazyListDataSource<string>, index: number): boolean {
  try {
    source.getData(index);
    return false;
  } catch (_) {
    return true;
  }
}

export default function lazyListDataSourceTest(): void {
  describe('LazyListDataSource', () => {
    it('reloads on the first replace and changes every stable-key item on replacement', 0, () => {
      const source = new LazyListDataSource<string>((value: string): string => value);
      const listener = new RecordingListener();
      source.registerDataChangeListener(listener);

      source.replace(['a', 'b']);
      source.replace(['a', 'b']);

      expect(listener.reloads).assertEqual(1);
      expect(listener.changed.join(',')).assertEqual('0,1');
    });

    it('reloads the first empty replacement but ignores a second identical empty replacement', 0, () => {
      const source = new LazyListDataSource<string>((value: string): string => value);
      const listener = new RecordingListener();
      source.registerDataChangeListener(listener);

      source.replace([]);
      source.replace([]);

      expect(listener.reloads).assertEqual(1);
      expect(listener.changed.length).assertEqual(0);
    });

    it('reloads when replacement key order changes', 0, () => {
      const source = new LazyListDataSource<string>((value: string): string => value);
      const listener = new RecordingListener();
      source.registerDataChangeListener(listener);

      source.replace(['a', 'b']);
      source.replace(['b', 'a']);

      expect(listener.reloads).assertEqual(2);
      expect(listener.changed.length).assertEqual(0);
    });

    it('appends only unseen keys and notifies each added position', 0, () => {
      const source = new LazyListDataSource<string>((value: string): string => value);
      const listener = new RecordingListener();
      source.registerDataChangeListener(listener);
      source.replace(['a', 'b']);

      source.appendUnique(['b', 'c', 'd', 'c']);

      expect(source.snapshot().join(',')).assertEqual('a,b,c,d');
      expect(listener.added.join(',')).assertEqual('2,3');
    });

    it('isolates snapshots, rejects invalid indexes, and stops notifying unregistered listeners', 0, () => {
      const values: string[] = ['a'];
      const source = new LazyListDataSource<string>((value: string): string => value);
      const listener = new RecordingListener();
      source.registerDataChangeListener(listener);
      source.registerDataChangeListener(listener);
      source.replace(values);
      expect(listener.reloads).assertEqual(1);
      values.push('outside');
      const snapshot = source.snapshot();
      snapshot.push('also-outside');

      expect(source.totalCount()).assertEqual(1);
      expect(source.getData(0)).assertEqual('a');
      expect(rejectsIndex(source, Number.NaN)).assertTrue();
      expect(rejectsIndex(source, Number.POSITIVE_INFINITY)).assertTrue();
      expect(rejectsIndex(source, Number.NEGATIVE_INFINITY)).assertTrue();
      expect(rejectsIndex(source, 0.5)).assertTrue();
      expect(rejectsIndex(source, -1)).assertTrue();
      expect(rejectsIndex(source, 1)).assertTrue();
      source.unregisterDataChangeListener(listener);
      source.appendUnique(['b']);
      expect(listener.added.length).assertEqual(0);
    });
  });
}
