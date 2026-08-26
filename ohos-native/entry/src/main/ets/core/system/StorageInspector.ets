import { fileIo } from '@kit.CoreFileKit';

export class StorageSnapshot {
  originals: number;
  rendered: number;
  exports: number;
  other: number;

  constructor(originals: number = 0, rendered: number = 0, exports: number = 0,
    other: number = 0) {
    this.originals = originals;
    this.rendered = rendered;
    this.exports = exports;
    this.other = other;
  }

  total(): number {
    return this.originals + this.rendered + this.exports + this.other;
  }
}
export class StorageInspector {
  static inspect(filesDir: string): StorageSnapshot {
    const result = new StorageSnapshot();
    StorageInspector.walk(filesDir, filesDir, result);
    return result;
  }

  static clearExports(filesDir: string): void {
    const exportDir = `${filesDir}/exports`;
    if (!fileIo.accessSync(exportDir)) {
      return;
    }
    for (const name of fileIo.listFileSync(exportDir)) {
      const path = `${exportDir}/${name}`;
      try {
        const stat = fileIo.statSync(path);
        if (stat.isFile() && name.toLowerCase().endsWith('.zip')) {
          fileIo.unlinkSync(path);
        } else if (stat.isDirectory() && StorageInspector.isInterruptedWorkDirectory(name)) {
          StorageInspector.removeDirectory(path);
        }
      } catch (_) {
      }
    }
  }

  static clearInterruptedExports(filesDir: string): void {
    const exportDir = `${filesDir}/exports`;
    if (!fileIo.accessSync(exportDir)) {
      return;
    }
    for (const name of fileIo.listFileSync(exportDir)) {
      if (!StorageInspector.isInterruptedWorkDirectory(name)) {
        continue;
      }
      const path = `${exportDir}/${name}`;
      try {
        if (fileIo.statSync(path).isDirectory()) {
          StorageInspector.removeDirectory(path);
        }
      } catch (_) {
      }
    }
  }

  private static isInterruptedWorkDirectory(name: string): boolean {
    return /^work-[0-9a-fA-F-]{36}$/.test(name);
  }

  private static removeDirectory(path: string): void {
    if (!fileIo.accessSync(path)) {
      return;
    }
    for (const name of fileIo.listFileSync(path)) {
      const child = `${path}/${name}`;
      const stat = fileIo.statSync(child);
      if (stat.isDirectory()) {
        StorageInspector.removeDirectory(child);
      } else {
        fileIo.unlinkSync(child);
      }
    }
    fileIo.rmdirSync(path);
  }

  private static walk(root: string, directory: string, result: StorageSnapshot): void {
    if (!fileIo.accessSync(directory)) {
      return;
    }
    let names: string[] = [];
    try {
      names = fileIo.listFileSync(directory);
    } catch (_) {
      return;
    }
    for (const name of names) {
      const path = `${directory}/${name}`;
      try {
        const stat = fileIo.statSync(path);
        if (stat.isDirectory()) {
          StorageInspector.walk(root, path, result);
        } else {
          const relative = path.substring(root.length + 1);
          if (relative.startsWith('originals/')) {
            result.originals += stat.size;
          } else if (relative.startsWith('renders/')) {
            result.rendered += stat.size;
          } else if (relative.startsWith('exports/')) {
            result.exports += stat.size;
          } else {
            result.other += stat.size;
          }
        }
      } catch (_) {
      }
    }
  }
}
