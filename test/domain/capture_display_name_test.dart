import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/domain/capture_display_name.dart';

void main() {
  test('uses date and sequence for legacy photo numbers', () {
    expect(
      captureListDisplayName(
        capturedAt: DateTime(2026, 7, 17),
        photoNumber: '云湖之城~uuid-SM-20260717-003',
        fallback: '南地块',
      ),
      '2026-07-17 · 003',
    );
  });

  test('uses date and sequence for new short photo numbers', () {
    expect(
      captureListDisplayName(
        capturedAt: DateTime(2026, 7, 17),
        photoNumber: '云湖之城-SM-20260717-012',
        fallback: '南地块',
      ),
      '2026-07-17 · 012',
    );
  });

  test('falls back when capture evidence is incomplete', () {
    expect(
      captureListDisplayName(
        capturedAt: null,
        photoNumber: null,
        fallback: '南地块',
      ),
      '南地块',
    );
  });
}
