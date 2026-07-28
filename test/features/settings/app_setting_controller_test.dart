// ignore_for_file: lines_longer_than_80_chars
import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/features/settings/app_setting_controller.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test('build loads the singleton AppSetting', () async {
    await database.getAppSettings();
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(database)],
    );
    addTearDown(container.dispose);
    final result = await container.read(appSettingControllerProvider.future);
    expect(result.themeMode, 'system');
  });

  test('update persists and reflects the new value', () async {
    await database.getAppSettings();
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(database)],
    );
    addTearDown(container.dispose);
    await container.read(appSettingControllerProvider.future);
    await container
        .read(appSettingControllerProvider.notifier)
        .update((s) => s.copyWith(themeMode: 'dark'));
    final fromDb = await database.getAppSettings();
    expect(fromDb.themeMode, 'dark');
    expect(
      container.read(appSettingControllerProvider).value?.themeMode,
      'dark',
    );
  });

  test('update persists appSeedColorArgb', () async {
    await database.getAppSettings();
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(database)],
    );
    addTearDown(container.dispose);
    await container.read(appSettingControllerProvider.future);
    await container
        .read(appSettingControllerProvider.notifier)
        .update((s) => s.copyWith(appSeedColorArgb: 0xff1565c0));
    final persisted = await database.getAppSettings();
    expect(persisted.appSeedColorArgb, 0xff1565c0);
  });

  test('overlapping updates persist the last user selection', () async {
    final delayedDatabase = _DelayedFirstWriteDatabase();
    addTearDown(delayedDatabase.close);
    await delayedDatabase.getAppSettings();
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(delayedDatabase)],
    );
    addTearDown(container.dispose);
    await container.read(appSettingControllerProvider.future);
    final controller = container.read(appSettingControllerProvider.notifier);

    final first = controller.update(
      (settings) => settings.copyWith(appSeedColorArgb: 0xff1565c0),
    );
    await delayedDatabase.firstWriteStarted.future;
    final second = controller.update(
      (settings) => settings.copyWith(appSeedColorArgb: 0xff6a1b9a),
    );
    await Future<void>.delayed(Duration.zero);
    delayedDatabase.releaseFirstWrite.complete();
    await Future.wait([first, second]);

    expect(
      (await delayedDatabase.getAppSettings()).appSeedColorArgb,
      0xff6a1b9a,
    );
  });

  test(
    'overlapping write failures roll back to the persisted settings',
    () async {
      final delayedDatabase = _DelayedFirstWriteDatabase(failWrites: true);
      addTearDown(delayedDatabase.close);
      final persistedBefore = await delayedDatabase.getAppSettings();
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(delayedDatabase)],
      );
      addTearDown(container.dispose);
      await container.read(appSettingControllerProvider.future);
      final controller = container.read(appSettingControllerProvider.notifier);

      final first = controller
          .update((settings) => settings.copyWith(appSeedColorArgb: 0xff1565c0))
          .then<void>((_) {}, onError: (_, _) {});
      await delayedDatabase.firstWriteStarted.future;
      final second = controller
          .update((settings) => settings.copyWith(appSeedColorArgb: 0xff6a1b9a))
          .then<void>((_) {}, onError: (_, _) {});
      delayedDatabase.releaseFirstWrite.complete();
      await Future.wait([first, second]);

      expect(
        container.read(appSettingControllerProvider).value?.appSeedColorArgb,
        persistedBefore.appSeedColorArgb,
      );
      expect(
        (await delayedDatabase.getAppSettings()).appSeedColorArgb,
        persistedBefore.appSeedColorArgb,
      );
    },
  );
}

class _DelayedFirstWriteDatabase extends AppDatabase {
  _DelayedFirstWriteDatabase({this.failWrites = false})
    : super.forTesting(NativeDatabase.memory());

  final bool failWrites;
  final firstWriteStarted = Completer<void>();
  final releaseFirstWrite = Completer<void>();
  var _writeCount = 0;

  @override
  Future<AppSetting> updateAppSettings({
    String? themeMode,
    String? localeCode,
    String? defaultWatermarkPosition,
    double? defaultWatermarkOpacity,
    int? defaultWatermarkAccentColorArgb,
    double? defaultWatermarkFontScale,
    bool? locationPermissionPromptDismissed,
    bool? useDynamicColor,
    bool? completionNotificationsEnabled,
    int? appSeedColorArgb,
  }) async {
    _writeCount++;
    if (_writeCount == 1) {
      firstWriteStarted.complete();
      await releaseFirstWrite.future;
    }
    if (failWrites) {
      throw StateError('simulated settings write failure');
    }
    return super.updateAppSettings(
      themeMode: themeMode,
      localeCode: localeCode,
      defaultWatermarkPosition: defaultWatermarkPosition,
      defaultWatermarkOpacity: defaultWatermarkOpacity,
      defaultWatermarkAccentColorArgb: defaultWatermarkAccentColorArgb,
      defaultWatermarkFontScale: defaultWatermarkFontScale,
      locationPermissionPromptDismissed: locationPermissionPromptDismissed,
      useDynamicColor: useDynamicColor,
      completionNotificationsEnabled: completionNotificationsEnabled,
      appSeedColorArgb: appSeedColorArgb,
    );
  }
}
