import {
  AbilityAware,
  AbilityPluginBinding,
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import common from '@ohos.app.ability.common';
import OhosSystemHost from './OhosSystemHost';

export default class SiteMarkSystemPlugin implements FlutterPlugin, AbilityAware, MethodCallHandler {
  private static instance: SiteMarkSystemPlugin | null = null;
  private static pendingDeepLink: string | null = null;
  private static dartListening: boolean = false;
  private channel: MethodChannel | null = null;
  private pathChannel: MethodChannel | null = null;
  private packageInfoChannel: MethodChannel | null = null;
  private host: OhosSystemHost | null = null;

  static deliverNotificationTap(deepLink: string): void {
    if (deepLink.length === 0) {
      return;
    }
    const plugin = SiteMarkSystemPlugin.instance;
    if (SiteMarkSystemPlugin.dartListening && plugin !== null && plugin.channel !== null) {
      plugin.channel.invokeMethod('notificationTap', deepLink);
      return;
    }
    SiteMarkSystemPlugin.pendingDeepLink = deepLink;
  }

  getUniqueClassName(): string {
    return 'SiteMarkSystemPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    SiteMarkSystemPlugin.instance = this;
    this.host = new OhosSystemHost(binding.getApplicationContext() as common.Context);
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'sitemark.system.ohos');
    this.channel.setMethodCallHandler(this);
    this.pathChannel = new MethodChannel(binding.getBinaryMessenger(), 'plugins.flutter.io/path_provider');
    this.pathChannel.setMethodCallHandler(this);
    this.packageInfoChannel = new MethodChannel(
      binding.getBinaryMessenger(),
      'dev.fluttercommunity.plus/package_info',
    );
    this.packageInfoChannel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel !== null) {
      this.channel.setMethodCallHandler(null);
    }
    if (this.pathChannel !== null) {
      this.pathChannel.setMethodCallHandler(null);
    }
    if (this.packageInfoChannel !== null) {
      this.packageInfoChannel.setMethodCallHandler(null);
    }
    this.channel = null;
    this.pathChannel = null;
    this.packageInfoChannel = null;
    this.host = null;
    if (SiteMarkSystemPlugin.instance === this) {
      SiteMarkSystemPlugin.instance = null;
      SiteMarkSystemPlugin.dartListening = false;
    }
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.host?.attachAbility(binding.getAbility());
  }

  onDetachedFromAbility(): void {
    this.host?.detachAbility();
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'takePendingNotificationTap') {
      SiteMarkSystemPlugin.dartListening = true;
      const pending = SiteMarkSystemPlugin.pendingDeepLink;
      SiteMarkSystemPlugin.pendingDeepLink = null;
      result.success(pending ?? '');
      return;
    }
    const host = this.host;
    if (host === null) {
      result.error('ohos_not_ready', call.method, null);
      return;
    }
    const args = this.asRecord(call.args);
    host.handle(call.method, args).then((value: Object | null) => {
      result.success(value);
    }).catch((error: Error) => {
      if (error.message === 'ohos_not_ready' || error.message.startsWith('ohos_not_ready')) {
        result.error('ohos_not_ready', call.method, null);
        return;
      }
      if (error.message.startsWith('unimplemented:')) {
        result.notImplemented();
        return;
      }
      result.error('ohos_system', error.message, null);
    });
  }

  private asRecord(value: Object | null): Record<string, Object | null | undefined> | null {
    if (value === null || value === undefined) {
      return null;
    }
    if (value instanceof Map) {
      const record: Record<string, Object | null | undefined> = {};
      value.forEach((entryValue: Object, key: Object) => {
        record[`${key}`] = entryValue as Object;
      });
      return record;
    }
    return value as Record<string, Object | null | undefined>;
  }
}
