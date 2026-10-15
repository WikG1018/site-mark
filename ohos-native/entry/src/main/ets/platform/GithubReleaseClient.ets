import { http } from '@kit.NetworkKit';
import {
  apiAttemptPlan,
  isAllowedApiUrl,
  isAllowedReleasePageUrl,
  looksLikeGithubReleasePage,
  officialReleasePage,
  pageOpenCandidates,
  parseVersion,
  readHarmonyReleases,
  RELEASE_FAILED,
  RELEASE_SOURCE_OFFICIAL,
  RELEASE_SOURCE_MIRROR,
  statusForVersions
} from '../shared/ReleaseCheck';

const BODY_LIMIT: number = 64 * 1024;
const API_ACCEPT: string = 'application/vnd.github+json';
const PAGE_ACCEPT: string = 'text/html';

class FetchedText {
  status: number;
  body: string;
  redirected: boolean;
  truncated: boolean;

  constructor(status: number, body: string, redirected: boolean, truncated: boolean) {
    this.status = status;
    this.body = body;
    this.redirected = redirected;
    this.truncated = truncated;
  }
}

export class HarmonyReleaseOutcome {
  kind: string;
  versionLabel: string;
  tag: string;
  source: string;

  constructor(kind: string, versionLabel: string = '', tag: string = '', source: string = '') {
    this.kind = kind;
    this.versionLabel = versionLabel;
    this.tag = tag;
    this.source = source;
  }

  static failed(): HarmonyReleaseOutcome {
    return new HarmonyReleaseOutcome(RELEASE_FAILED);
  }
}

export async function checkHarmonyRelease(localVersion: string, mode: string): Promise<HarmonyReleaseOutcome> {
  if (parseVersion(localVersion) === null) {
    return HarmonyReleaseOutcome.failed();
  }
  const plan = apiAttemptPlan(mode, true);
  for (let i = 0; i < plan.length; i++) {
    const attempt = plan[i];
    if (!isAllowedApiUrl(attempt.rawUrl)) {
      continue;
    }
    const fetched = await fetchText(attempt.rawUrl, attempt.timeoutMs, API_ACCEPT);
    if (fetched === null || fetched.redirected || fetched.truncated || fetched.status !== 200) {
      continue;
    }
    const read = readHarmonyReleases(fetched.body);
    if (!read.usable) {
      continue;
    }
    const status = statusForVersions(localVersion, read.versionLabel);
    if (status === RELEASE_FAILED) {
      return HarmonyReleaseOutcome.failed();
    }
    return new HarmonyReleaseOutcome(status, read.versionLabel, read.tag, attempt.source);
  }
  return HarmonyReleaseOutcome.failed();
}

export async function resolveHarmonyReleasePage(tag: string, source: string): Promise<string> {
  if (tag.length === 0) {
    return '';
  }
  if (source === RELEASE_SOURCE_OFFICIAL) {
    const page = officialReleasePage(tag);
    return isAllowedReleasePageUrl(page) ? page : '';
  }
  if (source !== RELEASE_SOURCE_MIRROR) {
    return '';
  }
  const candidates = pageOpenCandidates(tag);
  for (let i = 0; i < candidates.length; i++) {
    const raw = candidates[i];
    if (!isAllowedReleasePageUrl(raw)) {
      continue;
    }
    const fetched = await fetchText(raw, 6000, PAGE_ACCEPT);
    if (fetched === null || fetched.redirected || fetched.status !== 200) {
      continue;
    }
    if (looksLikeGithubReleasePage(fetched.status, fetched.body)) {
      return raw;
    }
  }
  return '';
}

async function fetchText(url: string, timeoutMs: number, accept: string): Promise<FetchedText | null> {
  if (!url.startsWith('https://')) {
    return null;
  }
  const client = http.createHttp();
  try {
    const header: Record<string, string> = {
      'User-Agent': 'SiteMark',
      'Accept': accept
    };
    const response = await client.request(url, {
      method: http.RequestMethod.GET,
      header: header,
      connectTimeout: timeoutMs,
      readTimeout: timeoutMs,
      expectDataType: http.HttpDataType.STRING,
      maxLimit: BODY_LIMIT
    });
    const code = response.responseCode;
    if (code >= 300 && code < 400) {
      return new FetchedText(code, '', true, false);
    }
    const body = typeof response.result === 'string' ? response.result as string : '';
    if (body.length > BODY_LIMIT) {
      return new FetchedText(code, '', false, true);
    }
    return new FetchedText(code, body, false, false);
  } catch (_) {
    return null;
  } finally {
    client.destroy();
  }
}
