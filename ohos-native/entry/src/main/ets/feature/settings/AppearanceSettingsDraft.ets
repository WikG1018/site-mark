import { AppSettingsRecord } from '../../domain/Models';

export class AppearanceSettingsDraft {
  themeMode: string = 'system';
  localeCode: string = '';
  defaultWatermarkPosition: string = 'bottomLeft';
  defaultWatermarkOpacity: number = 0.78;
  defaultWatermarkFontScale: number = 1.0;
  locationPermissionPromptDismissed: boolean = false;
  completionNotificationsEnabled: boolean = false;
  appSeed: number = 0xFF37C58B;
  accent: number = 0xFF37C58B;

  static fromSettings(value: AppSettingsRecord): AppearanceSettingsDraft {
    const draft = new AppearanceSettingsDraft();
    draft.themeMode = value.themeMode;
    draft.localeCode = value.localeCode;
    draft.defaultWatermarkPosition = value.defaultWatermarkPosition;
    draft.defaultWatermarkOpacity = value.defaultWatermarkOpacity;
    draft.defaultWatermarkFontScale = value.defaultWatermarkFontScale;
    draft.locationPermissionPromptDismissed = value.locationPermissionPromptDismissed;
    draft.completionNotificationsEnabled = value.completionNotificationsEnabled;
    draft.appSeed = value.appSeedColorArgb;
    draft.accent = value.defaultWatermarkAccentColorArgb;
    return draft;
  }

  selectSeed(argb: number): void {
    this.appSeed = argb;
  }

  selectAccent(argb: number): void {
    this.accent = argb;
  }

  toRecord(): AppSettingsRecord {
    return new AppSettingsRecord({
      themeMode: this.themeMode,
      localeCode: this.localeCode,
      defaultWatermarkPosition: this.defaultWatermarkPosition,
      defaultWatermarkOpacity: this.defaultWatermarkOpacity,
      defaultWatermarkAccentColorArgb: this.accent,
      defaultWatermarkFontScale: this.defaultWatermarkFontScale,
      locationPermissionPromptDismissed: this.locationPermissionPromptDismissed,
      completionNotificationsEnabled: this.completionNotificationsEnabled,
      appSeedColorArgb: this.appSeed
    });
  }
}
