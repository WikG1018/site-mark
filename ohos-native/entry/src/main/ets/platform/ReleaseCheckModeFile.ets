import { fileIo } from '@kit.CoreFileKit';
import util from '@ohos.util';
import { normalizeReleaseCheckMode } from '../shared/ReleaseCheck';

const FILE_NAME: string = 'release_check_mode.txt';

export function readReleaseCheckModeFile(filesDir: string): string {
  try {
    const path = `${filesDir}/${FILE_NAME}`;
    if (!fileIo.accessSync(path)) {
      return 'auto';
    }
    const stat = fileIo.statSync(path);
    if (stat.size <= 0) {
      return 'auto';
    }
    const size = stat.size > 64 ? 64 : stat.size;
    const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    try {
      const buffer = new ArrayBuffer(size);
      fileIo.readSync(file.fd, buffer);
      const text = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buffer));
      return normalizeReleaseCheckMode(text);
    } finally {
      fileIo.closeSync(file);
    }
  } catch (_) {
    return 'auto';
  }
}

export function writeReleaseCheckModeFile(filesDir: string, mode: string): void {
  const normalized = normalizeReleaseCheckMode(mode);
  const path = `${filesDir}/${FILE_NAME}`;
  const file = fileIo.openSync(path,
    fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
  try {
    fileIo.writeSync(file.fd, normalized);
  } finally {
    fileIo.closeSync(file);
  }
}
