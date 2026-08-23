import { describe, expect, it } from '@ohos/hypium';
import { AppSettingsLaunchPolicy, SettingsLaunchWant } from '../main/ets/shared/AppSettingsLaunchPolicy';

class StarterProbe {
  calls: number = 0;
  wants: SettingsLaunchWant[] = [];
  succeedOnCall: number = 0;
  throwOnCall: number = 0;

  start(want: SettingsLaunchWant): Promise<boolean> {
    this.calls += 1;
    this.wants.push(want);
    if (this.throwOnCall === this.calls) {
      return Promise.reject(new Error('starter failed'));
    }
    return Promise.resolve(this.succeedOnCall === this.calls);
  }

  wantAt(index: number): SettingsLaunchWant | null {
    if (index < 0 || index >= this.wants.length) {
      return null;
    }
    return this.wants[index];
  }
}

export default function appSettingsLaunchPolicyTest(): void {
  describe('AppSettingsLaunchPolicy', () => {
    it('starts with the full explicit settings want carrying the target bundle', 0, async () => {
      const probe = new StarterProbe();
      probe.succeedOnCall = 1;
      const policy = new AppSettingsLaunchPolicy((w: SettingsLaunchWant): Promise<boolean> => probe.start(w));
      const opened = await policy.openApplicationSettings('settings.host', 'app.target');
      expect(opened).assertTrue();
      expect(probe.calls).assertEqual(1);
      const first = probe.wantAt(0);
      expect(first === null).assertFalse();
      if (first !== null) {
        expect(first.bundleName).assertEqual('settings.host');
        expect(first.abilityName).assertEqual('com.huawei.hmos.settings.MainAbility');
        expect(first.uri).assertEqual('application_info_entry');
        expect(`${first.parameters !== null ? first.parameters['pushParams'] : ''}`).assertEqual('app.target');
      }
    });

    it('falls back to a bundle-only uri want when the explicit ability is declined', 0, async () => {
      const probe = new StarterProbe();
      probe.succeedOnCall = 2;
      const policy = new AppSettingsLaunchPolicy((w: SettingsLaunchWant): Promise<boolean> => probe.start(w));
      const opened = await policy.openApplicationSettings('settings.host', 'app.target');
      expect(opened).assertTrue();
      expect(probe.calls).assertEqual(2);
      const second = probe.wantAt(1);
      expect(second === null).assertFalse();
      if (second !== null) {
        expect(second.bundleName).assertEqual('settings.host');
        expect(second.abilityName).assertEqual('');
        expect(second.uri).assertEqual('application_info_entry');
      }
    });

    it('tries the location manager page before the generic details action', 0, async () => {
      const probe = new StarterProbe();
      probe.succeedOnCall = 3;
      const policy = new AppSettingsLaunchPolicy((w: SettingsLaunchWant): Promise<boolean> => probe.start(w));
      await policy.openApplicationSettings('settings.host', 'app.target');
      expect(probe.calls).assertEqual(3);
      const third = probe.wantAt(2);
      expect(third === null).assertFalse();
      if (third !== null) {
        expect(third.bundleName).assertEqual('settings.host');
        expect(third.uri).assertEqual('locationmanager_settings');
        expect(third.action).assertEqual('');
      }
    });

    it('ends with the bare settings home want after richer candidates fail', 0, async () => {
      const probe = new StarterProbe();
      probe.succeedOnCall = 5;
      const policy = new AppSettingsLaunchPolicy((w: SettingsLaunchWant): Promise<boolean> => probe.start(w));
      const opened = await policy.openApplicationSettings('settings.host', 'app.target');
      expect(opened).assertTrue();
      expect(probe.calls).assertEqual(5);
      const fourth = probe.wantAt(3);
      expect(fourth === null).assertFalse();
      if (fourth !== null) {
        expect(fourth.action).assertEqual('ohos.settings.application.details');
        expect(`${fourth.parameters !== null ? fourth.parameters['pushParams'] : ''}`).assertEqual('app.target');
      }
      const fifth = probe.wantAt(4);
      expect(fifth === null).assertFalse();
      if (fifth !== null) {
        expect(fifth.bundleName).assertEqual('settings.host');
        expect(fifth.abilityName).assertEqual('');
        expect(fifth.uri).assertEqual('');
        expect(fifth.action).assertEqual('');
      }
    });

    it('treats a throwing starter as declined and keeps trying later candidates', 0, async () => {
      const probe = new StarterProbe();
      probe.throwOnCall = 1;
      probe.succeedOnCall = 2;
      const policy = new AppSettingsLaunchPolicy((w: SettingsLaunchWant): Promise<boolean> => probe.start(w));
      const opened = await policy.openApplicationSettings('settings.host', 'app.target');
      expect(opened).assertTrue();
      expect(probe.calls).assertEqual(2);
    });

    it('reports failure only after all five candidates decline', 0, async () => {
      const probe = new StarterProbe();
      const policy = new AppSettingsLaunchPolicy((w: SettingsLaunchWant): Promise<boolean> => probe.start(w));
      const opened = await policy.openApplicationSettings('settings.host', 'app.target');
      expect(opened).assertFalse();
      expect(probe.calls).assertEqual(5);
    });
  });
}
