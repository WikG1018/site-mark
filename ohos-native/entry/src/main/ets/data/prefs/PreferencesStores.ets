import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { CaptureSessionStorage } from './CaptureSessionStore';
import { PublishJournalStorage } from './PublishJournalStore';
import { RestoreJournalStorage } from './RestoreJournalStore';

const PREFERENCES_NAME: string = 'sitemark_runtime';
const CAPTURE_SESSION_KEY: string = 'capture_session_v1';
const PUBLISH_JOURNAL_KEY: string = 'publish_journals_v1';
const RESTORE_JOURNAL_KEY: string = 'restore_journal_v1';

class PreferencesStringStore {
  private readonly context: common.UIAbilityContext;
  private readonly key: string;

  constructor(context: common.UIAbilityContext, key: string) {
    this.context = context;
    this.key = key;
  }

  async load(): Promise<string> {
    const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
    const value = await store.get(this.key, '');
    return typeof value === 'string' ? value : '';
  }

  async save(value: string): Promise<void> {
    const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
    await store.put(this.key, value);
    await store.flush();
  }
}

export class PreferencesCaptureSessionStorage extends PreferencesStringStore
  implements CaptureSessionStorage {
  constructor(context: common.UIAbilityContext) {
    super(context, CAPTURE_SESSION_KEY);
  }
}

export class PreferencesPublishJournalStorage extends PreferencesStringStore
  implements PublishJournalStorage {
  constructor(context: common.UIAbilityContext) {
    super(context, PUBLISH_JOURNAL_KEY);
  }
}

export class PreferencesRestoreJournalStorage extends PreferencesStringStore
  implements RestoreJournalStorage {
  constructor(context: common.UIAbilityContext) {
    super(context, RESTORE_JOURNAL_KEY);
  }
}
