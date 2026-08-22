import { describe, expect, it } from '@ohos/hypium';
import {
  CaptureKillDraftSnapshot,
  CaptureKillDraftStore,
  InMemoryCaptureKillDraftStorage
} from '../main/ets/data/prefs/CaptureKillDraftStore';
import { RecentCaptureSeed, resolveFormSeed } from '../main/ets/feature/capture/CaptureFormPolicy';

function draftOf(projectId: string, location: string, content: string, photographer: string,
  notes: string): CaptureKillDraftSnapshot {
  return new CaptureKillDraftSnapshot({
    projectId: projectId,
    workLocation: location,
    workContent: content,
    photographer: photographer,
    notes: notes
  });
}

function carryOf(location: string, content: string, photographer: string): RecentCaptureSeed {
  return { workLocation: location, workContent: content, photographer: photographer };
}

export default function captureKillDraftTest(): void {
  describe('Capture kill draft', () => {
    it('restores the exact unsaved fields for the matching project', 0, async () => {
      const store = new CaptureKillDraftStore(new InMemoryCaptureKillDraftStorage());
      await store.save(draftOf('p1', ' 现场 B ', '内容B', '李工', '备注B'));
      const restored = await store.recover('p1');
      expect(restored === null).assertFalse();
      if (restored === null) return;
      expect(restored.projectId).assertEqual('p1');
      expect(restored.workLocation).assertEqual(' 现场 B ');
      expect(restored.workContent).assertEqual('内容B');
      expect(restored.photographer).assertEqual('李工');
      expect(restored.notes).assertEqual('备注B');
    });

    it('keeps other projects safe when the requested id does not match', 0, async () => {
      const store = new CaptureKillDraftStore(new InMemoryCaptureKillDraftStorage());
      await store.save(draftOf('p1', '现场B', '内容B', '李工', ''));
      const foreign = await store.recover('p2');
      expect(foreign === null).assertTrue();
      await store.clear('p2');
      const kept = await store.recover('p1');
      expect(kept === null).assertFalse();
    });

    it('clears only after the same project captures successfully', 0, async () => {
      const store = new CaptureKillDraftStore(new InMemoryCaptureKillDraftStorage());
      await store.save(draftOf('p1', '现场B', '内容B', '李工', '备注B'));
      await store.clear('p1');
      const cleared = await store.recover('p1');
      expect(cleared === null).assertTrue();
    });

    it('treats malformed or empty persistence payloads as no draft', 0, async () => {
      const storage = new InMemoryCaptureKillDraftStorage();
      await storage.save('not-json{');
      const corrupt = new CaptureKillDraftStore(storage);
      const broken = await corrupt.recover('p1');
      expect(broken === null).assertTrue();

      const blank = new CaptureKillDraftStore(new InMemoryCaptureKillDraftStorage());
      const fresh = await blank.recover('p1');
      expect(fresh === null).assertTrue();
    });

    it('kill draft wins over carry-forward and restores notes', 0, () => {
      const seed = resolveFormSeed(draftOf('p1', '现场B', '内容B', '李工', '备注B'),
        carryOf('现场A', '内容A', '王工'));
      expect(seed.fromKillDraft).assertTrue();
      expect(seed.workLocation).assertEqual('现场B');
      expect(seed.workContent).assertEqual('内容B');
      expect(seed.photographer).assertEqual('李工');
      expect(seed.notes).assertEqual('备注B');
    });

    it('falls back to carry-forward without notes when no usable draft exists', 0, () => {
      const empty = resolveFormSeed(draftOf('p1', '', '', '', ''), carryOf('现场A', '内容A', '王工'));
      expect(empty.fromKillDraft).assertFalse();
      expect(empty.workLocation).assertEqual('现场A');
      expect(empty.workContent).assertEqual('内容A');
      expect(empty.photographer).assertEqual('王工');
      expect(empty.notes).assertEqual('');

      const none = resolveFormSeed(null, null);
      expect(none.fromKillDraft).assertFalse();
      expect(none.workLocation.length === 0 && none.workContent.length === 0 &&
        none.photographer.length === 0 && none.notes.length === 0).assertTrue();
    });
  });
}
