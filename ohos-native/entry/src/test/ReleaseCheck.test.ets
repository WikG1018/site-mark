import { describe, expect, it } from '@ohos/hypium';
import {
  apiAttemptPlan,
  isAllowedReleasePageUrl,
  looksLikeGithubReleasePage,
  normalizeReleaseCheckMode,
  officialReleasePage,
  pageOpenCandidates,
  readHarmonyReleases,
  RELEASE_FAILED,
  RELEASE_SOURCE_MIRROR,
  RELEASE_SOURCE_OFFICIAL,
  RELEASE_UP_TO_DATE,
  RELEASE_UPDATE,
  ReleasePageOpener,
  statusForVersions
} from '../main/ets/shared/ReleaseCheck';

class RecordingOpener {
  urls: string[] = [];
  calls: number = 0;

  start(url: string): Promise<void> {
    this.calls += 1;
    this.urls.push(url);
    return Promise.resolve();
  }
}

export default function releaseCheckTest(): void {
  describe('ReleaseCheck', () => {
    it('treats 1.0.29 against native-v1.0.29 as up to date and ignores build metadata', 0, () => {
      expect(statusForVersions('1.0.29', '1.0.29')).assertEqual(RELEASE_UP_TO_DATE);
      expect(statusForVersions('1.0.29+9', '1.0.29')).assertEqual(RELEASE_UP_TO_DATE);
      expect(statusForVersions('1.0.30', '1.0.29')).assertEqual(RELEASE_UP_TO_DATE);
    });

    it('treats a higher native tag as an update and a non-numeric local version as failure', 0, () => {
      expect(statusForVersions('1.0.14', '1.0.15')).assertEqual(RELEASE_UPDATE);
      expect(statusForVersions('unknown', '1.0.15')).assertEqual(RELEASE_FAILED);
      expect(statusForVersions('1.0.x', '1.0.15')).assertEqual(RELEASE_FAILED);
    });

    it('skips v1.0.29 and keeps the highest non-draft native-v', 0, () => {
      const body = '[' +
        '{"tag_name":"v1.0.29","draft":false,"prerelease":false},' +
        '{"tag_name":"native-v1.0.10","draft":false,"prerelease":false},' +
        '{"tag_name":"native-v1.0.12","draft":false,"prerelease":false},' +
        '{"tag_name":"native-v1.2.0","draft":true,"prerelease":false},' +
        '{"tag_name":"native-v9.0.0","draft":false,"prerelease":true}' +
        ']';
      const read = readHarmonyReleases(body);
      expect(read.usable).assertTrue();
      expect(read.tag).assertEqual('native-v1.0.12');
      expect(read.versionLabel).assertEqual('1.0.12');
      expect(statusForVersions('1.0.11', read.versionLabel)).assertEqual(RELEASE_UPDATE);
      expect(statusForVersions('1.0.12', read.versionLabel)).assertEqual(RELEASE_UP_TO_DATE);
    });

    it('does not require html_url and rejects HTML or a missing legal tag', 0, () => {
      const read = readHarmonyReleases(
        '[{"tag_name":"native-v1.0.14","draft":false,"prerelease":false}]');
      expect(read.usable).assertTrue();
      expect(read.tag).assertEqual('native-v1.0.14');
      expect(readHarmonyReleases('<html>Loading</html>').usable).assertFalse();
      expect(readHarmonyReleases('{"message":"Not Found"}').usable).assertFalse();
      expect(readHarmonyReleases('[{"tag_name":"v1.0.29","draft":false,"prerelease":false}]').usable)
        .assertFalse();
    });

    it('plans official first, then only gh-proxy.com, unless the user picks another mode', 0, () => {
      const automatic = apiAttemptPlan('auto', true);
      expect(automatic.length).assertEqual(2);
      expect(automatic[0].source).assertEqual(RELEASE_SOURCE_OFFICIAL);
      expect(automatic[0].rawUrl).assertEqual(
        'https://api.github.com/repos/WikG1018/site-mark/releases?per_page=30');
      expect(automatic[0].timeoutMs).assertEqual(4000);
      expect(automatic[1].source).assertEqual(RELEASE_SOURCE_MIRROR);
      expect(automatic[1].rawUrl).assertEqual(
        'https://gh-proxy.com/https://api.github.com/repos/WikG1018/site-mark/releases?per_page=30');
      expect(automatic[1].timeoutMs).assertEqual(6000);
      expect(automatic[0].rawUrl.indexOf('/releases/latest') < 0).assertTrue();
      const official = apiAttemptPlan('official', true);
      expect(official.length).assertEqual(1);
      expect(official[0].source).assertEqual(RELEASE_SOURCE_OFFICIAL);
      const mirror = apiAttemptPlan('mirror', true);
      expect(mirror[0].source).assertEqual(RELEASE_SOURCE_MIRROR);
      expect(mirror[1].source).assertEqual(RELEASE_SOURCE_OFFICIAL);
    });

    it('opens the official page directly and never uses gh-proxy.com for the page', 0, () => {
      expect(officialReleasePage('native-v1.0.14')).assertEqual(
        'https://github.com/WikG1018/site-mark/releases/tag/native-v1.0.14');
      const pages = pageOpenCandidates('native-v1.0.14');
      expect(pages.length).assertEqual(5);
      expect(pages[0]).assertEqual(
        'https://ghproxy.net/https://github.com/WikG1018/site-mark/releases/tag/native-v1.0.14');
      expect(pages[1].indexOf('gh.llkk.cc') >= 0).assertTrue();
      expect(pages[4].indexOf('fastgit.cc') >= 0).assertTrue();
      let usesApiMirror = false;
      for (let i = 0; i < pages.length; i++) {
        if (pages[i].indexOf('gh-proxy.com') >= 0) {
          usesApiMirror = true;
        }
      }
      expect(usesApiMirror).assertFalse();
    });

    it('rejects a release page whose prefix is not on the fixed list', 0, async () => {
      const probe = new RecordingOpener();
      const opener = new ReleasePageOpener((url: string): Promise<void> => probe.start(url));
      const allowed = 'https://github.com/WikG1018/site-mark/releases/tag/native-v1.0.14';
      expect(isAllowedReleasePageUrl(allowed)).assertTrue();
      await opener.open(allowed);
      expect(probe.calls).assertEqual(1);
      expect(probe.urls[0]).assertEqual(allowed);
      let rejected = false;
      try {
        await opener.open(
          'https://gh-proxy.com/https://github.com/WikG1018/site-mark/releases/tag/native-v1.0.14');
      } catch (_) {
        rejected = true;
      }
      expect(rejected).assertTrue();
      expect(probe.calls).assertEqual(1);
      expect(isAllowedReleasePageUrl('https://evil.example/releases/tag/v1.0.29')).assertFalse();
      expect(isAllowedReleasePageUrl(
        'https://ghproxy.net/https://github.com/WikG1018/site-mark/releases/tag/native-v1.0.14')).assertTrue();
    });

    it('treats unreadable mode text as automatic and does not accept an HTML landing page', 0, () => {
      expect(normalizeReleaseCheckMode(null)).assertEqual('auto');
      expect(normalizeReleaseCheckMode('nope')).assertEqual('auto');
      expect(normalizeReleaseCheckMode(' official ')).assertEqual('official');
      expect(normalizeReleaseCheckMode('mirror')).assertEqual('mirror');
      expect(looksLikeGithubReleasePage(200, '<html>Loading</html>')).assertFalse();
      expect(looksLikeGithubReleasePage(200, '{"tag_name":"native-v1.0.14"}')).assertFalse();
      expect(looksLikeGithubReleasePage(200,
        '<!DOCTYPE html><html>WikG1018/site-mark releases/tag</html>')).assertTrue();
    });
  });
}
