import { describe, expect, it } from '@ohos/hypium';
import { NasRemoteFileEntry, NasTwoWayPolicy } from '../main/ets/core/sync/NasTwoWayPolicy';

export default function nasTwoWayPolicyTest(): void {
  describe('NasTwoWayPolicy', () => {
    it('normalizes modes onto the wire values', 0, () => {
      expect(NasTwoWayPolicy.isTwoWay('two_way')).assertTrue();
      expect(NasTwoWayPolicy.isTwoWay('upload_only')).assertFalse();
      expect(NasTwoWayPolicy.normalizeMode('two_way')).assertEqual('two_way');
      expect(NasTwoWayPolicy.normalizeMode('upload_only')).assertEqual('upload_only');
      expect(NasTwoWayPolicy.normalizeMode('')).assertEqual('upload_only');
      expect(NasTwoWayPolicy.normalizeMode('legacy')).assertEqual('upload_only');
    });

    it('takes any non-empty .jpg stem as a photo number', 0, () => {
      expect(NasTwoWayPolicy.photoStemOf('12.jpg')).assertEqual('12');
      expect(NasTwoWayPolicy.photoStemOf('12.JPG')).assertEqual('12');
      expect(NasTwoWayPolicy.photoStemOf('2026-001.jpg')).assertEqual('2026-001');
      // Dart keeps opaque stems: photo_number is TEXT on both lines.
      expect(NasTwoWayPolicy.photoStemOf('a.jpg')).assertEqual('a');
      expect(NasTwoWayPolicy.photoStemOf('12.jpeg')).assertNull();
      expect(NasTwoWayPolicy.photoStemOf('.jpg')).assertNull();
    });

    it('groups remote-only photos per project and sorts groups by key', 0, () => {
      const remote: NasRemoteFileEntry[] = [
        { projectKey: 'bridge-north', fileName: '12.jpg' },
        { projectKey: 'bridge-north', fileName: '3.jpg' },
        { projectKey: 'bridge-north', fileName: '3.JPG' },
        { projectKey: 'bridge-north', fileName: 'notes.txt' },
        { projectKey: 'tower-a', fileName: '1.jpg' },
        { projectKey: 'bridge-north', fileName: '7.jpg' }
      ];
      const local = new Map<string, Set<string>>();
      local.set('bridge-north', new Set<string>(['7']));
      const groups = NasTwoWayPolicy.importCandidates(remote, local);
      expect(groups.length).assertEqual(2);
      const bridge = groups[0];
      expect(bridge.projectKey).assertEqual('bridge-north');
      expect(bridge.photoNumbers.length).assertEqual(2);
      expect(bridge.photoNumbers.includes('3')).assertTrue();
      expect(bridge.photoNumbers.includes('12')).assertTrue();
      const tower = groups[1];
      expect(tower.projectKey).assertEqual('tower-a');
      expect(tower.photoNumbers.length).assertEqual(1);
      expect(tower.photoNumbers[0]).assertEqual('1');
    });

    it('returns nothing when every remote photo exists locally', 0, () => {
      const remote: NasRemoteFileEntry[] = [{ projectKey: 'p', fileName: '1.jpg' }];
      const local = new Map<string, Set<string>>();
      local.set('p', new Set<string>(['1']));
      expect(NasTwoWayPolicy.importCandidates(remote, local).length).assertEqual(0);
    });
  });
}
