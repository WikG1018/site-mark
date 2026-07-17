import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/domain/photo_number.dart';

void main() {
  test('formats a project-prefixed daily photo number with project id', () {
    expect(
      formatPhotoNumber(
        projectName: '东区厂房改造',
        projectId: 'project-1',
        capturedAt: DateTime(2026, 7, 17, 9, 5),
        sequence: 1,
      ),
      '东区厂房改造-project--SM-20260717-001',
    );
  });

  test('sanitizes unsafe characters and repeated separators', () {
    expect(safePhotoProjectName('  A 区 / 风管::检查  '), 'A_区_风管_检查');
  });

  test('truncates to fit UTF-8 byte budget and trims result', () {
    // 60 CJK chars = 180 bytes, well within default budget.
    final repeated = List.filled(60, '工').join();
    final safe = safePhotoProjectName(repeated);
    expect(utf8.encode(safe).length, lessThanOrEqualTo(231)); // 255 - 24
    expect(safe.runes.length, 60);
  });

  test('uses Project when no safe project characters remain', () {
    expect(safePhotoProjectName(' . / : ? _ '), 'Project');
  });

  test('rejects non-positive sequences', () {
    expect(
      () => formatPhotoNumber(
        projectName: '项目',
        projectId: 'p1',
        capturedAt: DateTime(2026, 7, 17),
        sequence: 0,
      ),
      throwsArgumentError,
    );
  });

  test('preserves punctuation outside the forbidden set', () {
    expect(safePhotoProjectName('东区厂房改造（一期）'), '东区厂房改造（一期）');
    expect(safePhotoProjectName('A.B'), 'A.B');
    expect(safePhotoProjectName('--A'), '--A');
    expect(safePhotoProjectName('C&D'), 'C&D');
  });

  test('formats photo numbers with preserved punctuation', () {
    expect(
      formatPhotoNumber(
        projectName: '东区厂房改造（一期）',
        projectId: 'project-1',
        capturedAt: DateTime(2026, 7, 17),
        sequence: 1,
      ),
      '东区厂房改造（一期）-project--SM-20260717-001',
    );
    expect(
      formatPhotoNumber(
        projectName: 'A.B',
        projectId: 'project-1',
        capturedAt: DateTime(2026, 7, 17),
        sequence: 1,
      ),
      'A.B-project--SM-20260717-001',
    );
  });

  test('sanitizes C1 controls and Unicode whitespace consistently', () {
    // C1 control (U+0080) — must be sanitized like C0 controls.
    expect(safePhotoProjectName('A\u0080B'), 'A_B');
    // NBSP (U+00A0) — must be sanitized like ASCII space.
    expect(safePhotoProjectName('A\u00A0B'), 'A_B');
    // EM SPACE (U+2003) — must be sanitized.
    expect(safePhotoProjectName('A\u2003B'), 'A_B');
    // LINE SEPARATOR (U+2028) — must be sanitized.
    expect(safePhotoProjectName('A\u2028B'), 'A_B');
    // ZWNBSP / BOM (U+FEFF) — must be sanitized.
    expect(safePhotoProjectName('A\uFEFFB'), 'A_B');
  });

  test('keeps final jpeg name within 255 UTF-8 bytes', () {
    // 60 four-byte emoji = 240 bytes for the project name alone.
    final projectName = List.filled(60, '😀').join();
    final number = formatPhotoNumber(
      projectName: projectName,
      projectId: 'project-1',
      capturedAt: DateTime(2026, 7, 17),
      sequence: 1,
    );
    expect(utf8.encode('$number.jpg').length, lessThanOrEqualTo(255));
  });

  test(
    'different project ids with same sanitized name produce different numbers',
    () {
      // Two projects whose names sanitize to the same value but whose
      // IDs differ in the first 8 characters produce distinct file names.
      final a = formatPhotoNumber(
        projectName: 'A/B',
        projectId: 'aaaa1111-2222-3333-4444-555566667777',
        capturedAt: DateTime(2026, 7, 17),
        sequence: 1,
      );
      final b = formatPhotoNumber(
        projectName: 'A:B',
        projectId: 'bbbb2222-3333-4444-5555-666677778888',
        capturedAt: DateTime(2026, 7, 17),
        sequence: 1,
      );
      expect(a, 'A_B-aaaa1111-SM-20260717-001');
      expect(b, 'A_B-bbbb2222-SM-20260717-001');
      expect(a, isNot(equals(b)));
      // The JPEG display names passed to MediaStore are also distinct, so
      // the Android lookup-by-DISPLAY_NAME cannot silently overwrite one
      // project's photo with the other's.
      expect('$a.jpg', isNot(equals('$b.jpg')));
    },
  );

  test(
    'different project ids with identical project names produce different numbers',
    () {
      // Two projects with exactly the same display name must still produce
      // distinct file names because the short project id is embedded.
      final a = formatPhotoNumber(
        projectName: '东区厂房改造',
        projectId: 'aaaa1111-2222-3333-4444-555566667777',
        capturedAt: DateTime(2026, 7, 17),
        sequence: 1,
      );
      final b = formatPhotoNumber(
        projectName: '东区厂房改造',
        projectId: 'bbbb2222-3333-4444-5555-666677778888',
        capturedAt: DateTime(2026, 7, 17),
        sequence: 1,
      );
      expect(a, '东区厂房改造-aaaa1111-SM-20260717-001');
      expect(b, '东区厂房改造-bbbb2222-SM-20260717-001');
      expect(a, isNot(equals(b)));
      expect('$a.jpg', isNot(equals('$b.jpg')));
    },
  );
}
