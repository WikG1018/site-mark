/// Pure release-check rules. No Flutter, no HTTP, no I/O.
///
/// The About page is the only caller, and only after a tap. Release-page and
/// APK links are built locally from a validated tag. Download assets require
/// a fixed variant, bounded size and SHA-256; see the platform installer too.
library;

import 'dart:convert';

enum ReleaseCheckMode { auto, official, mirror }

enum ReleaseProduct { flutter, harmony }

enum ReleaseSource { official, apiMirror }

enum ReleaseCheckStatus { upToDate, updateAvailable, failed }

enum ReleaseApkVariant { arm64, universal }

/// Only the two APK variants published by our release workflow are accepted.
/// URLs are constructed locally, never taken from a remote response.
class ReleaseDownload {
  const ReleaseDownload({
    required this.tag,
    required this.variant,
    required this.sizeBytes,
    required this.sha256,
  });

  final String tag;
  final ReleaseApkVariant variant;
  final int sizeBytes;
  final String sha256;

  String get fileName => 'sitemark-$tag-${variant.name}.apk';
  Uri get officialUri =>
      Uri.parse('$officialReleaseOrigin/releases/download/$tag/$fileName');
}

const releaseCheckUserAgent = 'SiteMark';
const releaseCheckAccept = 'application/vnd.github+json';
const releasePageAccept = 'text/html';
const releaseCheckBodyLimit = 64 * 1024;
const officialApiTimeout = Duration(seconds: 4);
const mirrorTimeout = Duration(seconds: 6);

const releaseRepoPath = 'WikG1018/site-mark';
const officialApiOrigin = 'https://api.github.com';
const officialReleaseOrigin = 'https://github.com/WikG1018/site-mark';
const releaseTagPrefix = '$officialReleaseOrigin/releases/tag/';

/// The only API mirror. Other prefixes returned HTML, 403, 429, or TLS errors.
const apiMirrorPrefix = 'https://gh-proxy.com';

/// Page mirrors that return GitHub HTML. gh-proxy.com is not in this list:
/// it answers 403 for the release page.
const pageMirrorPrefixes = <String>[
  'https://ghproxy.net',
  'https://gh.llkk.cc',
  'https://ghfast.top',
  'https://g.blfrp.cn',
  'https://fastgit.cc',
];

const _modeAuto = 'auto';
const _modeOfficial = 'official';
const _modeMirror = 'mirror';

final _numericVersion = RegExp(r'^(\d+)\.(\d+)\.(\d+)$');
final _flutterTag = RegExp(r'^v(\d+)\.(\d+)\.(\d+)$');
final _nativeTag = RegExp(r'^native-v(\d+)\.(\d+)\.(\d+)$');
final _pageTag = RegExp(r'^(?:v|native-v)\d+\.\d+\.\d+$');

class ReleaseVersion {
  const ReleaseVersion(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  String get label => '$major.$minor.$patch';
}

class ReleaseCheckOutcome {
  const ReleaseCheckOutcome({
    required this.status,
    this.versionLabel,
    this.tag,
    this.source,
    this.downloads = const [],
  });

  const ReleaseCheckOutcome.failed()
    : status = ReleaseCheckStatus.failed,
      versionLabel = null,
      tag = null,
      source = null,
      downloads = const [];

  final ReleaseCheckStatus status;
  final String? versionLabel;
  final String? tag;
  final ReleaseSource? source;
  final List<ReleaseDownload> downloads;

  bool get hasUpdate => status == ReleaseCheckStatus.updateAvailable;

  /// Flutter split APKs use ABI offsets. Never offer the universal APK to an
  /// installed arm64 split: its lower versionCode would reject an upgrade.
  ReleaseDownload? downloadForBuild(String buildNumber) {
    if (!hasUpdate) return null;
    final code = int.tryParse(buildNumber);
    final variant = switch (code) {
      final int code when code > 0 && code < 1000 =>
        ReleaseApkVariant.universal,
      final int code when code >= 2000 && code < 3000 =>
        ReleaseApkVariant.arm64,
      _ => null,
    };
    if (variant == null) return null;
    for (final asset in downloads) {
      if (asset.variant == variant && asset.tag == tag) return asset;
    }
    return null;
  }
}

class ReleaseAttempt {
  const ReleaseAttempt({
    required this.rawUrl,
    required this.timeout,
    required this.source,
  });

  final String rawUrl;
  final Duration timeout;
  final ReleaseSource source;

  Uri get uri => Uri.parse(rawUrl);
}

class ReleaseRead {
  const ReleaseRead.unusable()
    : tag = null,
      versionLabel = null,
      downloads = const [];

  const ReleaseRead.ok({
    required this.tag,
    required this.versionLabel,
    this.downloads = const [],
  });

  final String? tag;
  final String? versionLabel;
  final List<ReleaseDownload> downloads;

  bool get usable => tag != null && versionLabel != null;
}

/// Headers sent to every check. No Cookie, Authorization, or body.
Map<String, String> releaseApiHeaders() => const {
  HttpHeader.userAgent: releaseCheckUserAgent,
  HttpHeader.accept: releaseCheckAccept,
};

class HttpHeader {
  static const userAgent = 'User-Agent';
  static const accept = 'Accept';
  static const cookie = 'Cookie';
  static const authorization = 'Authorization';
}

String officialApiUrl(ReleaseProduct product) => switch (product) {
  ReleaseProduct.flutter =>
    '$officialApiOrigin/repos/$releaseRepoPath/releases/latest',
  ReleaseProduct.harmony =>
    '$officialApiOrigin/repos/$releaseRepoPath/releases?per_page=30',
};

String mirroredApiUrl(ReleaseProduct product) =>
    '$apiMirrorPrefix/${officialApiUrl(product)}';

List<ReleaseAttempt> apiAttemptPlan(
  ReleaseCheckMode mode,
  ReleaseProduct product,
) {
  final official = ReleaseAttempt(
    rawUrl: officialApiUrl(product),
    timeout: officialApiTimeout,
    source: ReleaseSource.official,
  );
  final mirror = ReleaseAttempt(
    rawUrl: mirroredApiUrl(product),
    timeout: mirrorTimeout,
    source: ReleaseSource.apiMirror,
  );
  return switch (mode) {
    ReleaseCheckMode.official => [official],
    ReleaseCheckMode.mirror => [mirror, official],
    ReleaseCheckMode.auto => [official, mirror],
  };
}

bool isAllowedApiUrl(String rawUrl) {
  return rawUrl == officialApiUrl(ReleaseProduct.flutter) ||
      rawUrl == officialApiUrl(ReleaseProduct.harmony) ||
      rawUrl == mirroredApiUrl(ReleaseProduct.flutter) ||
      rawUrl == mirroredApiUrl(ReleaseProduct.harmony);
}

String stripBuildMetadata(String version) {
  final plus = version.indexOf('+');
  final bare = plus >= 0 ? version.substring(0, plus) : version;
  return bare.trim();
}

ReleaseVersion? parseVersion(String raw) {
  var value = stripBuildMetadata(raw);
  if (value.startsWith('native-v')) {
    value = value.substring('native-v'.length);
  } else if (value.startsWith('v')) {
    value = value.substring(1);
  }
  final match = _numericVersion.firstMatch(value);
  if (match == null) return null;
  return ReleaseVersion(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
}

/// Positive when [remote] is newer. Null when either side is not numeric.
int? compareReleaseVersions(String local, String remote) {
  final left = parseVersion(local);
  final right = parseVersion(remote);
  if (left == null || right == null) return null;
  if (left.major != right.major) return right.major - left.major;
  if (left.minor != right.minor) return right.minor - left.minor;
  return right.patch - left.patch;
}

ReleaseCheckStatus statusForVersions(String local, String remote) {
  final delta = compareReleaseVersions(local, remote);
  if (delta == null) return ReleaseCheckStatus.failed;
  if (delta > 0) return ReleaseCheckStatus.updateAvailable;
  return ReleaseCheckStatus.upToDate;
}

ReleaseRead readFlutterLatest(String body) {
  final json = _decodeObject(body);
  if (json == null) return const ReleaseRead.unusable();
  if (json['draft'] == true || json['prerelease'] == true) {
    return const ReleaseRead.unusable();
  }
  final tag = json['tag_name'];
  if (tag is! String) return const ReleaseRead.unusable();
  final match = _flutterTag.firstMatch(tag);
  if (match == null) return const ReleaseRead.unusable();
  return ReleaseRead.ok(
    tag: tag,
    versionLabel: '${match.group(1)}.${match.group(2)}.${match.group(3)}',
    downloads: _readDownloads(json['assets'], tag),
  );
}

List<ReleaseDownload> _readDownloads(Object? value, String tag) {
  if (value is! List) return const [];
  final assets = <ReleaseApkVariant, ReleaseDownload>{};
  for (final item in value) {
    if (item is! Map || item['state'] != 'uploaded') continue;
    final size = item['size'];
    final digest = item['digest'];
    if (size is! int || size <= 0 || size > 200 * 1024 * 1024) continue;
    if (digest is! String ||
        !RegExp(r'^sha256:[0-9a-fA-F]{64}$').hasMatch(digest)) {
      continue;
    }
    for (final variant in ReleaseApkVariant.values) {
      if (item['name'] == 'sitemark-$tag-${variant.name}.apk') {
        assets[variant] = ReleaseDownload(
          tag: tag,
          variant: variant,
          sizeBytes: size,
          sha256: digest.substring(7).toLowerCase(),
        );
      }
    }
  }
  return List.unmodifiable(assets.values);
}

ReleaseRead readHarmonyReleases(String body) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    return const ReleaseRead.unusable();
  }
  if (decoded is! List<dynamic>) return const ReleaseRead.unusable();
  ReleaseVersion? best;
  String? bestTag;
  for (final item in decoded) {
    if (item is! Map) continue;
    final json = Map<String, dynamic>.from(item);
    if (json['draft'] == true || json['prerelease'] == true) continue;
    final tag = json['tag_name'];
    if (tag is! String) continue;
    final match = _nativeTag.firstMatch(tag);
    if (match == null) continue;
    final version = ReleaseVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
    if (best == null || _isNewer(version, best)) {
      best = version;
      bestTag = tag;
    }
  }
  if (best == null || bestTag == null) return const ReleaseRead.unusable();
  return ReleaseRead.ok(tag: bestTag, versionLabel: best.label);
}

ReleaseRead readReleaseBody(String body, ReleaseProduct product) {
  return switch (product) {
    ReleaseProduct.flutter => readFlutterLatest(body),
    ReleaseProduct.harmony => readHarmonyReleases(body),
  };
}

ReleaseCheckOutcome outcomeFromRead({
  required String localVersion,
  required ReleaseRead read,
  required ReleaseSource source,
}) {
  if (!read.usable) return const ReleaseCheckOutcome.failed();
  final status = statusForVersions(localVersion, read.versionLabel!);
  if (status == ReleaseCheckStatus.failed) {
    return const ReleaseCheckOutcome.failed();
  }
  return ReleaseCheckOutcome(
    status: status,
    versionLabel: read.versionLabel,
    tag: read.tag,
    source: source,
    downloads: read.downloads,
  );
}

String officialReleasePage(String tag) => '$releaseTagPrefix$tag';

String mirroredReleasePage(String prefix, String tag) =>
    '$prefix/${officialReleasePage(tag)}';

List<String> pageOpenCandidates(String tag) {
  return [
    for (final prefix in pageMirrorPrefixes) mirroredReleasePage(prefix, tag),
  ];
}

bool isAllowedReleasePageUrl(String url) {
  final tag = _tagAfterAllowedPrefix(url);
  return tag != null && _pageTag.hasMatch(tag);
}

bool looksLikeGithubReleasePage(int statusCode, String body) {
  if (statusCode != 200) return false;
  final trimmed = body.trimLeft();
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) return false;
  final lower = body.toLowerCase();
  final html = lower.contains('<html') || lower.contains('<!doctype html');
  if (!html) return false;
  return lower.contains('site-mark') ||
      lower.contains('releases/tag') ||
      lower.contains('wikg1018');
}

ReleaseCheckMode parseReleaseCheckMode(String? raw) {
  final value = raw?.trim().toLowerCase();
  return switch (value) {
    _modeOfficial => ReleaseCheckMode.official,
    _modeMirror => ReleaseCheckMode.mirror,
    _ => ReleaseCheckMode.auto,
  };
}

String serializeReleaseCheckMode(ReleaseCheckMode mode) => switch (mode) {
  ReleaseCheckMode.official => _modeOfficial,
  ReleaseCheckMode.mirror => _modeMirror,
  ReleaseCheckMode.auto => _modeAuto,
};

Map<String, dynamic>? _decodeObject(String body) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  return Map<String, dynamic>.from(decoded);
}

bool _isNewer(ReleaseVersion candidate, ReleaseVersion current) {
  if (candidate.major != current.major) {
    return candidate.major > current.major;
  }
  if (candidate.minor != current.minor) {
    return candidate.minor > current.minor;
  }
  return candidate.patch > current.patch;
}

String? _tagAfterAllowedPrefix(String url) {
  if (url.startsWith(releaseTagPrefix)) {
    final tag = url.substring(releaseTagPrefix.length);
    return tag.isEmpty ? null : tag;
  }
  for (final prefix in pageMirrorPrefixes) {
    final marker = '$prefix/$releaseTagPrefix';
    if (url.startsWith(marker)) {
      final tag = url.substring(marker.length);
      return tag.isEmpty ? null : tag;
    }
  }
  return null;
}
