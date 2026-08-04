## Commit list

776f7c3 feat: add location settings sub-page

## Diff stat

 .../settings/sections/location_section_screen.dart | 125 +++++++++++++++++
 .../sections/location_section_screen_test.dart     | 156 +++++++++++++++++++++
 2 files changed, 281 insertions(+)

## Full diff

diff --git a/lib/features/settings/sections/location_section_screen.dart b/lib/features/settings/sections/location_section_screen.dart
new file mode 100644
index 0000000..60cc117
--- /dev/null
+++ b/lib/features/settings/sections/location_section_screen.dart
@@ -0,0 +1,125 @@
+import 'package:flutter/material.dart';
+import 'package:flutter_riverpod/flutter_riverpod.dart';
+import 'package:sitemark/app.dart';
+import 'package:sitemark/features/settings/settings_section_scaffold.dart';
+import 'package:sitemark/l10n/app_strings.dart';
+import 'package:sitemark/workflow/location_permission_service.dart';
+import 'package:sitemark_system_api/sitemark_system_api.dart';
+
+class LocationSectionScreen extends ConsumerStatefulWidget {
+  const LocationSectionScreen({super.key});
+
+  @override
+  ConsumerState<LocationSectionScreen> createState() =>
+      _LocationSectionScreenState();
+}
+
+class _LocationSectionScreenState extends ConsumerState<LocationSectionScreen>
+    with WidgetsBindingObserver {
+  /// 缓存定位权限的视图状态。初始化时加载，并在 App 恢复前台时刷新，
+  /// 以反映用户在系统对话框或系统设置中修改的权限。
+  /// `null` 表示首次加载尚未完成。
+  LocationPermissionViewState? _permissionState;
+
+  @override
+  void initState() {
+    super.initState();
+    _loadPermission();
+    WidgetsBinding.instance.addObserver(this);
+  }
+
+  @override
+  void didChangeAppLifecycleState(AppLifecycleState state) {
+    super.didChangeAppLifecycleState(state);
+    // 用户从系统权限对话框或系统设置返回后刷新 tile，以反映新权限状态。
+    if (state == AppLifecycleState.resumed) {
+      _loadPermission();
+    }
+  }
+
+  Future<void> _loadPermission() async {
+    try {
+      final state = await ref.read(locationPermissionServiceProvider).load();
+      if (!mounted) return;
+      setState(() => _permissionState = state);
+    } catch (_) {
+      // 平台通道不可用（例如没有平台 override 的单测环境）。
+      // 默认渲染为 disabled 且不显示 explanation 的状态，避免无限转圈。
+      if (!mounted) return;
+      setState(() {
+        _permissionState = const LocationPermissionViewState(
+          permission: LocationPermissionState.denied,
+          showExplanation: false,
+        );
+      });
+    }
+  }
+
+  Future<void> _onLocationTapped() async {
+    final service = ref.read(locationPermissionServiceProvider);
+    final current = _permissionState;
+    if (current == null || current.locationEnabled) return;
+    if (current.openSettings) {
+      // 跳转系统设置；resumed 生命周期回调会在用户返回时刷新 tile。
+      await service.openSettings();
+      return;
+    }
+    final state = await service.request();
+    if (!mounted) return;
+    setState(() => _permissionState = state);
+  }
+
+  @override
+  void dispose() {
+    WidgetsBinding.instance.removeObserver(this);
+    super.dispose();
+  }
+
+  @override
+  Widget build(BuildContext context) {
+    final strings = AppStrings.of(context);
+    return SettingsSectionScaffold(
+      title: strings.locationLabel,
+      body: _LocationPermissionTile(
+        state: _permissionState,
+        onTap: _onLocationTapped,
+      ),
+    );
+  }
+}
+
+/// 展示当前定位权限状态的 ListTile。权限未授予时点击会发起请求
+/// （或当平台报告 `permanentlyDenied` 时打开系统设置）。
+class _LocationPermissionTile extends StatelessWidget {
+  const _LocationPermissionTile({required this.state, required this.onTap});
+
+  final LocationPermissionViewState? state;
+  final VoidCallback onTap;
+
+  @override
+  Widget build(BuildContext context) {
+    final strings = AppStrings.of(context);
+    final current = state;
+    final enabled = current?.locationEnabled ?? false;
+    return ListTile(
+      key: const Key('location-permission-setting'),
+      leading: const Icon(Icons.location_on_outlined),
+      title: Text(strings.locationLabel),
+      trailing: current == null
+          ? const SizedBox(
+              width: 16,
+              height: 16,
+              child: CircularProgressIndicator(strokeWidth: 2),
+            )
+          : Text(enabled ? strings.enabled : strings.disabled),
+      subtitle: current != null && !enabled
+          ? Text(
+              current.openSettings
+                  ? strings.locationPermanentlyDeniedHint
+                  : strings.locationDisabledHint,
+            )
+          : null,
+      onTap: current == null || enabled ? null : onTap,
+    );
+  }
+}
diff --git a/test/features/settings/sections/location_section_screen_test.dart b/test/features/settings/sections/location_section_screen_test.dart
new file mode 100644
index 0000000..5b8a8f7
--- /dev/null
+++ b/test/features/settings/sections/location_section_screen_test.dart
@@ -0,0 +1,156 @@
+import 'package:drift/native.dart';
+import 'package:flutter/material.dart';
+import 'package:flutter_localizations/flutter_localizations.dart';
+import 'package:flutter_riverpod/flutter_riverpod.dart';
+import 'package:flutter_test/flutter_test.dart';
+import 'package:sitemark/app.dart';
+import 'package:sitemark/data/app_database.dart';
+import 'package:sitemark/features/settings/sections/location_section_screen.dart';
+import 'package:sitemark/l10n/app_strings.dart';
+import 'package:sitemark/platform/platform_services.dart';
+import 'package:sitemark_system_api/sitemark_system_api.dart';
+
+void main() {
+  late AppDatabase database;
+
+  setUp(() {
+    database = AppDatabase.forTesting(NativeDatabase.memory());
+  });
+
+  tearDown(() async {
+    await database.close();
+  });
+
+  Future<void> pumpScreen(
+    WidgetTester tester, {
+    required _SettingsTestPlatformServices platform,
+  }) async {
+    await database.getAppSettings();
+    await tester.pumpWidget(
+      ProviderScope(
+        overrides: [
+          databaseProvider.overrideWithValue(database),
+          platformServicesProvider.overrideWithValue(platform),
+        ],
+        child: MaterialApp(
+          locale: const Locale('zh'),
+          supportedLocales: AppStrings.supportedLocales,
+          localizationsDelegates: const [
+            AppStrings.delegate,
+            GlobalMaterialLocalizations.delegate,
+            GlobalWidgetsLocalizations.delegate,
+            GlobalCupertinoLocalizations.delegate,
+          ],
+          home: const LocationSectionScreen(),
+        ),
+      ),
+    );
+    await tester.pumpAndSettle();
+  }
+
+  testWidgets('location tile shows disabled when permission is denied', (
+    tester,
+  ) async {
+    await pumpScreen(
+      tester,
+      platform: _SettingsTestPlatformServices(
+        permissionState: LocationPermissionState.denied,
+      ),
+    );
+    expect(find.text('未开启'), findsOneWidget);
+  });
+
+  testWidgets('location tile shows enabled when permission is granted', (
+    tester,
+  ) async {
+    await pumpScreen(
+      tester,
+      platform: _SettingsTestPlatformServices(
+        permissionState: LocationPermissionState.granted,
+      ),
+    );
+    expect(find.text('已开启'), findsOneWidget);
+  });
+
+  testWidgets('tapping the disabled location tile requests permission', (
+    tester,
+  ) async {
+    final platform = _SettingsTestPlatformServices(
+      permissionState: LocationPermissionState.denied,
+      requestResult: LocationPermissionState.denied,
+    );
+    await pumpScreen(tester, platform: platform);
+    await tester.tap(find.byKey(const Key('location-permission-setting')));
+    await tester.pumpAndSettle();
+
+    expect(platform.requestLocationPermissionCount, 1);
+    final settings = await database.getAppSettings();
+    expect(settings.locationPermissionPromptDismissed, isTrue);
+  });
+}
+
+// Verbatim copy from global_settings_screen_test.dart — needed because
+// PlatformServices is a large interface and the full stub is already filled in.
+class _SettingsTestPlatformServices implements PlatformServices {
+  _SettingsTestPlatformServices({
+    this.permissionState = LocationPermissionState.denied,
+    this.requestResult = LocationPermissionState.denied,
+  });
+
+  LocationPermissionState permissionState;
+  LocationPermissionState requestResult;
+  int requestLocationPermissionCount = 0;
+  int openApplicationSettingsCount = 0;
+
+  @override
+  Future<LocationPermissionState> getLocationPermissionState() async =>
+      permissionState;
+
+  @override
+  Future<LocationPermissionState> requestLocationPermission() async {
+    requestLocationPermissionCount++;
+    return requestResult;
+  }
+
+  @override
+  Future<void> openApplicationSettings() async {
+    openApplicationSettingsCount++;
+  }
+
+  @override
+  Future<String> createCameraTarget(String captureId) async =>
+      '/private/$captureId.jpg';
+
+  @override
+  Future<CameraCaptureResult> launchCamera(String captureId) async =>
+      CameraCaptureResult(
+        outcome: CameraOutcome.captured,
+        outputPath: '/private/$captureId.jpg',
+      );
+
+  @override
+  Future<RecoveredCameraCapture?> recoverCameraCapture() async => null;
+
+  @override
+  Future<void> finishCameraCapture(String captureId, bool keepOriginal) async {}
+
+  @override
+  Future<LocationResult> requestCurrentLocation(int timeoutMillis) async =>
+      LocationResult(outcome: LocationOutcome.unavailable);
+
+  @override
+  Future<String> publishJpeg(String sourcePath, String displayName) async =>
+      'content://media/site-mark/1';
+
+  @override
+  Future<void> deletePublishedImage(String contentUri) async {}
+
+  @override
+  Future<ImageMetadataResult> inspectImage(String path) async =>
+      ImageMetadataResult(
+        width: 0,
+        height: 0,
+        fileSizeBytes: 0,
+        mimeType: 'image/jpeg',
+      );
+}
