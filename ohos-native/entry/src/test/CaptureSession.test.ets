import { describe, expect, it } from '@ohos/hypium';
import { CaptureSessionStore, InMemoryCaptureSessionStorage,
  PendingCaptureSession } from '../main/ets/data/prefs/CaptureSessionStore';

export default function captureSessionTest(): void {
  describe('CaptureSessionStore', () => {
    it('persists every field needed to recover a camera result', 0, async () => {
      const store = new CaptureSessionStore(new InMemoryCaptureSessionStorage());
      const session = new PendingCaptureSession({
        captureId: 'capture-1', projectId: 'project-1', projectName: '项目', targetPath: '/a.jpg',
        workLocation: 'A 区', workContent: '巡检', photographer: '王工', notes: '备注',
        startedAt: 123, watermarkLocaleCode: 'zh'
      });
      await store.save(session);
      const recovered = await store.recover();
      expect(recovered?.captureId).assertEqual('capture-1');
      expect(recovered?.workLocation).assertEqual('A 区');
      await store.clear('wrong');
      expect((await store.recover())?.captureId).assertEqual('capture-1');
      await store.clear('capture-1');
      expect(await store.recover()).assertNull();
    });
  });
}
