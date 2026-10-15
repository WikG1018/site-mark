import 'dart:convert';
import 'dart:io';

import 'package:sitemark/domain/release_check.dart';

/// Transport result. A redirect, non-200, or oversized body is not usable.
class ReleaseFetch {
  const ReleaseFetch({
    required this.statusCode,
    required this.body,
    this.redirected = false,
    this.truncated = false,
  });

  final int statusCode;
  final String body;
  final bool redirected;
  final bool truncated;

  bool get usableJson =>
      !redirected && !truncated && statusCode == 200 && body.isNotEmpty;
}

typedef ReleaseFetcher =
    Future<ReleaseFetch> Function(
      Uri uri, {
      required Duration timeout,
      required String accept,
    });

abstract interface class ReleaseLookup {
  Future<ReleaseCheckOutcome> check({
    required String localVersion,
    required ReleaseCheckMode mode,
  });

  /// Official success returns the GitHub page with no further request.
  /// A mirror success probes the fixed page-mirror list and never gh-proxy.com.
  Future<Uri?> resolveReleasePage(ReleaseCheckOutcome outcome);
}

class GithubReleaseClient implements ReleaseLookup {
  GithubReleaseClient({ReleaseFetcher? fetcher, ReleaseProduct? product})
    : _fetcher = fetcher ?? httpReleaseFetch,
      product = product ?? ReleaseProduct.flutter;

  final ReleaseFetcher _fetcher;
  final ReleaseProduct product;

  @override
  Future<ReleaseCheckOutcome> check({
    required String localVersion,
    required ReleaseCheckMode mode,
  }) async {
    if (parseVersion(localVersion) == null) {
      return const ReleaseCheckOutcome.failed();
    }
    for (final attempt in apiAttemptPlan(mode, product)) {
      if (!isAllowedApiUrl(attempt.rawUrl)) continue;
      final ReleaseFetch fetched;
      try {
        fetched = await _fetcher(
          attempt.uri,
          timeout: attempt.timeout,
          accept: releaseCheckAccept,
        );
      } catch (_) {
        continue;
      }
      if (!fetched.usableJson) continue;
      final read = readReleaseBody(fetched.body, product);
      if (!read.usable) continue;
      final outcome = outcomeFromRead(
        localVersion: localVersion,
        read: read,
        source: attempt.source,
      );
      if (outcome.status == ReleaseCheckStatus.failed) {
        return const ReleaseCheckOutcome.failed();
      }
      return outcome;
    }
    return const ReleaseCheckOutcome.failed();
  }

  @override
  Future<Uri?> resolveReleasePage(ReleaseCheckOutcome outcome) async {
    final tag = outcome.tag;
    if (!outcome.hasUpdate || tag == null || tag.isEmpty) return null;
    if (outcome.source == ReleaseSource.official) {
      final page = officialReleasePage(tag);
      return isAllowedReleasePageUrl(page) ? Uri.parse(page) : null;
    }
    if (outcome.source != ReleaseSource.apiMirror) return null;
    for (final raw in pageOpenCandidates(tag)) {
      if (!isAllowedReleasePageUrl(raw)) continue;
      final ReleaseFetch fetched;
      try {
        fetched = await _fetcher(
          Uri.parse(raw),
          timeout: mirrorTimeout,
          accept: releasePageAccept,
        );
      } catch (_) {
        continue;
      }
      if (fetched.redirected || fetched.statusCode != 200) continue;
      if (looksLikeGithubReleasePage(fetched.statusCode, fetched.body)) {
        return Uri.parse(raw);
      }
    }
    return null;
  }
}

/// Production transport. Fresh client, no cookies, no Authorization, no body.
Future<ReleaseFetch> httpReleaseFetch(
  Uri uri, {
  required Duration timeout,
  required String accept,
}) async {
  if (uri.scheme != 'https') {
    return const ReleaseFetch(statusCode: 0, body: '');
  }
  final client = HttpClient();
  try {
    client.connectionTimeout = timeout;
    client.userAgent = releaseCheckUserAgent;
    final request = await client.getUrl(uri).timeout(timeout);
    request.followRedirects = false;
    request.persistentConnection = false;
    final headers = releaseApiHeaders();
    request.headers.set(HttpHeader.userAgent, headers[HttpHeader.userAgent]!);
    request.headers.set(HttpHeader.accept, accept);
    request.headers.removeAll(HttpHeader.cookie);
    request.headers.removeAll(HttpHeader.authorization);
    final response = await request.close().timeout(timeout);
    if (response.isRedirect ||
        (response.statusCode >= 300 && response.statusCode < 400)) {
      await response.drain<void>();
      return ReleaseFetch(
        statusCode: response.statusCode,
        body: '',
        redirected: true,
      );
    }
    final bytes = BytesBuilder(copy: false);
    var total = 0;
    var truncated = false;
    await for (final chunk in response.timeout(timeout)) {
      total += chunk.length;
      if (total > releaseCheckBodyLimit) {
        truncated = true;
        break;
      }
      bytes.add(chunk);
    }
    if (truncated) {
      return ReleaseFetch(
        statusCode: response.statusCode,
        body: '',
        truncated: true,
      );
    }
    return ReleaseFetch(
      statusCode: response.statusCode,
      body: utf8.decode(bytes.takeBytes(), allowMalformed: true),
    );
  } finally {
    client.close(force: true);
  }
}
