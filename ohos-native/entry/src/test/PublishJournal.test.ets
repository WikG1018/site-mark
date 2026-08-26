import { describe, expect, it } from '@ohos/hypium';
import { InMemoryPublishJournalStorage, PublishJournalStorage,
  PublishJournalStore } from '../main/ets/data/prefs/PublishJournalStore';

class StaticJournalStorage implements PublishJournalStorage {
  private value: string;

  constructor(value: string) { this.value = value; }
  load(): Promise<string> { return Promise.resolve(this.value); }
  save(value: string): Promise<void> { this.value = value; return Promise.resolve(); }
}

export default function publishJournalTest(): void {
  describe('PublishJournalStore', () => {
    it('round trips the active gallery URI and conditionally clears', 0, async () => {
      const storage = new InMemoryPublishJournalStorage();
      const store = new PublishJournalStore(storage);
      await store.record('capture/危险', 'file://media/new');

      const entries = await store.recover();
      expect(entries.length).assertEqual(1);
      expect(entries[0].captureId).assertEqual('capture/危险');
      expect(await store.clear('capture/危险', 'wrong')).assertFalse();
      expect((await store.recover()).length).assertEqual(1);
      expect(await store.clear('capture/危险', 'file://media/new')).assertTrue();
      expect((await store.recover()).length).assertEqual(0);
    });

    it('replaces the same capture atomically without overwriting siblings', 0, async () => {
      const store = new PublishJournalStore(new InMemoryPublishJournalStorage());
      await store.record('a', 'new-1');
      await store.record('b', 'new-b');
      await store.record('a', 'new-2');
      const entries = await store.recover();
      expect(entries.length).assertEqual(2);
      const a = entries.filter((entry) => entry.captureId === 'a')[0];
      expect(a.contentUri).assertEqual('new-2');
    });

    it('keeps valid recovery entries when optional stale URI data is missing', 0, async () => {
      const encoded = '{"version":1,"entries":[' +
        '{"captureId":"a","contentUri":"uri-a","recordedAt":1},' +
        '{"captureId":"","contentUri":"invalid","supersededUris":[]}' +
        ']}';
      const entries = await new PublishJournalStore(new StaticJournalStorage(encoded)).recover();
      expect(entries.length).assertEqual(1);
      expect(entries[0].captureId).assertEqual('a');
    });
  });
}
