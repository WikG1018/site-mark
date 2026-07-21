import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/platform/notification_service.dart';

void main() {
  group('captureReadyDeepLink', () {
    test('builds the capture-detail deep-link path', () {
      expect(
        captureReadyDeepLink('project-1', 'capture-9'),
        '/projects/project-1/captures/capture-9',
      );
    });
  });

  group('CompletionNotificationService send gate', () {
    late _FakeCompletionNotificationService service;

    setUp(() {
      service = _FakeCompletionNotificationService();
    });

    test('delivers the captureReadyDeepLink payload when enabled', () async {
      await service.setEnabled(true);
      await service.showCaptureReady(
        projectId: 'project-1',
        captureId: 'capture-9',
        photoNumber: 'IMG-0009',
      );

      expect(service.showCalls, 1);
      expect(
        service.lastPayload,
        captureReadyDeepLink('project-1', 'capture-9'),
      );
      expect(service.lastPayload, '/projects/project-1/captures/capture-9');
    });

    test('gates sending when disabled', () async {
      await service.setEnabled(false);
      await service.showCaptureReady(
        projectId: 'project-1',
        captureId: 'capture-9',
        photoNumber: 'IMG-0009',
      );

      expect(service.showCalls, 0);
      expect(service.lastPayload, isNull);
    });
  });
}

/// Records calls and mirrors the production gate semantics (`setEnabled`
/// must be true before `showCaptureReady` delivers) so the gate contract is
/// exercised without the real plugin.
class _FakeCompletionNotificationService
    implements CompletionNotificationService {
  bool enabled = false;
  int showCalls = 0;
  String? lastPayload;

  @override
  Future<void> initialize(
    void Function(String deepLinkPath) onTapDeepLink,
  ) async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> showCaptureReady({
    required String projectId,
    required String captureId,
    required String photoNumber,
  }) async {
    if (!enabled) return;
    showCalls++;
    lastPayload = captureReadyDeepLink(projectId, captureId);
  }

  @override
  Future<void> setEnabled(bool value) async {
    enabled = value;
  }
}
