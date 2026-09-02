import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/data/nas_sync_database.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/domain/nas_sync.dart';
import 'package:sitemark/features/settings/sections/nas_sync_section_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/workflow/nas_sync_service.dart';

class _FakeCredentials implements NasCredentialStore {
  String? password;

  @override
  Future<String?> read() async => password;

  @override
  Future<void> write(String password) async {
    passwordSet = password;
  }

  String? passwordSet;

  @override
  Future<void> delete() async {
    password = null;
    passwordSet = null;
  }
}

class _FakeConnectivity implements NasConnectivity {
  @override
  Future<bool> allowsUpload({required bool wifiOnly}) async => false;
}

class _FakeUploader implements NasUploader {
  final List<NasUploadJob> jobs = [];

  @override
  Future<String?> upload(NasUploadJob job) async {
    jobs.add(job);
    return null;
  }
}

void main() {
  late AppDatabase database;
  late _FakeCredentials credentials;
  late _FakeUploader uploader;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    credentials = _FakeCredentials();
    uploader = _FakeUploader();
  });

  tearDown(() async {
    await database.close();
  });

  /// A capture row must exist before its upload state: the FK cascades on
  /// capture deletion.
  Future<void> seedReadyCapture(String id) async {
    await database
        .into(database.projects)
        .insert(
          ProjectsCompanion.insert(
            id: 'p1',
            name: '测试项目',
            createdAt: DateTime(2026, 9, 1),
            updatedAt: DateTime(2026, 9, 1),
          ),
        );
    await database
        .into(database.captureRecords)
        .insert(
          CaptureRecordsCompanion.insert(
            id: id,
            projectId: 'p1',
            workLocation: '施工区',
            workContent: '安装检查',
            photographer: 'Builder',
            originalPath: '/private/$id.jpg',
            status: CaptureStatus.ready,
            createdAt: DateTime(2026, 9, 1),
          ),
        );
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          nasCredentialStoreProvider.overrideWithValue(credentials),
          nasConnectivityProvider.overrideWithValue(_FakeConnectivity()),
          nasUploaderProvider.overrideWithValue(uploader),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const NasSyncSectionScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders defaults and saves the configured target', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.byKey(const Key('nas-enable-switch')), findsOneWidget);
    expect(find.byKey(const Key('nas-host-field')), findsOneWidget);
    expect(find.byKey(const Key('nas-save-button')), findsOneWidget);
    expect(find.text('WebDAV'), findsOneWidget);
    expect(find.text('SFTP'), findsOneWidget);
    expect(find.text('SMB'), findsOneWidget);
    expect(find.byKey(const Key('nas-wifi-only-switch')), findsOneWidget);
    expect(find.byKey(const Key('nas-test-connection-button')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('nas-host-field')),
      'nas.local',
    );
    await tester.enterText(
      find.byKey(const Key('nas-username-field')),
      'builder',
    );
    await tester.enterText(
      find.byKey(const Key('nas-password-field')),
      'secret',
    );
    await tester.enterText(find.byKey(const Key('nas-root-field')), '/dav');
    await tester.tap(find.byKey(const Key('nas-enable-switch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nas-save-button')));
    await tester.pumpAndSettle();

    final config = await database.nasSyncConfig();
    expect(config.host, 'nas.local');
    expect(config.username, 'builder');
    expect(config.rootPath, '/dav');
    expect(config.enabled, isTrue);
    expect(credentials.passwordSet, 'secret');
  });

  testWidgets('switching to SFTP hides the WebDAV-only TLS toggles', (
    tester,
  ) async {
    await pumpScreen(tester);

    // WebDAV (default): HTTPS switch is visible.
    expect(find.text('使用 HTTPS'), findsOneWidget);

    await tester.tap(find.text('SFTP'));
    await tester.pumpAndSettle();

    expect(find.text('使用 HTTPS'), findsNothing);
    expect(find.text('接受自签名证书'), findsNothing);
  });

  testWidgets('enabling with an empty host keeps the switch off', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('nas-enable-switch')));
    await tester.pumpAndSettle();

    final config = await database.nasSyncConfig();
    expect(config.enabled, isFalse);
    final switchWidget = tester.widget<SwitchListTile>(
      find.byKey(const Key('nas-enable-switch')),
    );
    expect(switchWidget.value, isFalse);
    expect(find.text('请先填写服务器地址'), findsOneWidget);
  });

  testWidgets('rejects out-of-range ports and accepts a fixed one', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.enterText(
      find.byKey(const Key('nas-host-field')),
      'nas.local',
    );
    await tester.enterText(find.byKey(const Key('nas-port-field')), '70000');
    // Let the focus-driven scroll settle before scrolling to the button.
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('nas-save-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nas-save-button')));
    await tester.pumpAndSettle();

    // The save was blocked: no config row exists yet.
    final blocked = await database.nasSyncConfig();
    expect(blocked.host, isEmpty);
    expect(find.text('端口需在 1–65535 之间'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('nas-port-field')), '8443');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('nas-save-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nas-save-button')));
    await tester.pumpAndSettle();

    final saved = await database.nasSyncConfig();
    expect(saved.host, 'nas.local');
    expect(saved.port, 8443);
  });

  testWidgets('shows the queue summary and retries failed uploads', (
    tester,
  ) async {
    await seedReadyCapture('capture-1');
    await database.upsertNasUploadPending('capture-1');
    for (var i = 0; i < 5; i++) {
      await database.markNasUploadFailed('capture-1', 'timeout');
    }
    await pumpScreen(tester);

    await tester.ensureVisible(find.byKey(const Key('nas-retry-button')));
    await tester.pumpAndSettle();
    expect(find.text('待上传 0 · 失败 1 · 已上传 0'), findsOneWidget);
    final retryButton = tester.widget<OutlinedButton>(
      find.byKey(const Key('nas-retry-button')),
    );
    expect(retryButton.onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('nas-retry-button')));
    await tester.pumpAndSettle();

    final states = await database.allNasUploadStates();
    expect(states.single.status, NasUploadStatus.pending);
    expect(states.single.attempts, 0);
    expect(uploader.jobs, isEmpty);
    final resetButton = tester.widget<OutlinedButton>(
      find.byKey(const Key('nas-retry-button')),
    );
    expect(resetButton.onPressed, isNull);
  });
}
