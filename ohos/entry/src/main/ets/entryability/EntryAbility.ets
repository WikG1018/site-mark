import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { AbilityConstant, Want } from '@kit.AbilityKit';
import SiteMarkSystemPlugin from 'sitemark_system_api';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';

export default class EntryAbility extends FlutterAbility {
  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    super.onCreate(want, launchParam)
    this.deliverNotificationTap(want)
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    super.onNewWant(want, launchParam)
    this.deliverNotificationTap(want)
  }

  private deliverNotificationTap(want: Want): void {
    const link = want.parameters?.['sitemarkDeepLink']
    if (typeof link === 'string' && link.length > 0) {
      SiteMarkSystemPlugin.deliverNotificationTap(link)
    }
  }
}
