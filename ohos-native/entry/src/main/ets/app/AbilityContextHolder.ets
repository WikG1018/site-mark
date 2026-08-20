import { common } from '@kit.AbilityKit';

export class AbilityContextHolder {
  static current: common.UIAbilityContext | undefined = undefined;

  static require(): common.UIAbilityContext {
    if (AbilityContextHolder.current === undefined) {
      throw new Error('UIAbilityContext is not initialized');
    }
    return AbilityContextHolder.current;
  }
}
