import 'package:url_launcher/url_launcher.dart';

abstract interface class ExternalLinkService {
  Future<bool> open(Uri uri);
}

typedef UrlLauncher =
    Future<bool> Function(Uri uri, {required LaunchMode mode});

class UrlLauncherExternalLinkService implements ExternalLinkService {
  const UrlLauncherExternalLinkService({UrlLauncher? launcher})
    : _launcher = launcher ?? launchUrl;
  final UrlLauncher _launcher;

  @override
  Future<bool> open(Uri uri) =>
      _launcher(uri, mode: LaunchMode.externalApplication);
}
