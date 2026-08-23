import { systemShare } from '@kit.ShareKit';
import { fileUri } from '@kit.CoreFileKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

export class SystemSharePanel {
  show(context: common.UIAbilityContext, path: string): Promise<boolean> {
    try {
      const data: systemShare.SharedData = new systemShare.SharedData({
        utd: uniformTypeDescriptor.UniformDataType.ZIP_ARCHIVE,
        uri: fileUri.getUriFromPath(path)
      });
      const controller: systemShare.ShareController = new systemShare.ShareController(data);
      const options: systemShare.ShareControllerOptions = {};
      return controller.show(context, options).then((): boolean => true)
        .catch((_error: BusinessError): boolean => false);
    } catch (_) {
      return Promise.resolve(false);
    }
  }
}
