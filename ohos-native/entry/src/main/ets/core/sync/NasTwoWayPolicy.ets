/** Pure two-way NAS sync semantics (H5, mirroring Dart #164). The service
 * supplies I/O; everything decidable from data lives here so it is
 * unit-testable without a network or database. */

export interface NasRemoteFileEntry {
  projectKey: string;
  fileName: string;
}

export interface NasImportCandidateGroup {
  projectKey: string;
  /** Remote-only photo numbers for the project, ascending, deduplicated. */
  photoNumbers: number[];
}

export class NasTwoWayPolicy {
  static readonly MODE_UPLOAD_ONLY: string = 'upload_only';
  static readonly MODE_TWO_WAY: string = 'two_way';

  static isTwoWay(mode: string): boolean {
    return mode === NasTwoWayPolicy.MODE_TWO_WAY;
  }

  /** Normalizes any stored/legacy value onto a valid mode wire value. */
  static normalizeMode(mode: string): string {
    return NasTwoWayPolicy.isTwoWay(mode) ?
      NasTwoWayPolicy.MODE_TWO_WAY : NasTwoWayPolicy.MODE_UPLOAD_ONLY;
  }

  /** Photo number encoded in a remote file name: the stem must be a
   * positive integer and the extension .jpg (case-insensitive). */
  static photoNumberOf(fileName: string): number | null {
    const lower = fileName.toLowerCase();
    if (!lower.endsWith('.jpg')) {
      return null;
    }
    const stem = fileName.substring(0, fileName.length - 4);
    if (stem.length === 0) {
      return null;
    }
    const value = Number(stem);
    if (!Number.isInteger(value) || value <= 0) {
      return null;
    }
    return value;
  }

  /** Remote photos missing on this phone, grouped per project key. Files
   * that are not photo numbers, duplicates, or numbers the project already
   * holds locally are dropped. Photo numbers are returned ascending. */
  static importCandidates(remote: NasRemoteFileEntry[],
    localNumbersByProject: Map<string, Set<number>>): NasImportCandidateGroup[] {
    const collected = new Map<string, Set<number>>();
    for (let i = 0; i < remote.length; i += 1) {
      const entry = remote[i];
      const number = NasTwoWayPolicy.photoNumberOf(entry.fileName);
      if (number === null) {
        continue;
      }
      const local = localNumbersByProject.get(entry.projectKey);
      if (local !== undefined && local.has(number)) {
        continue;
      }
      let numbers = collected.get(entry.projectKey);
      if (numbers === undefined) {
        numbers = new Set<number>();
        collected.set(entry.projectKey, numbers);
      }
      numbers.add(number);
    }
    const groups: NasImportCandidateGroup[] = [];
    collected.forEach((numbers: Set<number>, projectKey: string): void => {
      const sorted = Array.from(numbers).sort((a: number, b: number): number => a - b);
      groups.push({ projectKey: projectKey, photoNumbers: sorted });
    });
    return groups;
  }

  /** Remote-delete guard: only two-way mode deletes, and only when the
   * record actually reached the NAS. Local deletes never depend on it. */
  static shouldDeleteRemote(mode: string, uploaded: boolean): boolean {
    return NasTwoWayPolicy.isTwoWay(mode) && uploaded;
  }
}
