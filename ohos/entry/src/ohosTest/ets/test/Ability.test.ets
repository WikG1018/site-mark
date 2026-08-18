import hilog from '@ohos.hilog';
import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium'

export default function abilityTest() {
  describe('ActsAbilityTest', function () {
    beforeAll(function () {
    })
    beforeEach(function () {
    })
    afterEach(function () {
    })
    afterAll(function () {
    })
    it('assertContain',0, function () {
      hilog.info(0x0000, 'testTag', '%{public}s', 'it begin');
      let a = 'abc'
      let b = 'b'
      expect(a).assertContain(b)
      expect(a).assertEqual(a)
    })
  })
}
