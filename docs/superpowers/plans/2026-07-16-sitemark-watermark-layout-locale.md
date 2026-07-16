# SiteMark Adaptive Localized Watermark Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add user-controlled watermark font scale, render Chinese or English labels according to the capture-time locale, and size the watermark card from measured content instead of a fixed 62% width.

**Architecture:** Persist a font scale per project and snapshot a resolved locale per capture. Pass both values into the Rust renderer. Rust builds localized logical lines, wraps them within a 92% safety width, measures the final lines, then derives the smallest safe card width and height before drawing.

**Tech Stack:** Flutter/Dart, Drift schema v4, flutter_rust_bridge 2.12.0, Rust `image`/`imageproc`/`ab_glyph`, Noto Sans SC bundled font.

## Global Constraints

- Complete the foundation and camera/location plans first.
- Font scale is 0.80–1.60 in 0.05 steps; 1.00 preserves the v0.2.0 visual size.
- Global font scale only seeds new projects; changing it never mutates existing projects.
- Capture locale is the resolved UI language at capture time: only `zh` or `en`.
- Existing completed photos are not re-rendered automatically.
- Card width has no fixed percentage minimum; it is measured from text, accent strip, and padding, with a maximum near 92% of source width.
- Long content wraps and remains present; do not silently truncate whole fields.
- Do not edit Drift or FRB generated Dart by hand.

---

## File Map

- Modify: `lib/features/projects/project_watermark_settings_screen.dart` — project font-scale slider.
- Modify: `lib/features/settings/global_settings_screen.dart` — default font-scale slider.
- Modify: `lib/features/projects/project_form_screen.dart` — copy default font scale.
- Modify: `lib/features/capture/capture_form_screen.dart` — snapshot resolved locale.
- Modify: `lib/l10n/app_strings.dart` — slider labels/hints.
- Modify: `lib/workflow/capture_workflow.dart` — persist locale snapshot.
- Modify: `lib/workflow/capture_processor.dart` — send font scale and locale to Rust.
- Modify: `rust/src/api/image_core.rs` — request fields, labels, wrapping, measured layout.
- Modify: `rust/tests/core_test.rs` and in-module Rust tests.
- Regenerate: `lib/src/rust/**` through build_runner.
- Modify: database, processor, settings, and widget tests.

### Task 1: Add Font Scale to Project and Global Settings UI

**Files:**
- Modify: `lib/features/projects/project_watermark_settings_screen.dart`
- Modify: `lib/features/settings/global_settings_screen.dart`
- Modify: `lib/features/projects/project_form_screen.dart`
- Modify: `lib/l10n/app_strings.dart`
- Modify: `test/widget_test.dart`
- Modify: `test/features/settings/global_settings_screen_test.dart`

**Interfaces:**
- Consumes: schema v4 `watermarkFontScale` and `defaultWatermarkFontScale`.
- Produces: user-editable font scale in both settings surfaces.

- [ ] **Step 1: Write failing widget tests for both sliders**

Add to the project settings widget test flow:

```dart
expect(find.byKey(const Key('project-font-scale-slider')), findsOneWidget);
await tester.timedDrag(
  find.byKey(const Key('project-font-scale-slider')),
  const Offset(300, 0),
  const Duration(milliseconds: 200),
);
await tester.tap(find.text('保存'));
await tester.pumpAndSettle();
expect((await database.projectById('project-1'))?.watermarkFontScale,
    greaterThan(1.0));
```

Add to `global_settings_screen_test.dart`:

```dart
testWidgets('default font scale persists on release', (tester) async {
  await pumpSettings(tester);
  await tester.scrollUntilVisible(
    find.byKey(const Key('default-font-scale-slider')),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.timedDrag(
    find.byKey(const Key('default-font-scale-slider')),
    const Offset(500, 0),
    const Duration(milliseconds: 200),
  );
  await tester.pumpAndSettle();
  expect((await database.getAppSettings()).defaultWatermarkFontScale, 1.60);
});
```

- [ ] **Step 2: Run focused tests and verify missing controls**

```powershell
flutter test test/features/settings/global_settings_screen_test.dart --plain-name "default font scale"
flutter test test/widget_test.dart --plain-name "watermark settings"
```

Expected: FAIL because the slider keys do not exist.

- [ ] **Step 3: Implement the project slider and save path**

Add `_fontScale`, initialize it from `project.watermarkFontScale`, and insert this block before accent color:

```dart
Row(
  children: [
    Expanded(
      child: Text(
        strings.watermarkFontSize,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    ),
    Text('${(_fontScale! * 100).round()}%'),
  ],
),
Slider(
  key: const Key('project-font-scale-slider'),
  value: _fontScale!,
  min: 0.80,
  max: 1.60,
  divisions: 16,
  label: '${(_fontScale! * 100).round()}%',
  onChanged: (value) => setState(() => _fontScale = value),
),
```

Pass `fontScale: _fontScale!` to `updateProjectWatermarkSettings`.

- [ ] **Step 4: Implement the global slider and project-default copy**

Follow the existing opacity drag pattern with a separate `_fontScaleDragValue`; persist only in `onChangeEnd`:

```dart
Slider(
  key: const Key('default-font-scale-slider'),
  value: (_fontScaleDragValue ?? settings.defaultWatermarkFontScale)
      .clamp(0.80, 1.60),
  min: 0.80,
  max: 1.60,
  divisions: 16,
  onChanged: (value) => setState(() => _fontScaleDragValue = value),
  onChangeEnd: (value) {
    _apply((db) => db.updateAppSettings(defaultWatermarkFontScale: value));
    setState(() => _fontScaleDragValue = null);
  },
),
```

In `ProjectFormScreen`, pass:

```dart
watermarkFontScale: settings.defaultWatermarkFontScale,
```

Add Chinese/English `watermarkFontSize` and `fontScaleHint` strings.

- [ ] **Step 5: Run UI/data tests and commit**

```powershell
dart format lib test
flutter test test/features/settings/global_settings_screen_test.dart test/widget_test.dart test/data/app_database_test.dart
flutter analyze
git add lib test
git commit -m "feat: add watermark font size controls"
```

### Task 2: Snapshot Locale and Pass Rendering Settings

**Files:**
- Modify: `lib/features/capture/capture_form_screen.dart`
- Modify: `lib/workflow/capture_workflow.dart`
- Modify: `test/workflow/capture_workflow_test.dart`
- Modify: `test/widget_test.dart`

**Interfaces:**
- Produces: `CaptureDraft.watermarkLocaleCode`.

- [ ] **Step 1: Write failing locale-snapshot tests**

In `capture_workflow_test.dart`, capture an English draft and assert persistence:

```dart
final result = await workflow.capture(
  const CaptureDraft(
    projectId: 'project-1',
    projectName: 'East Plant',
    workLocation: 'Level 3',
    workContent: 'Duct inspection',
    photographer: 'Alex',
    useLocationFallback: false,
    watermarkLocaleCode: 'en',
  ),
);
expect(result.capture?.watermarkLocaleCode, 'en');
```

- [ ] **Step 2: Persist the resolved locale at capture creation**

Add to `CaptureDraft`:

```dart
required this.watermarkLocaleCode,
final String watermarkLocaleCode;
```

Pass it to `createPendingCapture`. In the form, resolve only the supported languages:

```dart
final language = Localizations.localeOf(context).languageCode;
final watermarkLocaleCode = language == 'en' ? 'en' : 'zh';
```

and include it in the draft. Update test drafts with explicit `zh` or `en`.

- [ ] **Step 3: Run workflow tests and commit**

```powershell
dart format lib test
flutter test test/workflow/capture_workflow_test.dart test/widget_test.dart
flutter analyze
git add lib test
git commit -m "feat: snapshot watermark locale per capture"
```

### Task 3: Implement Localized, Measured Rust Layout

**Files:**
- Modify: `rust/src/api/image_core.rs`
- Modify: `rust/tests/core_test.rs`
- Modify: `lib/workflow/capture_processor.dart`
- Modify: `test/workflow/capture_processor_test.dart`
- Regenerate: `lib/src/rust/api/image_core.dart`, `lib/src/rust/frb_generated*.dart`.

**Interfaces:**
- Consumes: `font_scale: f64`, `locale_code: String`.
- Produces: localized, wrapped display lines and measured `WatermarkLayout`.
- Produces: `RenderPhotoRequest.fontScale` and `RenderPhotoRequest.localeCode` populated from project/capture snapshots.

- [ ] **Step 1: Add failing Rust validation/localization/layout tests**

Add module tests at the bottom of `image_core.rs` so private helpers remain private:

```rust
#[cfg(test)]
mod watermark_tests {
    use super::*;

    #[test]
    fn english_labels_contain_no_fixed_chinese_labels() {
        let request = sample_request("en", 1.0, "East Plant");
        let lines = logical_watermark_lines(&request);
        let joined = lines.join("\n");
        assert!(joined.contains("Site record"));
        assert!(joined.contains("Location"));
        assert!(!joined.contains("现场记录"));
        assert!(!joined.contains("位置"));
    }

    #[test]
    fn short_content_produces_a_narrower_card_than_long_content() {
        let font = FontArc::try_from_slice(FONT_BYTES).unwrap();
        let short = layout_for_request(4000, 3000, &sample_request("zh", 1.0, "甲"), &font).unwrap();
        let long = layout_for_request(4000, 3000, &sample_request("zh", 1.0, "东区厂房通风空调系统综合改造工程"), &font).unwrap();
        assert!(short.card_width < long.card_width);
        assert!(long.card_width <= (4000.0 * 0.92) as u32);
    }

    #[test]
    fn font_scale_bounds_are_enforced() {
        assert!(validate_render_request(&sample_request("zh", 0.79, "甲")).is_err());
        assert!(validate_render_request(&sample_request("zh", 1.61, "甲")).is_err());
        assert!(validate_render_request(&sample_request("en", 1.60, "A")).is_ok());
    }

    fn sample_request(locale: &str, font_scale: f64, project: &str) -> RenderPhotoRequest {
        RenderPhotoRequest {
            source_path: "source.jpg".to_string(),
            output_path: "output.jpg".to_string(),
            project_name: project.to_string(),
            work_location: "A 区三层".to_string(),
            work_content: "风管安装检查".to_string(),
            photographer: "张工".to_string(),
            photo_number: "SM-20260716-001".to_string(),
            captured_at: "2026-07-16 09:32:18 +08:00".to_string(),
            address: None,
            coordinates: None,
            notes: None,
            position: WatermarkPosition::BottomLeft,
            opacity: 0.78,
            accent_color_argb: 0xff37c58b,
            font_scale,
            locale_code: locale.to_string(),
        }
    }
}
```

Update every integration-test `RenderPhotoRequest` fixture with `font_scale: 1.0` and `locale_code: "zh"`.

- [ ] **Step 2: Run Rust tests and verify missing fields/helpers**

```powershell
cargo test --manifest-path rust/Cargo.toml watermark_tests -- --nocapture
```

Expected: FAIL because request fields and layout helpers are not implemented.

- [ ] **Step 3: Add request fields, validation, and localized labels**

Extend `RenderPhotoRequest`:

```rust
pub font_scale: f64,
pub locale_code: String,
```

Validate:

```rust
if !(0.80..=1.60).contains(&request.font_scale) {
    return Err(invalid_data("validate render request", "font scale must be between 0.80 and 1.60"));
}
if !matches!(request.locale_code.as_str(), "zh" | "en") {
    return Err(invalid_data("validate render request", "locale must be zh or en"));
}
```

Implement one label table:

```rust
struct WatermarkLabels {
    title: &'static str,
    location: &'static str,
    content: &'static str,
    photographer: &'static str,
    number: &'static str,
    time: &'static str,
    address: &'static str,
    coordinates: &'static str,
    notes: &'static str,
}

fn labels(locale: &str) -> WatermarkLabels {
    if locale == "en" {
        WatermarkLabels {
            title: "Site record", location: "Location", content: "Work",
            photographer: "Photographer", number: "Number", time: "Time",
            address: "Address", coordinates: "Coordinates", notes: "Notes",
        }
    } else {
        WatermarkLabels {
            title: "现场记录", location: "位置", content: "内容",
            photographer: "拍摄人", number: "编号", time: "时间",
            address: "地址", coordinates: "坐标", notes: "备注",
        }
    }
}
```

Build all logical lines from this table; do not leave Chinese literals in `draw_watermark_card`.

- [ ] **Step 4: Replace truncation with wrapping and measured layout**

Implement tokenization that groups ASCII words and emits non-ASCII characters as individual tokens; greedily append tokens while measured width fits. If one token exceeds the available width, split that token by character so every emitted line fits.

Use this layout order:

```rust
let margin = ((width.min(height) as f32) * 0.025).round() as u32;
let scale = request.font_scale as f32;
let font_size = (((width as f32) * 0.0312).clamp(31.2, 69.6)) * scale;
let title_size = font_size * 1.18;
let line_height = (font_size * 1.42).round() as u32;
let padding = ((((width as f32) * 0.0216).round()).max(22.0) * scale).round() as u32;
let max_card_width = ((width as f32) * 0.92).round() as u32;
let max_text_width = max_card_width.saturating_sub(padding * 2);
```

Wrap logical lines against `max_text_width`, then measure every final line using its title/body size:

```rust
let mut measured_text_width = 1u32;
for (index, line) in rendered_lines.iter().enumerate() {
    let size = if index == 0 { title_size } else { font_size };
    let (line_width, _) = text_size(PxScale::from(size), font, line);
    measured_text_width = measured_text_width.max(line_width);
}
let accent_width = (font_size * 0.24).round() as u32;
let card_width = (measured_text_width + padding * 2 + accent_width)
    .min(max_card_width);
let card_height = padding * 2 + line_height * rendered_lines.len() as u32;
```

Draw every wrapped line; remove `fit_line` and the fixed `width * 0.62` path.

- [ ] **Step 5: Pass Rust tests and regenerate FRB**

```powershell
cargo fmt --manifest-path rust/Cargo.toml -- --check
cargo clippy --manifest-path rust/Cargo.toml -- -D warnings
cargo test --manifest-path rust/Cargo.toml
dart run build_runner build --delete-conflicting-outputs
dart format lib/src/rust
```

Expected: Rust tests PASS; generated Dart request requires `fontScale` and `localeCode`.

- [ ] **Step 6: Pass the project scale and capture locale from the processor**

In `capture_processor_test.dart`, seed a project with `watermarkFontScale: 1.35`, seed an English capture, process it, and assert:

```dart
expect(images.lastRenderRequest?.fontScale, 1.35);
expect(images.lastRenderRequest?.localeCode, 'en');
```

Construct the production request with:

```dart
fontScale: project.watermarkFontScale,
localeCode: rendering.watermarkLocaleCode,
```

Never read current global settings in the processor; that would change an already-captured photo after a language switch.

- [ ] **Step 7: Run Dart processor tests and commit**

```powershell
flutter test test/workflow/capture_processor_test.dart test/workflow/capture_workflow_test.dart
flutter analyze
git add rust lib/src/rust lib/workflow test/workflow
git commit -m "feat: render adaptive localized watermarks"
```

### Task 4: Watermark Verification Gate

**Files:**
- Verify only.

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces: verified settings persistence and renderer behavior.

- [ ] **Step 1: Run all automated checks**

```powershell
dart run build_runner build --delete-conflicting-outputs
flutter test
flutter analyze
cargo fmt --manifest-path rust/Cargo.toml -- --check
cargo clippy --manifest-path rust/Cargo.toml -- -D warnings
cargo test --manifest-path rust/Cargo.toml
git diff --check
```

Expected: all checks PASS.

- [ ] **Step 2: Record visual device cases for execution**

Generate photos at 80%, 100%, and 160% using short Chinese, long Chinese, short English, and long English fields in landscape and portrait. Confirm short cards visibly narrow, all long fields wrap inside the 92% maximum, no text clips, and English captures contain no Chinese fixed labels.
