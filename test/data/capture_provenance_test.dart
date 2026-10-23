import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/app_database.dart';

void main() {
  late AppDatabase database;
  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.createProject(id: 'p', name: 'Test project');
  });
  tearDown(() => database.close());

  test('watermark time never changes capture evidence or filename', () async {
    final actual = DateTime(2026, 10, 22, 10, 11, 12);
    final display = DateTime(2026, 10, 20, 8, 30);
    await database.createPendingCapture(
      id: 'c',
      projectId: 'p',
      originalPath: '/private/c.jpg',
      workLocation: 'Floor 1',
      workContent: 'Inspection',
      photographer: 'A',
      watermarkTime: display,
      watermarkLocaleCode: 'en',
    );
    final original = await database.markCaptured(
      captureId: 'c',
      capturedAt: actual,
    );
    expect(original.watermarkTime, display);
    expect(original.captureSource, 'camera');
    final updated = await database.updateCaptureDescription(
      captureId: 'c',
      workLocation: 'Floor 1',
      workContent: 'Inspection',
      photographer: 'A',
      watermarkTime: DateTime(2025, 1, 2),
      updateWatermarkTime: true,
    );
    expect(updated.capturedAt, actual);
    expect(updated.photoNumber, original.photoNumber);
    expect(updated.originalPath, original.originalPath);
    expect(updated.watermarkTime, DateTime(2025, 1, 2));
    final reset = await database.updateCaptureDescription(
      captureId: 'c',
      workLocation: 'Floor 1',
      workContent: 'Inspection',
      photographer: 'A',
      watermarkTime: null,
      updateWatermarkTime: true,
    );
    expect(reset.watermarkTime, isNull);
    expect(reset.capturedAt, actual);
  });

  test(
    'restoring a gallery record retains source and display timestamp',
    () async {
      final exif = DateTime(2024, 3, 4, 5, 6);
      final display = DateTime(2024, 3, 5, 5, 6);
      final restored = await database.insertRestoredCapture(
        id: 'imported',
        projectId: 'p',
        photoNumber: 'Test-SM-20240304-001',
        originalPath: '/private/imported.jpg',
        workLocation: 'Floor 1',
        workContent: 'Inspection',
        photographer: 'A',
        originalSha256: 'a' * 64,
        createdAt: DateTime(2026),
        capturedAt: exif,
        captureSource: 'gallery',
        sourceCapturedAt: exif,
        watermarkTime: display,
      );
      expect(restored.captureSource, 'gallery');
      expect(restored.sourceCapturedAt, exif);
      expect(restored.watermarkTime, display);
    },
  );
}
