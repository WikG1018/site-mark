import { bundleManager } from '@kit.AbilityKit';

export class AppVersionInfo {
  versionName: string;
  versionCode: string;

  constructor(versionName: string, versionCode: string) {
    this.versionName = versionName;
    this.versionCode = versionCode;
  }
}

export async function loadAppVersion(): Promise<AppVersionInfo> {
  try {
    const info = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
    return new AppVersionInfo(info.versionName, info.versionCode.toString());
  } catch (_) {
    return new AppVersionInfo('unknown', 'unknown');
  }
}
