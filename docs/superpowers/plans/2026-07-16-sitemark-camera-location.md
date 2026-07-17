# SiteMark Fast Camera and Location Coordination Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Open the system camera without waiting for location, then resolve capture location from EXIF first and an already-authorized one-shot request second before persistent watermark processing begins.

**Architecture:** Split permission prompting, current-location acquisition, metadata inspection, and render scheduling into explicit stages. The foreground workflow launches `ACTION_IMAGE_CAPTURE` immediately; a record-scoped coordinator resolves EXIF/fallback location off the user interaction path and only then enqueues WorkManager. Startup recovery finalizes any `pending` location state before queue reconciliation.

**Tech Stack:** Flutter/Dart, Pigeon 27.1.2, Kotlin/Android `LocationManager`, AndroidX ExifInterface 1.4.2, WorkManager 0.9.0+3, Drift schema v4.

## Global Constraints

- Complete `2026-07-16-sitemark-field-test-foundation.md` first.
- Continue using `ACTION_IMAGE_CAPTURE`; do not add CameraX, Camera2 UI, or a third-party camera screen.
- The capture-button path must never request runtime permission and must never await location, EXIF, hashing, Rust rendering, or MediaStore publishing.
- Already granted permission shows no explanation. Unapproved permission shows a non-blocking explanation only; the system prompt requires an explicit “Enable location” tap.
- No background-location permission, network permission, cloud lookup, reverse geocoding, or stale post-capture location substitution.
- Source priority is valid EXIF GPS, then the record-scoped one-shot location started at capture click, then `unavailable`.
- Generated Pigeon Dart/Kotlin files must be regenerated, never hand-edited.
- Use `androidx.exifinterface:exifinterface:1.4.2`, the current stable AndroidX release selected for this plan.

---

## File Map

- Modify: `pigeons/system_api.dart` — permission-state, explicit permission request, app-settings intent, and image metadata DTO/API.
- Regenerate: `packages/sitemark_system_api/lib/src/system_api.g.dart`, `packages/sitemark_system_api/android/src/main/kotlin/io/github/wikg1018/sitemark/system/SystemApi.g.kt`.
- Modify: `packages/sitemark_system_api/android/build.gradle` — AndroidX ExifInterface dependency.
- Modify: `packages/sitemark_system_api/android/src/main/kotlin/io/github/wikg1018/sitemark/system/AndroidSystemApi.kt` — permission separation and metadata inspection.
- Create: `packages/sitemark_system_api/android/src/main/kotlin/io/github/wikg1018/sitemark/system/ImageMetadataReader.kt` — testable AndroidX EXIF reader.
- Modify: `packages/sitemark_system_api/android/src/main/kotlin/io/github/wikg1018/sitemark/system/SiteMarkSystemPlugin.kt` — permission callback routing.
- Modify: Android plugin tests under `packages/sitemark_system_api/android/src/test/**`.
- Modify: `lib/platform/platform_services.dart` and `test/platform/platform_services_test.dart` — typed Dart bridge.
- Create: `lib/workflow/capture_location_coordinator.dart` and `test/workflow/capture_location_coordinator_test.dart`.
- Create: `lib/workflow/location_permission_service.dart` and `test/workflow/location_permission_service_test.dart`.
- Create: `lib/features/capture/location_permission_prompt.dart`.
- Modify: `lib/features/capture/capture_form_screen.dart`, `lib/features/settings/global_settings_screen.dart`, `lib/l10n/app_strings.dart`.
- Modify: `lib/workflow/capture_workflow.dart`, `lib/workflow/app_startup_recovery.dart`, `lib/background/capture_background_scheduler.dart`, `lib/workflow/capture_processor.dart`, `lib/app.dart`.
- Modify: workflow, widget, and scheduler tests affected by the interfaces.

### Task 1: Separate Permission Prompting and Add EXIF Metadata Inspection

**Files:**
- Modify: `pigeons/system_api.dart`
- Modify: `packages/sitemark_system_api/android/build.gradle`
- Modify: `packages/sitemark_system_api/android/src/main/kotlin/io/github/wikg1018/sitemark/system/AndroidSystemApi.kt`
- Create: `packages/sitemark_system_api/android/src/main/kotlin/io/github/wikg1018/sitemark/system/ImageMetadataReader.kt`
- Modify: `packages/sitemark_system_api/android/src/main/kotlin/io/github/wikg1018/sitemark/system/SiteMarkSystemPlugin.kt`
- Modify: `packages/sitemark_system_api/android/src/test/kotlin/io/github/wikg1018/sitemark/system/AndroidSystemApiTest.kt`
- Regenerate: Pigeon Dart and Kotlin output.

**Interfaces:**
- Produces: `LocationPermissionState { granted, denied, permanentlyDenied }`
- Produces: `ImageMetadataResult(width, height, fileSizeBytes, mimeType, latitude?, longitude?)`
- Produces: `SiteMarkSystemApi.getLocationPermissionState()`
- Produces: `SiteMarkSystemApi.requestLocationPermission()`
- Produces: `SiteMarkSystemApi.openApplicationSettings()`
- Produces: `SiteMarkSystemApi.inspectImage(String path)`

- [ ] **Step 1: Extend Pigeon source and generate a failing Android compile**

Add to `pigeons/system_api.dart`:

```dart
enum LocationPermissionState { granted, denied, permanentlyDenied }

class ImageMetadataResult {
  ImageMetadataResult({
    required this.width,
    required this.height,
    required this.fileSizeBytes,
    required this.mimeType,
    this.latitude,
    this.longitude,
  });

  int width;
  int height;
  int fileSizeBytes;
  String mimeType;
  double? latitude;
  double? longitude;
}
```

Add these host methods before `requestCurrentLocation`:

```dart
LocationPermissionState getLocationPermissionState();

@async
LocationPermissionState requestLocationPermission();

void openApplicationSettings();

@async
ImageMetadataResult inspectImage(String path);
```

Run:

```powershell
dart run pigeon --input pigeons/system_api.dart
./gradlew.bat :sitemark_system_api:compileDebugKotlin
```

Expected: Kotlin compile FAIL until `AndroidSystemApi` implements the new methods.

- [ ] **Step 2: Add AndroidX ExifInterface and failing Kotlin tests**

Add to plugin dependencies:

```kotlin
implementation("androidx.exifinterface:exifinterface:1.4.2")
```

Add tests proving current location no longer owns permission prompting and metadata reads GPS:

```kotlin
@Test
fun currentLocationWithoutPermissionReturnsDeniedWithoutRequestingPermission() {
    val api = AndroidSystemApi(context)
    var outcome: LocationOutcome? = null
    api.requestCurrentLocation(1_000) { result ->
        outcome = result.getOrThrow().outcome
    }
    assertEquals(LocationOutcome.PERMISSION_DENIED, outcome)
}

@Test
fun permissionStateIsGrantedWhenEitherForegroundPermissionExists() {
    `when`(context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION))
        .thenReturn(PackageManager.PERMISSION_GRANTED)
    val api = AndroidSystemApi(context)
    assertEquals(LocationPermissionState.GRANTED, api.getLocationPermissionState())
}
```

Inject a fake metadata reader and assert the API returns its typed result:

```kotlin
@Test
fun inspectImageReturnsReaderMetadata() {
    val privateFile = kotlin.io.path.createTempFile(suffix = ".jpg").toFile()
    privateFile.writeBytes(byteArrayOf(1, 2, 3))
    `when`(context.dataDir).thenReturn(privateFile.parentFile)
    val reader = mock(ImageMetadataReader::class.java)
    `when`(reader.read(privateFile.canonicalFile)).thenReturn(
        ImageMetadataResult(4000, 3000, 3, "image/jpeg", 24.513, 117.6471),
    )
    val api = AndroidSystemApi(context, reader)

    val result = api.inspectImageForTest(privateFile.absolutePath)

    assertEquals(4000L, result.width)
    assertEquals(24.513, result.latitude!!, 0.000001)
}
```

- [ ] **Step 3: Implement explicit permission-state methods**

Use a separate permission callback; `requestCurrentLocation` must never call `requestPermissions`:

```kotlin
private var permissionCallback: ((Result<LocationPermissionState>) -> Unit)? = null

override fun getLocationPermissionState(): LocationPermissionState {
    if (hasLocationPermission()) return LocationPermissionState.GRANTED
    val asked = preferences.getBoolean(KEY_LOCATION_PERMISSION_REQUESTED, false)
    val canExplain = activity?.shouldShowRequestPermissionRationale(
        Manifest.permission.ACCESS_FINE_LOCATION,
    ) == true
    return if (asked && !canExplain) {
        LocationPermissionState.PERMANENTLY_DENIED
    } else {
        LocationPermissionState.DENIED
    }
}

override fun requestLocationPermission(
    callback: (Result<LocationPermissionState>) -> Unit,
) {
    if (hasLocationPermission()) {
        callback(Result.success(LocationPermissionState.GRANTED))
        return
    }
    val foreground = requireActivity()
    permissionCallback = callback
    preferences.edit().putBoolean(KEY_LOCATION_PERMISSION_REQUESTED, true).apply()
    foreground.requestPermissions(
        arrayOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        ),
        REQUEST_LOCATION_PERMISSION,
    )
}

fun onLocationPermissionResult() {
    val callback = permissionCallback ?: return
    permissionCallback = null
    callback(Result.success(getLocationPermissionState()))
}
```

At the start of `requestCurrentLocation`, replace the current permission branch with:

```kotlin
if (!hasLocationPermission()) {
    finishLocation(
        LocationResult(
            LocationOutcome.PERMISSION_DENIED,
            null, null, null, null, null,
        ),
    )
    return
}
```

Implement settings navigation with the package URI:

```kotlin
override fun openApplicationSettings() {
    val intent = Intent(
        android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
        Uri.fromParts("package", context.packageName, null),
    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    context.startActivity(intent)
}
```

- [ ] **Step 4: Implement private image metadata inspection**

Create a testable reader:

```kotlin
fun interface ImageMetadataReader {
    fun read(file: File): ImageMetadataResult
}

internal class AndroidXImageMetadataReader : ImageMetadataReader {
    override fun read(file: File): ImageMetadataResult {
        val exif = ExifInterface(file)
        val bounds = android.graphics.BitmapFactory.Options().apply {
            inJustDecodeBounds = true
        }
        android.graphics.BitmapFactory.decodeFile(file.absolutePath, bounds)
        val latLong = FloatArray(2)
        val hasGps = exif.getLatLong(latLong)
        val latitude = if (hasGps) latLong[0].toDouble() else null
        val longitude = if (hasGps) latLong[1].toDouble() else null
        val validGps = latitude != null && longitude != null &&
            latitude in -90.0..90.0 && longitude in -180.0..180.0
        return ImageMetadataResult(
            width = bounds.outWidth.coerceAtLeast(0).toLong(),
            height = bounds.outHeight.coerceAtLeast(0).toLong(),
            fileSizeBytes = file.length(),
            mimeType = bounds.outMimeType ?: "image/jpeg",
            latitude = if (validGps) latitude else null,
            longitude = if (validGps) longitude else null,
        )
    }
}
```

Inject it into `AndroidSystemApi`:

```kotlin
class AndroidSystemApi(
    private val context: Context,
    private val metadataReader: ImageMetadataReader = AndroidXImageMetadataReader(),
) : SiteMarkSystemApi {
```

Use the IO executor and validated private file:

```kotlin
override fun inspectImage(
    path: String,
    callback: (Result<ImageMetadataResult>) -> Unit,
) {
    ioExecutor.execute {
        val result = runCatching {
            val file = validatedPrivateFile(path)
            metadataReader.read(file)
        }
        mainHandler.post { callback(result) }
    }
}
```

Add `inspectImageForTest(path) = metadataReader.read(validatedPrivateFile(path))` as the internal synchronous unit-test adapter.

- [ ] **Step 5: Regenerate and run platform tests**

```powershell
dart run pigeon --input pigeons/system_api.dart
./gradlew.bat :sitemark_system_api:testDebugUnitTest
dart format pigeons packages/sitemark_system_api/lib
```

Expected: Kotlin tests PASS; generated Dart/Kotlin matches the source.

- [ ] **Step 6: Commit the platform contract**

```powershell
git add pigeons packages/sitemark_system_api
git commit -m "feat: separate location permission and read EXIF"
```

### Task 2: Expose the Permission and Metadata Contract to Dart

**Files:**
- Modify: `lib/platform/platform_services.dart`
- Modify: `test/platform/platform_services_test.dart`
- Modify: all `PlatformServices` fakes under `test/**`.

**Interfaces:**
- Consumes: Pigeon APIs from Task 1.
- Produces: matching methods on `PlatformServices`.

- [ ] **Step 1: Add failing bridge tests**

Use the existing fake Pigeon API pattern to assert each call delegates and maps its result:

```dart
class _FakeSiteMarkSystemApi extends SiteMarkSystemApi {
  ImageMetadataResult? metadata;

  @override
  Future<ImageMetadataResult> inspectImage(String path) async => metadata!;
}

test('inspectImage delegates private metadata inspection', () async {
  final api = _FakeSiteMarkSystemApi()
    ..metadata = ImageMetadataResult(
      width: 4000,
      height: 3000,
      fileSizeBytes: 123456,
      mimeType: 'image/jpeg',
      latitude: 24.513,
      longitude: 117.6471,
    );
  final services = PigeonPlatformServices(api: api);

  final result = await services.inspectImage('/private/photo.jpg');

  expect(result.width, 4000);
  expect(result.latitude, 24.513);
});
```

- [ ] **Step 2: Extend `PlatformServices` and its production adapter**

Add:

```dart
Future<LocationPermissionState> getLocationPermissionState();
Future<LocationPermissionState> requestLocationPermission();
Future<void> openApplicationSettings();
Future<ImageMetadataResult> inspectImage(String path);
```

Implement each with one direct `_api` call. Add deterministic implementations to every fake: default permission `denied`, default metadata with zero GPS, and no-op settings launch.

- [ ] **Step 3: Run bridge and compile tests**

```powershell
dart format lib/platform test
flutter test test/platform/platform_services_test.dart
flutter analyze
```

Expected: bridge tests PASS and all fakes implement the expanded interface.

- [ ] **Step 4: Commit the Dart bridge**

```powershell
git add lib/platform/platform_services.dart test
git commit -m "feat: expose location permission and image metadata"
```

### Task 3: Implement Non-Blocking Permission UX

**Files:**
- Create: `lib/workflow/location_permission_service.dart`
- Create: `test/workflow/location_permission_service_test.dart`
- Create: `lib/features/capture/location_permission_prompt.dart`
- Modify: `lib/features/capture/capture_form_screen.dart`
- Modify: `lib/features/settings/global_settings_screen.dart`
- Modify: `lib/l10n/app_strings.dart`
- Modify: `lib/app.dart`
- Modify: `test/widget_test.dart`, `test/features/settings/global_settings_screen_test.dart`.

**Interfaces:**
- Produces: `LocationPermissionViewState(permission, showExplanation, openSettings)`
- Produces: `LocationPermissionService.load/request/dismiss/openSettings`
- Produces: `CaptureDraft.useLocationFallback: bool`

- [ ] **Step 1: Write failing service tests**

```dart
test('granted permission never shows the explanation', () async {
  platform.permissionState = LocationPermissionState.granted;
  final state = await service.load();
  expect(state.showExplanation, isFalse);
  expect(state.locationEnabled, isTrue);
});

test('dismissed denied permission stays hidden after reload', () async {
  platform.permissionState = LocationPermissionState.denied;
  await service.dismiss();
  final state = await service.load();
  expect(state.showExplanation, isFalse);
  expect((await database.getAppSettings()).locationPermissionPromptDismissed,
      isTrue);
});
```

- [ ] **Step 2: Implement the service state machine**

```dart
class LocationPermissionViewState {
  const LocationPermissionViewState({
    required this.permission,
    required this.showExplanation,
  });

  final LocationPermissionState permission;
  final bool showExplanation;
  bool get locationEnabled => permission == LocationPermissionState.granted;
  bool get openSettings =>
      permission == LocationPermissionState.permanentlyDenied;
}

class LocationPermissionService {
  const LocationPermissionService({required this.database, required this.platform});
  final AppDatabase database;
  final PlatformServices platform;

  Future<LocationPermissionViewState> load() async {
    final permission = await platform.getLocationPermissionState();
    final settings = await database.getAppSettings();
    return LocationPermissionViewState(
      permission: permission,
      showExplanation: permission != LocationPermissionState.granted &&
          !settings.locationPermissionPromptDismissed,
    );
  }

  Future<LocationPermissionViewState> request() async {
    final result = await platform.requestLocationPermission();
    if (result != LocationPermissionState.granted) {
      await database.updateAppSettings(
        locationPermissionPromptDismissed: true,
      );
    }
    return LocationPermissionViewState(
      permission: result,
      showExplanation: false,
    );
  }

  Future<void> dismiss() => database
      .updateAppSettings(locationPermissionPromptDismissed: true)
      .then((_) {});

  Future<void> openSettings() => platform.openApplicationSettings();
}
```

- [ ] **Step 3: Add the capture-page explanation and settings entry**

`LocationPermissionPrompt` is a `Card` with explanatory text, close icon, and an “Enable location” button. It receives callbacks and contains no platform logic.

In `CaptureFormScreen`, load permission state during initialization, refresh it on `AppLifecycleState.resumed`, and only include the card when `showExplanation` is true. Pass `permission == granted` into the draft:

```dart
useLocationFallback: _permissionState?.locationEnabled ?? false,
```

In global settings add a `ListTile` keyed `location-permission-setting`, showing Enabled/Disabled and invoking `request()` or `openSettings()` based on the state. Add complete Chinese/English strings for the explanation, enable, disabled, enabled, and app-settings actions.

- [ ] **Step 4: Prove the UX never prompts from the capture button**

Add widget tests:

```dart
testWidgets('granted location hides explanation', (tester) async {
  platform.permissionState = LocationPermissionState.granted;
  await openCaptureForm(tester, platformOverride: platform);
  expect(find.byKey(const Key('location-permission-prompt')), findsNothing);
});

testWidgets('denied explanation requires explicit enable tap', (tester) async {
  platform.permissionState = LocationPermissionState.denied;
  await openCaptureForm(tester, platformOverride: platform);
  expect(find.byKey(const Key('location-permission-prompt')), findsOneWidget);
  expect(platform.permissionRequestCount, 0);
  await tester.tap(find.byKey(const Key('capture-button')));
  await tester.pump();
  expect(platform.permissionRequestCount, 0);
});
```

Extend the existing `openCaptureForm` widget-test helper with `_WidgetTestPlatformServices? platformOverride`, use `platformOverride ?? _WidgetTestPlatformServices()`, and expose `permissionState`/`permissionRequestCount` on that fake.

- [ ] **Step 5: Run tests and commit**

```powershell
dart format lib test
flutter test test/workflow/location_permission_service_test.dart test/widget_test.dart test/features/settings/global_settings_screen_test.dart
flutter analyze
git add lib test
git commit -m "feat: add non-blocking location permission UX"
```

### Task 4: Coordinate EXIF, Fallback Location, and Background Enqueue

**Files:**
- Create: `lib/workflow/capture_location_coordinator.dart`
- Create: `test/workflow/capture_location_coordinator_test.dart`
- Modify: `lib/workflow/capture_workflow.dart`
- Modify: `lib/workflow/app_startup_recovery.dart`
- Modify: `lib/background/capture_background_scheduler.dart`
- Modify: `lib/workflow/capture_processor.dart`
- Modify: `lib/data/app_database.dart`, generated Drift output.
- Modify: `lib/app.dart` and related tests.

**Interfaces:**
- Produces: `CaptureLocationCoordinator.begin(...)`
- Produces: `CaptureLocationCoordinator.resolve(...)`
- Produces: `CaptureLocationCoordinator.reconcilePendingLocations()`
- Produces: `AppDatabase.capturesAwaitingLocationResolution()`

- [ ] **Step 1: Write coordinator source-priority tests**

Cover all three branches:

```dart
test('EXIF GPS wins and enqueues without waiting for fallback', () async {
  platform.metadata = ImageMetadataResult(
    width: 4000, height: 3000, fileSizeBytes: 10,
    mimeType: 'image/jpeg', latitude: 24.5, longitude: 117.6,
  );
  final never = Completer<LocationResult>().future;

  await coordinator.resolve('capture-1', fallback: never, enqueue: true);

  final row = await database.captureById('capture-1');
  expect(row?.latitude, 24.5);
  expect(row?.locationOutcome, 'exif');
  expect(scheduler.enqueuedIds, ['capture-1']);
});

test('missing EXIF uses the record-scoped fallback', () async {
  platform.metadata = ImageMetadataResult(
    width: 4000, height: 3000, fileSizeBytes: 10,
    mimeType: 'image/jpeg',
  );
  await coordinator.resolve(
    'capture-1',
    fallback: Future.value(LocationResult(
      outcome: LocationOutcome.precise,
      latitude: 24.513,
      longitude: 117.6471,
      accuracyMeters: 8,
    )),
    enqueue: true,
  );
  expect((await database.captureById('capture-1'))?.locationOutcome, 'precise');
});

test('no EXIF and no fallback becomes unavailable and still enqueues', () async {
  platform.metadata = ImageMetadataResult(
    width: 4000, height: 3000, fileSizeBytes: 10,
    mimeType: 'image/jpeg',
  );
  await coordinator.resolve('capture-1', fallback: null, enqueue: true);
  final row = await database.captureById('capture-1');
  expect(row?.locationResolution, 'unavailable');
  expect(scheduler.enqueuedIds, ['capture-1']);
});
```

- [ ] **Step 2: Implement `CaptureLocationCoordinator`**

```dart
final class CaptureLocationCoordinator {
  const CaptureLocationCoordinator({
    required this.database,
    required this.platform,
    required this.scheduler,
  });

  final AppDatabase database;
  final PlatformServices platform;
  final CaptureBackgroundScheduler scheduler;

  void begin(String captureId, {Future<LocationResult>? fallback}) {
    unawaited(
      resolve(captureId, fallback: fallback, enqueue: true)
          .catchError((Object _) {}),
    );
  }

  Future<void> resolve(
    String captureId, {
    Future<LocationResult>? fallback,
    required bool enqueue,
  }) async {
    final record = await database.captureById(captureId);
    if (record == null || record.locationResolution != 'pending') return;
    try {
      final metadata = await platform.inspectImage(record.originalPath);
      if (_validGps(metadata.latitude, metadata.longitude)) {
        await database.resolveCaptureLocation(
          captureId: captureId,
          resolution: 'resolved',
          outcome: 'exif',
          latitude: metadata.latitude,
          longitude: metadata.longitude,
        );
      } else {
        await _persistFallback(captureId, fallback == null ? null : await fallback);
      }
    } catch (_) {
      await _persistFallback(captureId, fallback == null ? null : await fallback);
    }
    if (enqueue) await scheduler.enqueue(captureId);
  }

  Future<void> reconcilePendingLocations() async {
    for (final row in await database.capturesAwaitingLocationResolution()) {
      await resolve(row.id, fallback: null, enqueue: false);
    }
  }
}
```

Implement `_validGps` with latitude `[-90, 90]` and longitude `[-180, 180]`. `_persistFallback` accepts only precise/approximate results with non-null valid coordinates; every other result writes `resolution: 'unavailable'` and the original `outcome.name` or `unavailable`.

- [ ] **Step 3: Prove `launchCamera` runs before location completion**

In `capture_workflow_test.dart`, add a `Completer<LocationResult>` and ordered event log to the fake. Start capture without completing location, pump the microtask queue, and assert:

```dart
expect(platform.events, containsAllInOrder([
  'requestCurrentLocation',
  'createCameraTarget',
  'launchCamera',
]));
expect(platform.locationCompleter.isCompleted, isFalse);
```

After the fake camera returns, assert the workflow result is `queued` before the location completer resolves. Complete location afterward and assert the coordinator enqueues exactly once.

- [ ] **Step 4: Refactor the foreground workflow**

Add `useLocationFallback` to `CaptureDraft`. At the beginning of `capture`:

```dart
final locationFuture = draft.useLocationFallback ? _safeLocation() : null;
```

Delete `final location = await _safeLocation()`. Create the pending row with no coordinates, `locationResolution: 'pending'`, and after camera success:

```dart
final captured = await database.markCaptured(
  captureId: captureId,
  capturedAt: _now(),
);
await platform.finishCameraCapture(captureId, true);
locationCoordinator.begin(captureId, fallback: locationFuture);
return CaptureWorkflowResult(
  outcome: CaptureWorkflowOutcome.queued,
  capture: captured,
);
```

Recovered captures call the same coordinator with `fallback: null`.

- [ ] **Step 5: Make startup and WorkManager honor location resolution**

Add `capturesAwaitingLocationResolution()` for captured rows with `locationResolution == 'pending'`. Filter `capturesAwaitingProcessing()` to `locationResolution != 'pending'`.

Change `AppStartupRecovery` order to:

```dart
await recoverCamera();
await resolveLocations();
await reconcileQueue();
```

As a defensive guard, make `CaptureProcessor.process` return `CaptureProcessResult.retry` when a queued record still has `locationResolution == 'pending'`. Place this guard before `incrementProcessingAttempts` so a coordination race cannot consume the three-attempt render budget.

- [ ] **Step 6: Wire providers and update recovery tests**

Add providers for `LocationPermissionService` and `CaptureLocationCoordinator`. Inject the coordinator into `CaptureWorkflow`. Update `MyApp` overrides so widget tests can provide fakes.

Update `app_startup_recovery_test.dart` to assert the order `camera`, `location`, `queue`, and scheduler tests to prove pending-location rows are not enqueued early.

- [ ] **Step 7: Run the focused workflow suite and commit**

```powershell
dart run build_runner build --delete-conflicting-outputs
dart format lib test
flutter test test/workflow/capture_location_coordinator_test.dart test/workflow/capture_workflow_test.dart test/workflow/app_startup_recovery_test.dart test/background/capture_background_scheduler_test.dart test/workflow/capture_processor_test.dart test/widget_test.dart
flutter analyze
git add lib test
git commit -m "fix: launch camera before location resolves"
```

### Task 5: Camera/Location Verification Gate

**Files:**
- Verify only.

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces: verified fast-launch and location-coordination behavior.

- [ ] **Step 1: Run generated-code and automated checks**

```powershell
dart run pigeon --input pigeons/system_api.dart
dart run build_runner build --delete-conflicting-outputs
./gradlew.bat :sitemark_system_api:testDebugUnitTest
flutter test
flutter analyze
git diff --check
```

Expected: all checks PASS and generation leaves no unexplained diff.

- [ ] **Step 2: Record the device acceptance procedure for execution**

On the target phone, measure 10 launches each with location warm, cold, disabled, and denied. Record `tap → launchCamera` app timing and visible system-camera timing. Acceptance is no 5–10 second app wait, app-side P90 ≤300ms, and successful continued shooting while prior records resolve location/render in the background.
