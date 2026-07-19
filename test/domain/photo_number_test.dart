import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/domain/photo_number.dart';

void main() {
  test('formats a short project-prefixed daily photo number', () {
    expect(
      formatPhotoNumber(
        projectName: '云湖之城',
        capturedAt: DateTime(2026, 7, 17, 9, 5),
        sequence: 3,
      ),
      '云湖之城-SM-20260717-003',
    );
  });

  test('sanitizes forbidden characters and repeated separators', () {
    expect(safePhotoProjectName('  A 区 / 风管::检查  '), 'A_区_风管_检查');
    expect(safePhotoProjectName('A~B'), 'A_B');
  });

  test('preserves punctuation outside the forbidden set', () {
    expect(safePhotoProjectName('东区厂房改造（一期）'), '东区厂房改造（一期）');
    expect(safePhotoProjectName('A.B'), 'A.B');
    expect(safePhotoProjectName('--A'), '--A');
    expect(safePhotoProjectName('C&D'), 'C&D');
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

  test('sanitizes controls and Unicode whitespace consistently', () {
    expect(safePhotoProjectName('A\u0080B'), 'A_B');
    expect(safePhotoProjectName('A\u00A0B'), 'A_B');
    expect(safePhotoProjectName('A\u2003B'), 'A_B');
    expect(safePhotoProjectName('A\u2028B'), 'A_B');
    expect(safePhotoProjectName('A\uFEFFB'), 'A_B');
  });

  test('keeps final jpeg name within 255 UTF-8 bytes', () {
    final projectName = List.filled(60, '😀').join();
    final number = formatPhotoNumber(
      projectName: projectName,
      capturedAt: DateTime(2026, 7, 17),
      sequence: 1,
    );
    expect(utf8.encode('$number.jpg').length, lessThanOrEqualTo(255));
  });
}
