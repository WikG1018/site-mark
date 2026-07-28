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
  Future<void> _writeTail = Future<void>.value();
  AppSetting? _lastPersisted;
  var _updateRevision = 0;

  @override
  Future<AppSetting> build() async {
    final db = ref.read(databaseProvider);
    final settings = await db.getAppSettings();
    _lastPersisted = settings;
    return settings;
  }

  /// Updates the [AppSetting] optimistically, then persists to the database.
  /// If persistence fails, the state rolls back to the previous value.
  ///
  /// Overrides Riverpod's built-in [AsyncNotifier.update] to interleave the
  /// database write between the optimistic state set and the return.
  @override
  Future<AppSetting> update(
    FutureOr<AppSetting> Function(AppSetting current) updater, {
    FutureOr<AppSetting> Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    final current = state.value;
    if (current == null) {
      // State is loading/error; defer to the default behavior so callers
      // wiring `onError` still get the expected contract.
      return super.update(updater, onError: onError);
    }
    final next = await updater(current);
    final revision = ++_updateRevision;
    state = AsyncData(next);
    final previousWrite = _writeTail;
    final writeCompleted = Completer<void>();
    _writeTail = writeCompleted.future;
    try {
      // UI callbacks do not await one another. Preserve invocation order at
      // the database boundary so a slower, older write cannot overwrite the
      // user's latest theme or color selection.
      await previousWrite;
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
      _lastPersisted = next;
      return next;
    } catch (e, st) {
      // Roll back only when this is still the newest optimistic update. Use
      // the last successful database snapshot rather than this call's input:
      // overlapping failed updates may have been based on another optimistic
      // value that never reached disk.
      if (_updateRevision == revision) {
        state = AsyncData(_lastPersisted ?? current);
      }
      if (onError != null) {
        return await onError(e, st);
      }
      rethrow;
    } finally {
      writeCompleted.complete();
    }
  }
}

final appSettingControllerProvider =
    AsyncNotifierProvider<AppSettingController, AppSetting>(
      AppSettingController.new,
    );
