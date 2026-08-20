import { describe, expect, it } from '@ohos/hypium';
import { StableSelectionList } from '../main/ets/feature/settings/SettingsProjectSelection';
import { AppText } from '../main/ets/shared/AppText';
import { settingsBackAccessibilityText, settingsConfirmationButtonHeight, watermarkAccentAccessibilityText,
  watermarkAccentOptions, WatermarkAccentOption, diagnosticsConfirmAccessibilityText }
  from '../main/ets/feature/settings/SettingsAccessibility';
import { choiceAccessibilityText, joinAccessibilityText, lifecycleAccessibilityText }
  from '../main/ets/shared/AccessibilityText';
import { UiTokens } from '../main/ets/shared/UiTokens';

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

    it('discards a project load invalidated by component teardown', 0, () => {
      const selection = new StableSelectionList<ProjectOption>((row: ProjectOption): string => row.id);
      const request = selection.beginLoad();

      selection.invalidate();

      expect(selection.replaceFor(request, [{ id: 'stale', name: 'Stale project' }])).assertFalse();
      expect(selection.count()).assertEqual(0);
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

    it('clears a selected project when the same stable row is toggled again', 0, () => {
      const selection = new StableSelectionList<ProjectOption>((row: ProjectOption): string => row.id);
      const request = selection.beginLoad();
      selection.replaceFor(request, [{ id: 'a', name: 'Alpha' }]);

      selection.toggle('a');
      selection.toggle('a');

      expect(selection.isSelected('a')).assertFalse();
      expect(selection.selectedIds().length).assertEqual(0);
    });

    it('provides localized and distinct settings accessibility labels', 0, () => {
      const options = watermarkAccentOptions();
      AppText.apply('zh', 'en-US');
      const chineseBack = settingsBackAccessibilityText();
      const chineseLabels = options.map((option: WatermarkAccentOption): string =>
        watermarkAccentAccessibilityText(option, false));
      const chineseSelectedLabels = options.map((option: WatermarkAccentOption): string =>
        watermarkAccentAccessibilityText(option, true));
      AppText.apply('en', 'zh-CN');
      const englishBack = settingsBackAccessibilityText();
      const englishLabels = options.map((option: WatermarkAccentOption): string =>
        watermarkAccentAccessibilityText(option, false));
      const englishSelectedLabels = options.map((option: WatermarkAccentOption): string =>
        watermarkAccentAccessibilityText(option, true));

      expect(chineseBack.length > 0).assertTrue();
      expect(englishBack.length > 0).assertTrue();
      expect(chineseBack === englishBack).assertFalse();
      expect(new Set<string>(chineseLabels).size).assertEqual(5);
      expect(new Set<string>(chineseSelectedLabels).size).assertEqual(5);
      expect(new Set<string>(englishLabels).size).assertEqual(5);
      expect(new Set<string>(englishSelectedLabels).size).assertEqual(5);
      expect(chineseLabels.every((label: string): boolean => label.length > 0)).assertTrue();
      expect(chineseSelectedLabels.every((label: string): boolean => label.length > 0)).assertTrue();
      expect(englishLabels.every((label: string): boolean => label.length > 0)).assertTrue();
      expect(englishSelectedLabels.every((label: string): boolean => label.length > 0)).assertTrue();
      expect(englishSelectedLabels[0] === englishLabels[0]).assertFalse();
      AppText.apply('', 'zh-CN');
    });

    it('keeps diagnostics confirmation actions at the shared touch target height', 0, () => {
      expect(settingsConfirmationButtonHeight()).assertEqual(UiTokens.TOUCH_TARGET);
      expect(settingsConfirmationButtonHeight() >= 44).assertTrue();
    });

    it('announces option state and punctuation in the active language', 0, () => {
      AppText.apply('zh', 'en-US');
      expect(choiceAccessibilityText('浅色', true)).assertEqual('浅色，已选择');
      expect(choiceAccessibilityText('浅色', false)).assertEqual('浅色，未选择');
      expect(lifecycleAccessibilityText('进行中', true)).assertEqual('进行中，当前');
      expect(joinAccessibilityText(['项目', '3 条记录'])).assertEqual('项目，3 条记录');

      AppText.apply('en', 'zh-CN');
      expect(choiceAccessibilityText('Light', true)).assertEqual('Light, selected');
      expect(choiceAccessibilityText('Light', false)).assertEqual('Light, not selected');
      expect(lifecycleAccessibilityText('Active', true)).assertEqual('Active, current');
      expect(joinAccessibilityText(['Project', '3 records'])).assertEqual('Project, 3 records');
      expect(diagnosticsConfirmAccessibilityText()).assertEqual('Confirm and choose save location');
      AppText.apply('', 'zh-CN');
    });
  });
}
