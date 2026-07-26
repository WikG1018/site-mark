import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('foreground and background share one Rust initialization owner', () {
    final platformSource = File(
      'lib/platform/platform_services.dart',
    ).readAsStringSync();
    final backgroundSource = File(
      'lib/background/capture_background_scheduler.dart',
    ).readAsStringSync();

    expect('RustLib.init()'.allMatches(platformSource), hasLength(1));
    expect(
      backgroundSource,
      isNot(contains('RustLib.init()')),
      reason:
          'The headless worker uses RustImagePipeline, which already awaits '
          'the shared per-isolate Rust initializer.',
    );
  });
}
