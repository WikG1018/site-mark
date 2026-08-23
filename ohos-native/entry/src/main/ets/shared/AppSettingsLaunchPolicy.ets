export class SettingsLaunchWant {
  readonly bundleName: string;
  readonly abilityName: string;
  readonly uri: string;
  readonly action: string;
  readonly parameters: Record<string, Object> | null;

  constructor(bundleName: string, abilityName: string, uri: string, action: string,
    parameters: Record<string, Object> | null) {
    this.bundleName = bundleName;
    this.abilityName = abilityName;
    this.uri = uri;
    this.action = action;
    this.parameters = parameters;
  }
}

export function settingsLaunchCandidates(settingsBundleName: string,
  targetBundleName: string): SettingsLaunchWant[] {
  return [
    new SettingsLaunchWant(settingsBundleName, 'com.huawei.hmos.settings.MainAbility', 'application_info_entry', '',
      { 'pushParams': targetBundleName }),
    new SettingsLaunchWant(settingsBundleName, '', 'application_info_entry', '', { 'pushParams': targetBundleName }),
    new SettingsLaunchWant(settingsBundleName, '', 'locationmanager_settings', '', null),
    new SettingsLaunchWant('', '', '', 'ohos.settings.application.details', { 'pushParams': targetBundleName }),
    new SettingsLaunchWant(settingsBundleName, '', '', '', null),
  ];
}

export type SettingsAbilityStarter = (want: SettingsLaunchWant) => Promise<boolean>;

export class AppSettingsLaunchPolicy {
  private readonly start: SettingsAbilityStarter;

  constructor(start: SettingsAbilityStarter) {
    this.start = start;
  }

  async openApplicationSettings(settingsBundleName: string, targetBundleName: string): Promise<boolean> {
    const candidates = settingsLaunchCandidates(settingsBundleName, targetBundleName);
    for (const want of candidates) {
      let opened = false;
      try {
        opened = await this.start(want);
      } catch (_) {
        opened = false;
      }
      if (opened) {
        return true;
      }
    }
    return false;
  }
}
