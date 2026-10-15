const OFFICIAL_API = 'https://api.github.com';
const REPO = 'WikG1018/site-mark';
const RELEASE_TAG_PREFIX = `https://github.com/${REPO}/releases/tag/`;
const API_MIRROR_PREFIX = 'https://gh-proxy.com';
const PAGE_MIRROR_PREFIXES: string[] = [
  'https://ghproxy.net',
  'https://gh.llkk.cc',
  'https://ghfast.top',
  'https://g.blfrp.cn',
  'https://fastgit.cc'
];

const FLUTTER_TAG: RegExp = /^v(\d+)\.(\d+)\.(\d+)$/;
const NATIVE_TAG: RegExp = /^native-v(\d+)\.(\d+)\.(\d+)$/;
const PAGE_TAG: RegExp = /^(v|native-v)\d+\.\d+\.\d+$/;
const NUMERIC: RegExp = /^(\d+)\.(\d+)\.(\d+)$/;

export const RELEASE_UP_TO_DATE: string = 'up_to_date';
export const RELEASE_UPDATE: string = 'update';
export const RELEASE_FAILED: string = 'failed';
export const RELEASE_SOURCE_OFFICIAL: string = 'official';
export const RELEASE_SOURCE_MIRROR: string = 'apiMirror';

export class ReleaseVersion {
  major: number;
  minor: number;
  patch: number;

  constructor(major: number, minor: number, patch: number) {
    this.major = major;
    this.minor = minor;
    this.patch = patch;
  }

  label(): string {
    return `${this.major}.${this.minor}.${this.patch}`;
  }
}

export class ReleaseRead {
  usable: boolean;
  tag: string;
  versionLabel: string;

  constructor(usable: boolean, tag: string = '', versionLabel: string = '') {
    this.usable = usable;
    this.tag = tag;
    this.versionLabel = versionLabel;
  }

  static unusable(): ReleaseRead {
    return new ReleaseRead(false);
  }
}

export class ReleaseAttempt {
  rawUrl: string;
  timeoutMs: number;
  source: string;

  constructor(rawUrl: string, timeoutMs: number, source: string) {
    this.rawUrl = rawUrl;
    this.timeoutMs = timeoutMs;
    this.source = source;
  }
}

export function officialApiUrl(harmony: boolean): string {
  if (harmony) {
    return `${OFFICIAL_API}/repos/${REPO}/releases?per_page=30`;
  }
  return `${OFFICIAL_API}/repos/${REPO}/releases/latest`;
}

export function mirroredApiUrl(harmony: boolean): string {
  return `${API_MIRROR_PREFIX}/${officialApiUrl(harmony)}`;
}

export function apiAttemptPlan(mode: string, harmony: boolean): ReleaseAttempt[] {
  const official = new ReleaseAttempt(officialApiUrl(harmony), 4000, RELEASE_SOURCE_OFFICIAL);
  const mirror = new ReleaseAttempt(mirroredApiUrl(harmony), 6000, RELEASE_SOURCE_MIRROR);
  const normalized = normalizeReleaseCheckMode(mode);
  if (normalized === 'official') {
    return [official];
  }
  if (normalized === 'mirror') {
    return [mirror, official];
  }
  return [official, mirror];
}

export function isAllowedApiUrl(rawUrl: string): boolean {
  return rawUrl === officialApiUrl(false) || rawUrl === officialApiUrl(true) ||
    rawUrl === mirroredApiUrl(false) || rawUrl === mirroredApiUrl(true);
}

export function stripBuildMetadata(version: string): string {
  const plus = version.indexOf('+');
  const bare = plus >= 0 ? version.substring(0, plus) : version;
  return bare.trim();
}

export function parseVersion(raw: string): ReleaseVersion | null {
  let value = stripBuildMetadata(raw);
  if (value.startsWith('native-v')) {
    value = value.substring('native-v'.length);
  } else if (value.startsWith('v')) {
    value = value.substring(1);
  }
  const match = value.match(NUMERIC);
  if (match === null || match[1] === undefined || match[2] === undefined || match[3] === undefined) {
    return null;
  }
  return new ReleaseVersion(Number(match[1]), Number(match[2]), Number(match[3]));
}

export function statusForVersions(local: string, remote: string): string {
  const left = parseVersion(local);
  const right = parseVersion(remote);
  if (left === null || right === null) {
    return RELEASE_FAILED;
  }
  if (left.major !== right.major) {
    return right.major > left.major ? RELEASE_UPDATE : RELEASE_UP_TO_DATE;
  }
  if (left.minor !== right.minor) {
    return right.minor > left.minor ? RELEASE_UPDATE : RELEASE_UP_TO_DATE;
  }
  if (left.patch !== right.patch) {
    return right.patch > left.patch ? RELEASE_UPDATE : RELEASE_UP_TO_DATE;
  }
  return RELEASE_UP_TO_DATE;
}

export function readHarmonyReleases(body: string): ReleaseRead {
  let parsed: Object;
  try {
    parsed = JSON.parse(body) as Object;
  } catch (_) {
    return ReleaseRead.unusable();
  }
  if (!Array.isArray(parsed)) {
    return ReleaseRead.unusable();
  }
  const items = parsed as Object[];
  let best: ReleaseVersion | null = null;
  let bestTag = '';
  for (let i = 0; i < items.length; i++) {
    const record = asRecord(items[i]);
    if (record === null) {
      continue;
    }
    if (record['draft'] === true || record['prerelease'] === true) {
      continue;
    }
    const tag = record['tag_name'];
    if (typeof tag !== 'string') {
      continue;
    }
    const match = tag.match(NATIVE_TAG);
    if (match === null || match[1] === undefined || match[2] === undefined || match[3] === undefined) {
      continue;
    }
    const version = new ReleaseVersion(Number(match[1]), Number(match[2]), Number(match[3]));
    if (best === null || isNewer(version, best)) {
      best = version;
      bestTag = tag;
    }
  }
  if (best === null || bestTag.length === 0) {
    return ReleaseRead.unusable();
  }
  return new ReleaseRead(true, bestTag, best.label());
}

export function officialReleasePage(tag: string): string {
  return `${RELEASE_TAG_PREFIX}${tag}`;
}

export function pageOpenCandidates(tag: string): string[] {
  const pages: string[] = [];
  for (let i = 0; i < PAGE_MIRROR_PREFIXES.length; i++) {
    pages.push(`${PAGE_MIRROR_PREFIXES[i]}/${officialReleasePage(tag)}`);
  }
  return pages;
}

export function isAllowedReleasePageUrl(url: string): boolean {
  const tag = tagAfterAllowedPrefix(url);
  return tag !== null && PAGE_TAG.test(tag);
}

export function looksLikeGithubReleasePage(statusCode: number, body: string): boolean {
  if (statusCode !== 200) {
    return false;
  }
  const trimmed = body.trim();
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    return false;
  }
  const lower = body.toLowerCase();
  const html = lower.includes('<html') || lower.includes('<!doctype html');
  if (!html) {
    return false;
  }
  return lower.includes('site-mark') || lower.includes('releases/tag') || lower.includes('wikg1018');
}

export function normalizeReleaseCheckMode(raw: string | null): string {
  const value = raw === null ? '' : raw.trim().toLowerCase();
  if (value === 'official' || value === 'mirror') {
    return value;
  }
  return 'auto';
}

export type ReleasePageStarter = (url: string) => Promise<void>;

export class ReleasePageOpener {
  private readonly start: ReleasePageStarter;

  constructor(start: ReleasePageStarter) {
    this.start = start;
  }

  async open(url: string): Promise<void> {
    if (!isAllowedReleasePageUrl(url)) {
      throw new Error('rejected_release_url');
    }
    await this.start(url);
  }
}

function asRecord(value: Object): Record<string, Object> | null {
  if (value === null || Array.isArray(value)) {
    return null;
  }
  return value as Record<string, Object>;
}

function isNewer(candidate: ReleaseVersion, current: ReleaseVersion): boolean {
  if (candidate.major !== current.major) {
    return candidate.major > current.major;
  }
  if (candidate.minor !== current.minor) {
    return candidate.minor > current.minor;
  }
  return candidate.patch > current.patch;
}

function tagAfterAllowedPrefix(url: string): string | null {
  if (url.startsWith(RELEASE_TAG_PREFIX)) {
    const tag = url.substring(RELEASE_TAG_PREFIX.length);
    return tag.length === 0 ? null : tag;
  }
  for (let i = 0; i < PAGE_MIRROR_PREFIXES.length; i++) {
    const marker = `${PAGE_MIRROR_PREFIXES[i]}/${RELEASE_TAG_PREFIX}`;
    if (url.startsWith(marker)) {
      const tag = url.substring(marker.length);
      return tag.length === 0 ? null : tag;
    }
  }
  return null;
}
