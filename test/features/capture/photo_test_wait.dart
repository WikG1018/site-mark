import 'package:flutter_test/flutter_test.dart';

typedef PhotoTestCondition = bool Function();

Future<int> pumpUntilPhotoCondition(
  WidgetTester tester, {
  required String condition,
  required PhotoTestCondition isSatisfied,
  String Function()? describeState,
  int maxAttempts = 8,
  Duration decodeOpportunity = const Duration(milliseconds: 10),
  Duration frameDuration = const Duration(milliseconds: 20),
  void Function(int attempt)? onAttempt,
}) async {
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    await tester.runAsync(() => Future<void>.delayed(decodeOpportunity));
    await tester.pump(frameDuration);
    onAttempt?.call(attempt);
    if (isSatisfied()) return attempt;
  }
  final lastState = describeState?.call() ?? 'condition remained false';
  throw TestFailure(
    'Timed out waiting for $condition after $maxAttempts attempts. '
    'Last state: $lastState',
  );
}
