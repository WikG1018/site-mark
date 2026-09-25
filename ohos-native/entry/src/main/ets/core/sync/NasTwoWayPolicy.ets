/** Pure two-way NAS sync semantics (H5, mirroring Dart #164). The service
 * supplies I/O; everything decidable from data lives here so it is
 * unit-testable without a network or database.
 *
 * Photo numbers are opaque strings, exactly as Dart treats them: the stem
 * of a .jpg file name, non-empty. photo_number is TEXT on both lines, so no
 * integer assumption is safe. */

export interface NasRemoteFileEntry {
  projectKey: string;
  fileName: string;
}

export interface NasImportCandidateGroup {
  projectKey: string;
  /** Remote-only photo numbers (file-name stems) for the project, in
   * first-seen order, deduplicated. */
  photoNumbers: string[];
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

  /** Photo number encoded in a remote file name: the stem of a .jpg
   * (case-insensitive extension), non-empty. Mirrors Dart exactly. */
  static photoStemOf(fileName: string): string | null {
    if (!fileName.toLowerCase().endsWith('.jpg')) {
      return null;
    }
    const stem = fileName.substring(0, fileName.length - 4);
    return stem.length === 0 ? null : stem;
  }

  /** Remote photos missing on this phone, grouped per project key. Files
   * that are not .jpg photos, duplicates, or numbers the project already
   * holds locally are dropped; groups sort by project key like Dart. */
  static importCandidates(remote: NasRemoteFileEntry[],
    localNumbersByProject: Map<string, Set<string>>): NasImportCandidateGroup[] {
    const collected = new Map<string, Set<string>>();
    for (let i = 0; i < remote.length; i += 1) {
      const entry = remote[i];
      const stem = NasTwoWayPolicy.photoStemOf(entry.fileName);
      if (stem === null) {
        continue;
      }
      const local = localNumbersByProject.get(entry.projectKey);
      if (local !== undefined && local.has(stem)) {
        continue;
      }
      let numbers = collected.get(entry.projectKey);
      if (numbers === undefined) {
        numbers = new Set<string>();
        collected.set(entry.projectKey, numbers);
      }
      numbers.add(stem);
    }
    const groups: NasImportCandidateGroup[] = [];
    collected.forEach((numbers: Set<string>, projectKey: string): void => {
      groups.push({ projectKey: projectKey, photoNumbers: Array.from(numbers) });
    });
    groups.sort((a: NasImportCandidateGroup, b: NasImportCandidateGroup): number =>
      a.projectKey < b.projectKey ? -1 : a.projectKey > b.projectKey ? 1 : 0);
    return groups;
  }
}
