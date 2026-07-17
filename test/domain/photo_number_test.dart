import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/domain/photo_number.dart';

void main() {
  test('formats a project-prefixed daily photo number', () {
    expect(
      formatPhotoNumber(
        projectName: '东区厂房改造',
        capturedAt: DateTime(2026, 7, 17, 9, 5),
        sequence: 1,
      ),
      '东区厂房改造-SM-20260717-001',
    );
  });

  test('sanitizes unsafe characters and repeated separators', () {
    expect(safePhotoProjectName('  A 区 / 风管::检查  '), 'A_区_风管_检查');
  });

  test('truncates to 60 code points and trims the truncated result', () {
    final repeated = List.filled(59, '工').join();
    final raw = '$repeated._extra';
    final safe = safePhotoProjectName(raw);
    expect(safe.runes.length, 59);
    expect(safe, repeated);
  });

  test('uses Project when no safe project characters remain', () {
    expect(safePhotoProjectName(' . / : ? _ '), 'Project');
  });

  test('rejects non-positive sequences', () {
    expect(
      () => formatPhotoNumber(
        projectName: '项目',
        capturedAt: DateTime(2026, 7, 17),
        sequence: 0,
      ),
      throwsArgumentError,
    );
  });
}
