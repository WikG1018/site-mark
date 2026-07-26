// ignore_for_file: lines_longer_than_80_chars
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
    expect(container.read(appSettingControllerProvider).value?.themeMode, 'dark');
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
}
