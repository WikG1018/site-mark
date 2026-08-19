import { describe, expect, it } from '@ohos/hypium';
import { backgroundPublishOutcome } from '../main/ets/core/system/SystemServices';

export default function albumPublishPolicyTest(): void {
  describe('AlbumPublishPolicy', () => {
    it('finishes a new background render without opening an interactive album flow', 0, () => {
      const outcome = backgroundPublishOutcome('');

      expect(outcome.contentUri).assertEqual('');
      expect(outcome.enteredSystemAlbum).assertFalse();
      expect(outcome.supersededUris.length).assertEqual(0);
    });

    it('preserves an existing album reference while a replacement awaits user action', 0, () => {
      const outcome = backgroundPublishOutcome('file://media/Photo/17');

      expect(outcome.contentUri).assertEqual('file://media/Photo/17');
      expect(outcome.enteredSystemAlbum).assertTrue();
      expect(outcome.supersededUris.length).assertEqual(0);
    });
  });
}
