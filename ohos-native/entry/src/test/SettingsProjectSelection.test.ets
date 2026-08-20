import { describe, expect, it } from '@ohos/hypium';
import { StableSelectionList } from '../main/ets/feature/settings/SettingsProjectSelection';

class RecordingListener implements DataChangeListener {
  reloads: number = 0;
  changed: number[] = [];

  onDataReloaded(): void { this.reloads += 1; }
  onDataAdded(_index: number): void {}
  onDataAdd(_index: number): void {}
  onDataMoved(_from: number, _to: number): void {}
  onDataMove(_from: number, _to: number): void {}
  onDataDeleted(_index: number): void {}
  onDataDelete(_index: number): void {}
  onDataChanged(index: number): void { this.changed.push(index); }
  onDataChange(index: number): void { this.changed.push(index); }
  onDatasetChange(_operations: DataOperation[]): void {}
}

interface ProjectOption {
  id: string;
  name: string;
}

export default function settingsProjectSelectionTest(): void {
  describe('Settings project selection', () => {
    it('discards an expired project load and retains the newest rows', 0, () => {
      const selection = new StableSelectionList<ProjectOption>((row: ProjectOption): string => row.id);
      const initialRequest = selection.beginLoad();
      const newestRequest = selection.beginLoad();

      expect(selection.replaceFor(initialRequest, [{ id: 'old', name: 'Old project' }])).assertFalse();
      expect(selection.replaceFor(newestRequest, [{ id: 'new', name: 'New project' }])).assertTrue();
      expect(selection.count()).assertEqual(1);
      expect(selection.data.getData(0).id).assertEqual('new');
    });

    it('notifies visible stable-key rows when selection changes', 0, () => {
      const selection = new StableSelectionList<ProjectOption>((row: ProjectOption): string => row.id);
      const listener = new RecordingListener();
      selection.data.registerDataChangeListener(listener);
      const request = selection.beginLoad();
      selection.replaceFor(request, [{ id: 'a', name: 'Alpha' }, { id: 'b', name: 'Beta' }]);
      listener.changed = [];

      selection.toggle('b');

      expect(selection.isSelected('a')).assertFalse();
      expect(selection.isSelected('b')).assertTrue();
      expect(selection.selectedIds().join(',')).assertEqual('b');
      expect(listener.changed.join(',')).assertEqual('0,1');
    });
  });
}
