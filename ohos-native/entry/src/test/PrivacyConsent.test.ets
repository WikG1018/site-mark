import { describe, expect, it } from '@ohos/hypium';
import { InMemoryConsentStorage, PrivacyConsentStore } from
  '../main/ets/data/prefs/PrivacyConsentStore';

export default function privacyConsentTest(): void {
  describe('PrivacyConsentStore', () => {
    it('hides product until the user explicitly accepts', 0, async () => {
      const storage = new InMemoryConsentStorage();
      const store = new PrivacyConsentStore(storage);
      expect(await store.isAccepted()).assertFalse();
      await store.accept();
      expect(await store.isAccepted()).assertTrue();
    });

    it('does not treat a missing or false value as consent', 0, async () => {
      const storage = new InMemoryConsentStorage();
      await storage.write(false);
      const store = new PrivacyConsentStore(storage);
      expect(await store.isAccepted()).assertFalse();
    });
  });
}
