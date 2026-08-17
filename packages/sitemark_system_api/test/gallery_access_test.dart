import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark_system_api/src/ohos/gallery_access.dart';

void main() {
  test('granted ACL selects acl mode', () async {
    final probe = GalleryAccessProbe(reader: () async => true);
    expect(await probe.detect(), GalleryAccessMode.acl);
  });

  test('denied ACL selects picker fallback, not failure', () async {
    final probe = GalleryAccessProbe(reader: () async => false);
    expect(await probe.detect(), GalleryAccessMode.pickerFallback);
  });
}
