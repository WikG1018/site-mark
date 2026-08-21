import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark_system_api/src/ohos/share_cancel_policy.dart';

void main() {
  test('cancelled and Canceled share errors are user cancel', () {
    expect(
      ShareCancelPolicy.isUserCancelled(
        Exception('User cancelled the share panel'),
      ),
      isTrue,
    );
    expect(
      ShareCancelPolicy.isUserCancelled(Exception('Operation Canceled')),
      isTrue,
    );
  });

  test('empty source, not ready, and other errors are not user cancel', () {
    expect(ShareCancelPolicy.isUserCancelled(null), isFalse);
    expect(
      ShareCancelPolicy.isUserCancelled(
        Exception('share source is empty or missing'),
      ),
      isFalse,
    );
    expect(
      ShareCancelPolicy.isUserCancelled(Exception('ohos_not_ready')),
      isFalse,
    );
    expect(
      ShareCancelPolicy.isUserCancelled(
        Exception('ability context unavailable'),
      ),
      isFalse,
    );
  });
}
