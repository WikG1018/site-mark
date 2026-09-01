import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/data/nas_sync_database.dart';
import 'package:sitemark/features/settings/sections/nas_sync_section_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/workflow/nas_sync_service.dart';

class _FakeCredentials implements NasCredentialStore {
  _FakeCredentials([this.password]);

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

void main() {
  late AppDatabase database;
  late _FakeCredentials credentials;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    credentials = _FakeCredentials();
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          nasCredentialStoreProvider.overrideWithValue(credentials),
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
}
