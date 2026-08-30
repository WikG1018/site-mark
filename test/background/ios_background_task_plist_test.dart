import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/background/capture_background_scheduler.dart';

/// Pins the Dart BGTaskScheduler identifier to `ios/Runner/Info.plist`.
///
/// iOS requires an exact three-way match between [iosCaptureProcessingBgTask],
/// the `BGTaskSchedulerPermittedIdentifiers` entry, and the
/// `WorkmanagerPlugin.registerBGProcessingTask(withIdentifier:)` call in
/// `ios/Runner/AppDelegate.swift` (the AppDelegate string cannot be reached
/// from Dart tests; the CI ios job compiles it, this guard keeps the other
/// two sides from drifting). Only `processing` may be declared as a
/// background mode — audio/location/fetch are explicitly not requested.
void main() {
  List<String> plistArrayEntries(String plist, String key) {
    final block = RegExp(
      '<key>$key</key>\\s*<array>(.*?)</array>',
      dotAll: true,
    ).firstMatch(plist)?.group(1);
    if (block == null) {
      fail('Info.plist is missing the <$key> array');
    }
    return RegExp(
      '<string>(.*?)</string>',
    ).allMatches(block).map((match) => match.group(1)!).toList();
  }

  test('Info.plist permits exactly the capture-processing task identifier', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();

    final identifiers = plistArrayEntries(
      plist,
      'BGTaskSchedulerPermittedIdentifiers',
    );
    expect(identifiers, [iosCaptureProcessingBgTask]);
  });

  test('Info.plist declares only the processing background mode', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();

    expect(plistArrayEntries(plist, 'UIBackgroundModes'), ['processing']);
  });
}
