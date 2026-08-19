import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { ConsentStorage } from './PrivacyConsentStore';

const PREFERENCES_NAME: string = 'sitemark_settings';
const CONSENT_KEY: string = 'privacy_consent_accepted_v1';

export class PreferencesConsentStorage implements ConsentStorage {
  private readonly context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async read(): Promise<boolean> {
    const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
    const value = await store.get(CONSENT_KEY, false);
    return value === true;
  }

  async write(value: boolean): Promise<void> {
    const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
    await store.put(CONSENT_KEY, value);
    await store.flush();
  }
}
