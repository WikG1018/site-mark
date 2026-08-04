1cf5a48 feat: add watermark defaults settings sub-page

--- diff stat ---

 .../watermark_defaults_section_screen.dart         | 200 +++++++++++++++++++++
 .../watermark_defaults_section_screen_test.dart    |  93 ++++++++++
 2 files changed, 293 insertions(+)

--- full diff (U10) ---

diff --git a/lib/features/settings/sections/watermark_defaults_section_screen.dart b/lib/features/settings/sections/watermark_defaults_section_screen.dart
new file mode 100644
index 0000000..f54d11e
--- /dev/null
+++ b/lib/features/settings/sections/watermark_defaults_section_screen.dart
@@ -0,0 +1,200 @@
+// lib/features/settings/sections/watermark_defaults_section_screen.dart
+import 'package:flutter/material.dart';
+import 'package:flutter_riverpod/flutter_riverpod.dart';
+import 'package:sitemark/features/settings/app_setting_controller.dart';
+import 'package:sitemark/features/settings/settings_section_scaffold.dart';
+import 'package:sitemark/l10n/app_strings.dart';
+
+class WatermarkDefaultsSectionScreen extends ConsumerStatefulWidget {
+  const WatermarkDefaultsSectionScreen({super.key});
+
+  @override
+  ConsumerState<WatermarkDefaultsSectionScreen> createState() =>
+      _WatermarkDefaultsSectionScreenState();
+}
+
+class _WatermarkDefaultsSectionScreenState
+    extends ConsumerState<WatermarkDefaultsSectionScreen> {
+  double? _dragValue;
+  double? _fontScaleDragValue;
+
+  @override
+  Widget build(BuildContext context) {
+    final strings = AppStrings.of(context);
+    final asyncSettings = ref.watch(appSettingControllerProvider);
+    final settings = asyncSettings.value;
+    if (settings == null) {
+      return SettingsSectionScaffold(
+        title: strings.newProjectDefaults,
+        body: const Center(child: CircularProgressIndicator()),
+      );
+    }
+    return SettingsSectionScaffold(
+      title: strings.newProjectDefaults,
+      body: Column(
+        crossAxisAlignment: CrossAxisAlignment.stretch,
+        children: [
+          // Position
+          Text(strings.watermarkPosition,
+              style: Theme.of(context).textTheme.titleMedium),
+          const SizedBox(height: 8),
+          SegmentedButton<String>(
+            key: const Key('default-position-segmented'),
+            style: segmentTapTargetStyle,
+            segments: [
+              ButtonSegment(
+                value: 'bottomLeft',
+                label: Text(strings.bottomLeft,
+                    key: const Key('default-position-bottomLeft')),
+              ),
+              ButtonSegment(
+                value: 'bottomRight',
+                label: Text(strings.bottomRight,
+                    key: const Key('default-position-bottomRight')),
+              ),
+            ],
+            selected: {settings.defaultWatermarkPosition},
+            onSelectionChanged: (selection) => ref
+                .read(appSettingControllerProvider.notifier)
+                .update((s) =>
+                    s.copyWith(defaultWatermarkPosition: selection.single)),
+          ),
+          const SizedBox(height: 24),
+          // Opacity slider (migrate _dragValue logic)
+          Builder(builder: (context) {
+            final opacity =
+                (_dragValue ?? settings.defaultWatermarkOpacity).clamp(0.20, 0.95);
+            final percent = (opacity * 100).round();
+            return Column(
+              crossAxisAlignment: CrossAxisAlignment.stretch,
+              children: [
+                Row(children: [
+                  Expanded(
+                    child: Text(strings.watermarkOpacity,
+                        style: Theme.of(context).textTheme.titleMedium),
+                  ),
+                  Text('$percent%'),
+                ]),
+                Slider(
+                  key: const Key('opacity-slider'),
+                  value: opacity,
+                  min: 0.20,
+                  max: 0.95,
+                  divisions: 75,
+                  label: '$percent%',
+                  onChanged: (value) =>
+                      setState(() => _dragValue = value),
+                  onChangeEnd: (value) {
+                    ref
+                        .read(appSettingControllerProvider.notifier)
+                        .update((s) =>
+                            s.copyWith(defaultWatermarkOpacity: value));
+                    setState(() => _dragValue = null);
+                  },
+                ),
+              ],
+            );
+          }),
+          const SizedBox(height: 8),
+          Text(strings.opacityHint,
+              style: Theme.of(context).textTheme.bodySmall),
+          const SizedBox(height: 20),
+          // Font scale slider (migrate _fontScaleDragValue logic)
+          Builder(builder: (context) {
+            final fontScale =
+                (_fontScaleDragValue ?? settings.defaultWatermarkFontScale)
+                    .clamp(0.80, 1.60);
+            final percent = (fontScale * 100).round();
+            return Column(
+              crossAxisAlignment: CrossAxisAlignment.stretch,
+              children: [
+                Row(children: [
+                  Expanded(
+                    child: Text(strings.watermarkFontSize,
+                        style: Theme.of(context).textTheme.titleMedium),
+                  ),
+                  Text('$percent%'),
+                ]),
+                Slider(
+                  key: const Key('default-font-scale-slider'),
+                  value: fontScale,
+                  min: 0.80,
+                  max: 1.60,
+                  divisions: 16,
+                  label: '$percent%',
+                  onChanged: (value) =>
+                      setState(() => _fontScaleDragValue = value),
+                  onChangeEnd: (value) {
+                    ref
+                        .read(appSettingControllerProvider.notifier)
+                        .update((s) =>
+                            s.copyWith(defaultWatermarkFontScale: value));
+                    setState(() => _fontScaleDragValue = null);
+                  },
+                ),
+              ],
+            );
+          }),
+          const SizedBox(height: 8),
+          Text(strings.fontScaleHint,
+              style: Theme.of(context).textTheme.bodySmall),
+          const SizedBox(height: 20),
+          // Accent color
+          Text(strings.accentColor,
+              style: Theme.of(context).textTheme.titleMedium),
+          const SizedBox(height: 12),
+          Wrap(
+            spacing: 10,
+            runSpacing: 10,
+            children: [
+              for (final swatch in accentSwatches)
+                _AccentChoice(
+                  choiceKey: swatch.key,
+                  colorArgb: swatch.argb,
+                  selected:
+                      settings.defaultWatermarkAccentColorArgb == swatch.argb,
+                  onSelected: () => ref
+                      .read(appSettingControllerProvider.notifier)
+                      .update((s) => s.copyWith(
+                          defaultWatermarkAccentColorArgb: swatch.argb)),
+                ),
+            ],
+          ),
+        ],
+      ),
+    );
+  }
+}
+
+class _AccentChoice extends StatelessWidget {
+  const _AccentChoice({
+    required this.choiceKey,
+    required this.colorArgb,
+    required this.selected,
+    required this.onSelected,
+  });
+
+  final Key choiceKey;
+  final int colorArgb;
+  final bool selected;
+  final VoidCallback onSelected;
+
+  @override
+  Widget build(BuildContext context) {
+    return ChoiceChip(
+      key: choiceKey,
+      selected: selected,
+      avatar: CircleAvatar(backgroundColor: Color(colorArgb)),
+      label: Text(_label(context, colorArgb)),
+      onSelected: (_) => onSelected(),
+    );
+  }
+
+  String _label(BuildContext context, int argb) {
+    final strings = AppStrings.of(context);
+    if (argb == 0xff37c58b) return strings.green;
+    if (argb == 0xff1565c0) return strings.blue;
+    if (argb == 0xffef6c00) return strings.orange;
+    return '';
+  }
+}
diff --git a/test/features/settings/sections/watermark_defaults_section_screen_test.dart b/test/features/settings/sections/watermark_defaults_section_screen_test.dart
new file mode 100644
index 0000000..f7bedbc
--- /dev/null
+++ b/test/features/settings/sections/watermark_defaults_section_screen_test.dart
@@ -0,0 +1,93 @@
+// test/features/settings/sections/watermark_defaults_section_screen_test.dart
+import 'package:drift/native.dart';
+import 'package:flutter/material.dart';
+import 'package:flutter_localizations/flutter_localizations.dart';
+import 'package:flutter_riverpod/flutter_riverpod.dart';
+import 'package:flutter_test/flutter_test.dart';
+import 'package:sitemark/app.dart';
+import 'package:sitemark/data/app_database.dart';
+import 'package:sitemark/features/settings/sections/watermark_defaults_section_screen.dart';
+import 'package:sitemark/l10n/app_strings.dart';
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
+  Future<void> pumpScreen(WidgetTester tester) async {
+    await database.getAppSettings();
+    await tester.pumpWidget(
+      ProviderScope(
+        overrides: [databaseProvider.overrideWithValue(database)],
+        child: MaterialApp(
+          locale: const Locale('zh'),
+          supportedLocales: AppStrings.supportedLocales,
+          localizationsDelegates: const [
+            AppStrings.delegate,
+            GlobalMaterialLocalizations.delegate,
+            GlobalWidgetsLocalizations.delegate,
+            GlobalCupertinoLocalizations.delegate,
+          ],
+          home: const WatermarkDefaultsSectionScreen(),
+        ),
+      ),
+    );
+    await tester.pumpAndSettle();
+  }
+
+  testWidgets('watermark position persists', (tester) async {
+    await pumpScreen(tester);
+    await tester.tap(find.byKey(const Key('default-position-bottomRight')));
+    await tester.pumpAndSettle();
+    expect(
+      (await database.getAppSettings()).defaultWatermarkPosition,
+      'bottomRight',
+    );
+  });
+
+  testWidgets('opacity slider persists on change end', (tester) async {
+    await pumpScreen(tester);
+    await tester.timedDrag(
+      find.byKey(const Key('opacity-slider')),
+      const Offset(500, 0),
+      const Duration(milliseconds: 200),
+    );
+    await tester.pumpAndSettle();
+    expect((await database.getAppSettings()).defaultWatermarkOpacity, 0.95);
+  });
+
+  testWidgets('font scale slider persists on release', (tester) async {
+    await pumpScreen(tester);
+    final slider = find.byKey(const Key('default-font-scale-slider'));
+    await tester.ensureVisible(slider);
+    await tester.pumpAndSettle();
+    await tester.timedDrag(
+      slider,
+      const Offset(500, 0),
+      const Duration(milliseconds: 200),
+    );
+    await tester.pumpAndSettle();
+    expect(
+      (await database.getAppSettings()).defaultWatermarkFontScale,
+      1.60,
+    );
+  });
+
+  testWidgets('accent swatch selection persists', (tester) async {
+    await pumpScreen(tester);
+    await tester.ensureVisible(find.byKey(const Key('accent-orange')));
+    await tester.pumpAndSettle();
+    await tester.tap(find.byKey(const Key('accent-orange')));
+    await tester.pumpAndSettle();
+    expect(
+      (await database.getAppSettings()).defaultWatermarkAccentColorArgb,
+      0xffef6c00,
+    );
+  });
+}
