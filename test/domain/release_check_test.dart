import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/domain/release_check.dart';
import 'package:sitemark/platform/github_release_client.dart';
import 'package:sitemark/platform/release_check_mode_store.dart';

void main() {
  const current = '1.0.29';
  const latestJson = '''
{"tag_name":"v1.0.29","draft":false,"prerelease":false}
''';
  const newerJson = '''
{"tag_name":"v1.0.30","draft":false,"prerelease":false,"html_url":"https://evil.example/phish"}
''';

  test('1.0.29 against v1.0.29 is up to date', () {
    final read = readFlutterLatest(latestJson);
    final outcome = outcomeFromRead(
      localVersion: current,
      read: read,
      source: ReleaseSource.official,
    );
    expect(outcome.status, ReleaseCheckStatus.upToDate);
    expect(outcome.versionLabel, '1.0.29');
  });

  test('1.0.29 against v1.0.30 is an update and ignores html_url', () {
    final read = readFlutterLatest(newerJson);
    final outcome = outcomeFromRead(
      localVersion: current,
      read: read,
      source: ReleaseSource.official,
    );
    expect(outcome.status, ReleaseCheckStatus.updateAvailable);
    expect(outcome.versionLabel, '1.0.30');
    expect(outcome.tag, 'v1.0.30');
    expect(
      officialReleasePage(outcome.tag!),
      'https://github.com/WikG1018/site-mark/releases/tag/v1.0.30',
    );
    expect(officialReleasePage(outcome.tag!), isNot(contains('evil.example')));
  });

  test('local 1.0.30 against remote 1.0.29 is up to date', () {
    final outcome = outcomeFromRead(
      localVersion: '1.0.30',
      read: readFlutterLatest(latestJson),
      source: ReleaseSource.official,
    );
    expect(outcome.status, ReleaseCheckStatus.upToDate);
  });

  test('build metadata is ignored when comparing', () {
    expect(
      statusForVersions('1.0.29+44', '1.0.29'),
      ReleaseCheckStatus.upToDate,
    );
    expect(
      statusForVersions('1.0.29+44', '1.0.30'),
      ReleaseCheckStatus.updateAvailable,
    );
  });

  test('non-numeric tags, drafts, and prereleases are failures', () {
    expect(
      readFlutterLatest(
        '{"tag_name":"v1.0.x","draft":false,"prerelease":false}',
      ).usable,
      isFalse,
    );
    expect(
      readFlutterLatest(
        '{"tag_name":"1.0.30","draft":false,"prerelease":false}',
      ).usable,
      isFalse,
    );
    expect(
      readFlutterLatest(
        '{"tag_name":"v1.0.30","draft":true,"prerelease":false}',
      ).usable,
      isFalse,
    );
    expect(
      readFlutterLatest(
        '{"tag_name":"v1.0.30","draft":false,"prerelease":true}',
      ).usable,
      isFalse,
    );
    expect(
      statusForVersions('not-a-version', '1.0.30'),
      ReleaseCheckStatus.failed,
    );
  });

  test('missing html_url is not a failure when tag_name is valid', () {
    final read = readFlutterLatest(
      '{"tag_name":"v1.0.30","draft":false,"prerelease":false}',
    );
    expect(read.usable, isTrue);
    expect(read.tag, 'v1.0.30');
  });

  test('HTML and JSON without a legal tag fail that source', () {
    expect(readFlutterLatest('<html>Loading</html>').usable, isFalse);
    expect(readFlutterLatest('{"message":"Not Found"}').usable, isFalse);
    expect(readHarmonyReleases('<html>landing</html>').usable, isFalse);
  });

  test('harmony list skips v1.0.29 and keeps the highest native-v', () {
    const body = '''
[
  {"tag_name":"v1.0.29","draft":false,"prerelease":false},
  {"tag_name":"native-v1.0.10","draft":false,"prerelease":false},
  {"tag_name":"native-v1.0.12","draft":false,"prerelease":false},
  {"tag_name":"native-v1.2.0","draft":true,"prerelease":false},
  {"tag_name":"native-v9.0.0","draft":false,"prerelease":true},
  {"tag_name":"not-a-tag","draft":false,"prerelease":false}
]
''';
    final read = readHarmonyReleases(body);
    expect(read.tag, 'native-v1.0.12');
    expect(read.versionLabel, '1.0.12');
    final outcome = outcomeFromRead(
      localVersion: '1.0.11',
      read: read,
      source: ReleaseSource.official,
    );
    expect(outcome.status, ReleaseCheckStatus.updateAvailable);
    expect(
      outcomeFromRead(
        localVersion: '1.0.12',
        read: read,
        source: ReleaseSource.official,
      ).status,
      ReleaseCheckStatus.upToDate,
    );
    expect(
      outcomeFromRead(
        localVersion: '1.0.13+2',
        read: read,
        source: ReleaseSource.official,
      ).status,
      ReleaseCheckStatus.upToDate,
    );
  });

  test('automatic tries official then only gh-proxy.com', () {
    final plan = apiAttemptPlan(ReleaseCheckMode.auto, ReleaseProduct.flutter);
    expect(plan.map((attempt) => attempt.rawUrl).toList(), [
      'https://api.github.com/repos/WikG1018/site-mark/releases/latest',
      'https://gh-proxy.com/https://api.github.com/repos/WikG1018/site-mark/releases/latest',
    ]);
    expect(plan.first.timeout, officialApiTimeout);
    expect(plan.last.timeout, mirrorTimeout);
    expect(plan.last.source, ReleaseSource.apiMirror);
    expect(
      plan.any((attempt) => attempt.rawUrl.contains('ghproxy.net')),
      isFalse,
    );
  });

  test('official-only does not include a mirror', () {
    final plan = apiAttemptPlan(
      ReleaseCheckMode.official,
      ReleaseProduct.harmony,
    );
    expect(plan, hasLength(1));
    expect(
      plan.single.rawUrl,
      'https://api.github.com/repos/WikG1018/site-mark/releases?per_page=30',
    );
  });

  test('mirror-first tries gh-proxy.com then official', () {
    final plan = apiAttemptPlan(
      ReleaseCheckMode.mirror,
      ReleaseProduct.flutter,
    );
    expect(plan.first.source, ReleaseSource.apiMirror);
    expect(plan.last.source, ReleaseSource.official);
    expect(
      plan.first.rawUrl,
      'https://gh-proxy.com/https://api.github.com/repos/WikG1018/site-mark/releases/latest',
    );
  });

  test('harmony mirror URL keeps the releases query on the inner API path', () {
    expect(
      mirroredApiUrl(ReleaseProduct.harmony),
      'https://gh-proxy.com/https://api.github.com/repos/WikG1018/site-mark/releases?per_page=30',
    );
  });

  test('page open list excludes gh-proxy.com and keeps the fixed order', () {
    final pages = pageOpenCandidates('v1.0.29');
    expect(pages, [
      'https://ghproxy.net/https://github.com/WikG1018/site-mark/releases/tag/v1.0.29',
      'https://gh.llkk.cc/https://github.com/WikG1018/site-mark/releases/tag/v1.0.29',
      'https://ghfast.top/https://github.com/WikG1018/site-mark/releases/tag/v1.0.29',
      'https://g.blfrp.cn/https://github.com/WikG1018/site-mark/releases/tag/v1.0.29',
      'https://fastgit.cc/https://github.com/WikG1018/site-mark/releases/tag/v1.0.29',
    ]);
    expect(pages.any((url) => url.contains('gh-proxy.com')), isFalse);
  });

  test('release page prefix rejects unknown hosts and gh-proxy.com', () {
    expect(
      isAllowedReleasePageUrl(
        'https://github.com/WikG1018/site-mark/releases/tag/v1.0.29',
      ),
      isTrue,
    );
    expect(
      isAllowedReleasePageUrl(
        'https://ghproxy.net/https://github.com/WikG1018/site-mark/releases/tag/native-v1.0.14',
      ),
      isTrue,
    );
    expect(
      isAllowedReleasePageUrl(
        'https://gh-proxy.com/https://github.com/WikG1018/site-mark/releases/tag/v1.0.29',
      ),
      isFalse,
    );
    expect(
      isAllowedReleasePageUrl('https://evil.example/releases/tag/v1.0.29'),
      isFalse,
    );
    expect(
      isAllowedReleasePageUrl(
        'http://github.com/WikG1018/site-mark/releases/tag/v1.0.29',
      ),
      isFalse,
    );
    expect(
      isAllowedReleasePageUrl(
        'https://github.com/WikG1018/site-mark/releases/tag/v1.0.29?x=1',
      ),
      isFalse,
    );
  });

  test(
    'API headers name SiteMark and do not carry Cookie or Authorization',
    () {
      final headers = releaseApiHeaders();
      expect(headers['User-Agent'], 'SiteMark');
      expect(headers['Accept'], 'application/vnd.github+json');
      expect(headers.containsKey('Cookie'), isFalse);
      expect(headers.containsKey('Authorization'), isFalse);
    },
  );

  test('unreadable mode text is automatic', () {
    expect(parseReleaseCheckMode(null), ReleaseCheckMode.auto);
    expect(parseReleaseCheckMode(''), ReleaseCheckMode.auto);
    expect(parseReleaseCheckMode('nope'), ReleaseCheckMode.auto);
    expect(parseReleaseCheckMode(' official '), ReleaseCheckMode.official);
    expect(parseReleaseCheckMode('mirror'), ReleaseCheckMode.mirror);
    expect(serializeReleaseCheckMode(ReleaseCheckMode.auto), 'auto');
  });

  test('HTML landing page is not a GitHub release page', () {
    expect(looksLikeGithubReleasePage(200, '<html>Loading</html>'), isFalse);
    expect(looksLikeGithubReleasePage(200, '{"tag_name":"v1.0.29"}'), isFalse);
    expect(looksLikeGithubReleasePage(403, '<html>site-mark</html>'), isFalse);
    expect(
      looksLikeGithubReleasePage(
        200,
        '<!DOCTYPE html><html><title>site-mark releases/tag</title></html>',
      ),
      isTrue,
    );
  });

  test(
    'client skips a failed official source and does not claim up to date',
    () async {
      final calls = <String>[];
      final client = GithubReleaseClient(
        fetcher: (uri, {required timeout, required accept}) async {
          calls.add(uri.toString());
          if (uri.host == 'api.github.com') {
            return const ReleaseFetch(
              statusCode: 200,
              body: '<html>Loading</html>',
            );
          }
          return const ReleaseFetch(
            statusCode: 200,
            body: '{"tag_name":"v1.0.30","draft":false,"prerelease":false}',
          );
        },
      );
      final outcome = await client.check(
        localVersion: '1.0.29',
        mode: ReleaseCheckMode.auto,
      );
      expect(outcome.status, ReleaseCheckStatus.updateAvailable);
      expect(outcome.source, ReleaseSource.apiMirror);
      expect(calls, [
        'https://api.github.com/repos/WikG1018/site-mark/releases/latest',
        'https://gh-proxy.com/https://api.github.com/repos/WikG1018/site-mark/releases/latest',
      ]);
    },
  );

  test('official-only client does not call the mirror', () async {
    final calls = <String>[];
    final client = GithubReleaseClient(
      fetcher: (uri, {required timeout, required accept}) async {
        calls.add(uri.host);
        return const ReleaseFetch(statusCode: 500, body: '');
      },
    );
    final outcome = await client.check(
      localVersion: '1.0.29',
      mode: ReleaseCheckMode.official,
    );
    expect(outcome.status, ReleaseCheckStatus.failed);
    expect(calls, ['api.github.com']);
  });

  test(
    'redirect and thrown transport errors continue, then fail closed',
    () async {
      final client = GithubReleaseClient(
        fetcher: (uri, {required timeout, required accept}) async {
          if (uri.host == 'api.github.com') {
            return const ReleaseFetch(
              statusCode: 302,
              body: '',
              redirected: true,
            );
          }
          throw const SocketException('down');
        },
      );
      final outcome = await client.check(
        localVersion: '1.0.29',
        mode: ReleaseCheckMode.auto,
      );
      expect(outcome.status, ReleaseCheckStatus.failed);
      expect(outcome.status, isNot(ReleaseCheckStatus.upToDate));
    },
  );

  test(
    'official success opens the GitHub page without probing mirrors',
    () async {
      var fetches = 0;
      final client = GithubReleaseClient(
        fetcher: (uri, {required timeout, required accept}) async {
          fetches += 1;
          return const ReleaseFetch(statusCode: 500, body: '');
        },
      );
      final page = await client.resolveReleasePage(
        const ReleaseCheckOutcome(
          status: ReleaseCheckStatus.updateAvailable,
          versionLabel: '1.0.30',
          tag: 'v1.0.30',
          source: ReleaseSource.official,
        ),
      );
      expect(fetches, 0);
      expect(
        page,
        Uri.parse('https://github.com/WikG1018/site-mark/releases/tag/v1.0.30'),
      );
    },
  );

  test(
    'mirror success opens the first page mirror that returns GitHub HTML',
    () async {
      final calls = <String>[];
      final client = GithubReleaseClient(
        fetcher: (uri, {required timeout, required accept}) async {
          calls.add(uri.toString());
          if (uri.host == 'ghproxy.net') {
            return const ReleaseFetch(statusCode: 403, body: '');
          }
          return const ReleaseFetch(
            statusCode: 200,
            body: '<html><body>WikG1018/site-mark releases/tag</body></html>',
          );
        },
      );
      final page = await client.resolveReleasePage(
        const ReleaseCheckOutcome(
          status: ReleaseCheckStatus.updateAvailable,
          versionLabel: '1.0.30',
          tag: 'v1.0.30',
          source: ReleaseSource.apiMirror,
        ),
      );
      expect(calls.first, contains('ghproxy.net'));
      expect(calls.any((url) => url.contains('gh-proxy.com')), isFalse);
      expect(
        page,
        Uri.parse(
          'https://gh.llkk.cc/https://github.com/WikG1018/site-mark/releases/tag/v1.0.30',
        ),
      );
    },
  );

  test('mode file round-trips and a missing file is automatic', () async {
    final dir = await Directory.systemTemp.createTemp('sitemark-release-mode');
    try {
      final store = FileReleaseCheckModeStore(directory: () async => dir);
      expect(await store.read(), ReleaseCheckMode.auto);
      await store.write(ReleaseCheckMode.mirror);
      expect(await store.read(), ReleaseCheckMode.mirror);
      expect(
        await File(
          '${dir.path}${Platform.pathSeparator}$releaseCheckModeFileName',
        ).readAsString(),
        'mirror',
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
