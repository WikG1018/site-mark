import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { UIContext, window } from '@kit.ArkUI';
import { AbilityContextHolder } from '../app/AbilityContextHolder';
import { AppRuntime } from '../app/AppRuntime';
import { forwardUiMemoryLevel } from '../shared/UiMemoryCoordinator';
import { captureIdFromWantParameters, PendingNotificationLaunch }
  from '../shared/PendingNotificationLaunch';
import { SAFE_AREA_BOTTOM_VP, SAFE_AREA_TOP_VP, bottomInsetVp } from '../shared/SystemBars';

const DOMAIN = 0x0000;
const TAG = 'SiteMarkAbility';

export default class EntryAbility extends UIAbility {
  private mainWindow: window.Window | null = null;
  private avoidAreaListener: ((info: window.AvoidAreaOptions) => void) | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AbilityContextHolder.current = this.context;
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    PendingNotificationLaunch.put(captureIdFromWantParameters(want.parameters));
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onCreate');
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    PendingNotificationLaunch.put(captureIdFromWantParameters(want.parameters));
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onNewWant');
  }

  onDestroy(): void {
    AbilityContextHolder.current = undefined;
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'Succeeded in loading the content.');
      this.applyImmersiveLayout(windowStage).catch((error: Error): void => {
        hilog.error(DOMAIN, TAG, 'Failed to apply immersive layout. Cause: %{public}s', JSON.stringify(error));
      });
    });
  }

  private async applyImmersiveLayout(windowStage: window.WindowStage): Promise<void> {
    const win = windowStage.getMainWindowSync();
    await win.setWindowLayoutFullScreen(true);
    await win.setWindowSystemBarProperties({
      statusBarColor: '#00000000',
      navigationBarColor: '#00000000',
      statusBarContentColor: '#17201C',
      navigationBarContentColor: '#17201C'
    });
    const uiContext: UIContext = win.getUIContext();
    const publish = (): void => {
      const systemArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const indicatorArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const topVp = finitePxToVp(uiContext, systemArea.topRect.height);
      const navigationVp = finitePxToVp(uiContext, systemArea.bottomRect.height);
      const indicatorVp = finitePxToVp(uiContext, indicatorArea.bottomRect.height);
      AppStorage.setOrCreate(SAFE_AREA_TOP_VP, topVp);
      AppStorage.setOrCreate(SAFE_AREA_BOTTOM_VP, bottomInsetVp(navigationVp, indicatorVp));
    };
    const listener = (_info: window.AvoidAreaOptions): void => {
      try {
        publish();
      } catch (error) {
        hilog.error(DOMAIN, TAG, 'Failed to refresh avoid area. Cause: %{public}s', JSON.stringify(error));
      }
    };
    publish();
    win.on('avoidAreaChange', listener);
    this.mainWindow = win;
    this.avoidAreaListener = listener;
  }

  onWindowStageDestroy(): void {
    if (this.mainWindow !== null && this.avoidAreaListener !== null) {
      try {
        this.mainWindow.off('avoidAreaChange', this.avoidAreaListener);
      } catch (_) {
      }
    }
    this.mainWindow = null;
    this.avoidAreaListener = null;
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageDestroy');
  }

  onConfigurationUpdate(_newConfig: Configuration): void {
    const runtime = AppRuntime.current;
    if (runtime === null) {
      return;
    }
    runtime.applyAppearance().catch((error: Error): void => {
      hilog.error(DOMAIN, TAG, 'Failed to apply updated appearance. Cause: %{public}s', JSON.stringify(error));
    });
  }

  onForeground(): void {
    const runtime = AppRuntime.current;
    if (runtime !== null) {
      runtime.suspendWindow.release();
    }
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    const runtime = AppRuntime.current;
    if (runtime !== null) {
      runtime.suspendWindow.acquire();
    }
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onBackground');
  }

  onMemoryLevel(level: AbilityConstant.MemoryLevel): void {
    const runtime = AppRuntime.current;
    forwardUiMemoryLevel(level, runtime === null ? null : runtime.uiMemory);
  }
}

function finitePxToVp(uiContext: UIContext, px: number): number {
  if (!Number.isFinite(px) || px <= 0) {
    return 0;
  }
  const vp = uiContext.px2vp(px);
  return Number.isFinite(vp) && vp > 0 ? vp : 0;
}
