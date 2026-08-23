import { describe, expect, it } from '@ohos/hypium';
import { AppSettingsRecord } from '../main/ets/domain/Models';
import { AppearanceSettingsDraft } from '../main/ets/feature/settings/AppearanceSettingsDraft';

function sampleSettings(seed: number, accent: number): AppSettingsRecord {
  return new AppSettingsRecord({
    themeMode: 'dark',
    localeCode: 'zh',
    defaultWatermarkPosition: 'bottomLeft',
    defaultWatermarkOpacity: 0.78,
    defaultWatermarkAccentColorArgb: accent,
    defaultWatermarkFontScale: 1.0,
    locationPermissionPromptDismissed: true,
    completionNotificationsEnabled: false,
    appSeedColorArgb: seed
  });
}

export default function appearanceSettingsDraftTest(): void {
  describe('AppearanceSettingsDraft', () => {
    it('loads seed and accent independently from settings', 0, () => {
      const draft = AppearanceSettingsDraft.fromSettings(sampleSettings(0xFF1565C0, 0xFFEF6C00));
      expect(draft.appSeed).assertEqual(0xFF1565C0);
      expect(draft.accent).assertEqual(0xFFEF6C00);
      expect(draft.themeMode).assertEqual('dark');
      expect(draft.localeCode).assertEqual('zh');
    });

    it('changing the seed does not copy or rewrite the watermark accent', 0, () => {
      const draft = AppearanceSettingsDraft.fromSettings(sampleSettings(0xFF37C58B, 0xFFC62828));
      draft.selectSeed(0xFF1565C0);
      expect(draft.appSeed).assertEqual(0xFF1565C0);
      expect(draft.accent).assertEqual(0xFFC62828);
      const record = draft.toRecord();
      expect(record.appSeedColorArgb).assertEqual(0xFF1565C0);
      expect(record.defaultWatermarkAccentColorArgb).assertEqual(0xFFC62828);
    });

    it('changing the accent does not copy or rewrite the app seed', 0, () => {
      const draft = AppearanceSettingsDraft.fromSettings(sampleSettings(0xFF1565C0, 0xFF37C58B));
      draft.selectAccent(0xFFEF6C00);
      expect(draft.appSeed).assertEqual(0xFF1565C0);
      expect(draft.accent).assertEqual(0xFFEF6C00);
      const record = draft.toRecord();
      expect(record.appSeedColorArgb).assertEqual(0xFF1565C0);
      expect(record.defaultWatermarkAccentColorArgb).assertEqual(0xFFEF6C00);
    });

    it('keeps non-color fields intact when emitting a record', 0, () => {
      const draft = AppearanceSettingsDraft.fromSettings(sampleSettings(0xFF37C58B, 0xFF2E7D61));
      const record = draft.toRecord();
      expect(record.themeMode).assertEqual('dark');
      expect(record.localeCode).assertEqual('zh');
      expect(record.defaultWatermarkPosition).assertEqual('bottomLeft');
      expect(record.defaultWatermarkOpacity).assertEqual(0.78);
      expect(record.defaultWatermarkFontScale).assertEqual(1.0);
      expect(record.locationPermissionPromptDismissed).assertTrue();
      expect(record.completionNotificationsEnabled).assertFalse();
      expect(record.defaultWatermarkAccentColorArgb).assertEqual(0xFF2E7D61);
      expect(record.appSeedColorArgb).assertEqual(0xFF37C58B);
    });
  });
}
