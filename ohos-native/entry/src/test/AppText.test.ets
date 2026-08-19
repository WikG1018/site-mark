import { describe, expect, it } from '@ohos/hypium';
import { AppText, tr } from '../main/ets/shared/AppText';

export default function appTextTest(): void {
  describe('AppText', () => {
    it('uses the explicit application language', 0, () => {
      AppText.apply('en', 'zh-CN');
      expect(tr('项目', 'Projects')).assertEqual('Projects');
      AppText.apply('zh', 'en-US');
      expect(tr('项目', 'Projects')).assertEqual('项目');
    });

    it('follows the system locale when no override is set', 0, () => {
      AppText.apply('', 'en-US');
      expect(tr('设置', 'Settings')).assertEqual('Settings');
      AppText.apply('', 'zh-CN');
      expect(tr('设置', 'Settings')).assertEqual('设置');
    });
  });
}
