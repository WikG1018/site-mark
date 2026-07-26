import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';

/// Centralizes [AppSetting] read/persist logic for all settings sub-pages.
///
/// Sub-pages `ref.watch(appSettingControllerProvider)` for auto-rebuild on
/// change. Call [update] with a functional updater to modify the setting:
/// the controller optimistic-updates the state, then persists to the database.
class AppSettingController extends AsyncNotifier<AppSetting> {
  @override
  Future<AppSetting> build() {
    final db = ref.read(databaseProvider);
    return db.getAppSettings();
  }

  /// Updates the [AppSetting] optimistically, then persists to the database.
  /// If persistence fails, the state rolls back to the previous value.
  ///
  /// Overrides Riverpod's built-in [AsyncNotifier.update] to interleave the
  /// database write between the optimistic state set and the return.
  @override
  Future<AppSetting> update(
    FutureOr<AppSetting> Function(AppSetting current) updater, {
    FutureOr<AppSetting> Function(Object error, StackTrace stackTrace)?
        onError,
  }) async {
    final current = state.value;
    if (current == null) {
      // State is loading/error; defer to the default behavior so callers
      // wiring `onError` still get the expected contract.
      return super.update(updater, onError: onError);
    }
    final next = await updater(current);
    state = AsyncData(next);
    try {
      final db = ref.read(databaseProvider);
      await db.updateAppSettings(
        themeMode: next.themeMode,
        useDynamicColor: next.useDynamicColor,
        localeCode: next.localeCode,
        defaultWatermarkPosition: next.defaultWatermarkPosition,
        defaultWatermarkOpacity: next.defaultWatermarkOpacity,
        defaultWatermarkFontScale: next.defaultWatermarkFontScale,
        defaultWatermarkAccentColorArgb: next.defaultWatermarkAccentColorArgb,
        completionNotificationsEnabled: next.completionNotificationsEnabled,
        appSeedColorArgb: next.appSeedColorArgb,
      );
      return next;
    } catch (e, st) {
      // Roll back to the previous value on persist failure.
      state = AsyncData(current);
      if (onError != null) {
        return await onError(e, st);
      }
      rethrow;
    }
  }
}

final appSettingControllerProvider =
    AsyncNotifierProvider<AppSettingController, AppSetting>(
  AppSettingController.new,
);
