import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark_system_api/src/ohos/publish_fallback_policy.dart';

void main() {
  test('empty destinations fall back to sandbox without throwing', () {
    expect(
      PublishFallbackPolicy.decide(destinations: null),
      PublishFallbackDecision.sandbox,
    );
    expect(
      PublishFallbackPolicy.decide(destinations: const []),
      PublishFallbackDecision.sandbox,
    );
    expect(
      PublishFallbackPolicy.shouldRethrow(
        destinations: const [],
        error: Exception('User cancelled the album save dialog'),
      ),
      isFalse,
    );
  });

  test('cancelled and Canceled album errors fall back to sandbox', () {
    expect(
      PublishFallbackPolicy.decide(
        error: Exception('User cancelled the album save dialog'),
      ),
      PublishFallbackDecision.sandbox,
    );
    expect(
      PublishFallbackPolicy.decide(error: Exception('Operation Canceled')),
      PublishFallbackDecision.sandbox,
    );
    expect(
      PublishFallbackPolicy.shouldRethrow(
        error: Exception('User cancelled the album save dialog'),
      ),
      isFalse,
    );
  });

  test('other album errors also fall back to sandbox', () {
    expect(
      PublishFallbackPolicy.decide(error: Exception('copy failed')),
      PublishFallbackDecision.sandbox,
    );
    expect(
      PublishFallbackPolicy.shouldRethrow(error: Exception('copy failed')),
      isFalse,
    );
  });

  test('non-empty destination stays on album', () {
    expect(
      PublishFallbackPolicy.decide(
        destinations: const ['file://media/Photo/123'],
      ),
      PublishFallbackDecision.album,
    );
    expect(
      PublishFallbackPolicy.shouldRethrow(
        destinations: const ['file://media/Photo/123'],
      ),
      isFalse,
    );
  });
}
