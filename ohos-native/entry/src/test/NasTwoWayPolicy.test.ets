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

    it('parses photo numbers from remote file names', 0, () => {
      expect(NasTwoWayPolicy.photoNumberOf('12.jpg')).assertEqual(12);
      expect(NasTwoWayPolicy.photoNumberOf('12.JPG')).assertEqual(12);
      expect(NasTwoWayPolicy.photoNumberOf('030.jpg')).assertEqual(30);
      expect(NasTwoWayPolicy.photoNumberOf('a.jpg')).assertNull();
      expect(NasTwoWayPolicy.photoNumberOf('12.jpeg')).assertNull();
      expect(NasTwoWayPolicy.photoNumberOf('.jpg')).assertNull();
      expect(NasTwoWayPolicy.photoNumberOf('0.jpg')).assertNull();
      expect(NasTwoWayPolicy.photoNumberOf('-3.jpg')).assertNull();
      expect(NasTwoWayPolicy.photoNumberOf('1.5.jpg')).assertNull();
    });

    it('groups remote-only photos per project, ascending and deduplicated', 0, () => {
      const remote: NasRemoteFileEntry[] = [
        { projectKey: 'bridge-north', fileName: '12.jpg' },
        { projectKey: 'bridge-north', fileName: '3.jpg' },
        { projectKey: 'bridge-north', fileName: '3.JPG' },
        { projectKey: 'bridge-north', fileName: 'notes.txt' },
        { projectKey: 'bridge-north', fileName: '7.jpg' },
        { projectKey: 'tower-a', fileName: '1.jpg' }
      ];
      const local = new Map<string, Set<number>>();
      local.set('bridge-north', new Set<number>([7]));
      const groups = NasTwoWayPolicy.importCandidates(remote, local);
      expect(groups.length).assertEqual(2);
      const bridge = groups[0];
      expect(bridge.projectKey).assertEqual('bridge-north');
      expect(bridge.photoNumbers.length).assertEqual(2);
      expect(bridge.photoNumbers[0]).assertEqual(3);
      expect(bridge.photoNumbers[1]).assertEqual(12);
      const tower = groups[1];
      expect(tower.projectKey).assertEqual('tower-a');
      expect(tower.photoNumbers.length).assertEqual(1);
      expect(tower.photoNumbers[0]).assertEqual(1);
    });

    it('returns nothing when every remote photo exists locally', 0, () => {
      const remote: NasRemoteFileEntry[] = [{ projectKey: 'p', fileName: '1.jpg' }];
      const local = new Map<string, Set<number>>();
      local.set('p', new Set<number>([1]));
      expect(NasTwoWayPolicy.importCandidates(remote, local).length).assertEqual(0);
    });

    it('gates remote deletes on two-way mode and an actual upload', 0, () => {
      expect(NasTwoWayPolicy.shouldDeleteRemote('two_way', true)).assertTrue();
      expect(NasTwoWayPolicy.shouldDeleteRemote('two_way', false)).assertFalse();
      expect(NasTwoWayPolicy.shouldDeleteRemote('upload_only', true)).assertFalse();
    });
  });
}
