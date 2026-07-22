# Task 4 Report: Cached and Bounded Storage Usage

## Delivered

- Kept `storageUsageProvider` alive after settings-page disposal. Existing
  refresh, retry, and export-clear flows continue to reload through explicit
  `invalidate` calls.
- Added an injectable `FileLengthLoader`. The production default still treats
  `FileSystemException` as a zero-byte read.
- Enumerates files asynchronously, classifies each physical file once, and
  sums lengths through one shared queue with at most eight workers.

## TDD record

1. **RED — provider lifecycle:** the new `ProviderContainer` test observed
   `loadCount == 2` after listener disposal and re-entry, while the expected
   cached value required `loadCount == 1`.
2. **GREEN — provider lifecycle:** changing from `FutureProvider.autoDispose`
   to retained `FutureProvider` made the test pass; explicit invalidation then
   produced the second load as required.
3. **RED — bounded file reads:** the many-file test failed to compile because
   `AppStorageUsageService` had no `fileLength` injection point.
4. **GREEN — bounded file reads:** the service now starts at most eight active
   length loads and the test verifies 21 physical files total 311 bytes with
   duplicate capture paths counted once.

## Verification

- `flutter test test/workflow/app_storage_service_test.dart test/features/settings/global_settings_screen_test.dart` — passed (20 tests).
- `flutter analyze` — passed, no issues.
- `flutter test` — passed (216 tests).

## Concern

The full pre-existing suite still emits Drift's warning about multiple
`AppDatabase` instances sharing a query executor. It does not fail the suite
and is outside this task's storage-usage scope.
