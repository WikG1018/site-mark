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
  private channel: MethodChannel | null = null;
  private host: OhosSystemHost | null = null;

  getUniqueClassName(): string {
    return 'SiteMarkSystemPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.host = new OhosSystemHost(binding.getApplicationContext() as common.Context);
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'sitemark.system.ohos');
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel !== null) {
      this.channel.setMethodCallHandler(null);
    }
    this.channel = null;
    this.host = null;
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.host?.attachAbility(binding.getAbility());
  }

  onDetachedFromAbility(): void {
    this.host?.detachAbility();
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
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
