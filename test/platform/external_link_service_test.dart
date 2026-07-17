import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/domain/app_links.dart';
import 'package:sitemark/platform/external_link_service.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  test('external link service uses external application mode', () async {
    Uri? opened;
    LaunchMode? openedMode;
    final service = UrlLauncherExternalLinkService(
      launcher: (uri, {required LaunchMode mode}) async {
        opened = uri;
        openedMode = mode;
        return true;
      },
    );

    expect(await service.open(siteMarkRepositoryUri), isTrue);
    expect(opened, siteMarkRepositoryUri);
    expect(openedMode, LaunchMode.externalApplication);
  });
}
