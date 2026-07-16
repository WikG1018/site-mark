# SiteMark Android Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Flutter placeholder launcher icon with the approved centered frosted-glass camera mark, `M`, and red recording dot across Android launcher, themed-icon, Play, and splash surfaces.

**Architecture:** Keep the design reproducible with one Pillow generator that emits the editable SVG master and the PNG sources consumed by `flutter_launcher_icons 0.14.4`. Let the Flutter tool generate standard density and adaptive resources, then add the optional round reference and validate geometry, resource wiring, APK output, and emulator rendering.

**Tech Stack:** Python 3 + Pillow 12.2.0, SVG, Flutter 3.44.6/Dart, `flutter_launcher_icons 0.14.4`, Android SDK 36/AAPT/ADB, API 36 AVD, FFmpeg.

## Global Constraints

- Android minimum is API 31 and target/compile SDK is 36.
- Use a full-bleed opaque background based on `#176B55`; only the camera foreground receives glass treatment.
- Keep the camera, lens, `M`, and red dot within the central `66 × 66 dp` safe zone of a `108 × 108 dp` adaptive layer.
- Fix the lens center at `(54 dp, 54 dp)` with zero geometric offset.
- Use one continuous rounded `M` stroke and a color-mode red dot with primary color `#FF4D4F`.
- In the monochrome layer, preserve `M` as a positive shape and represent the red dot as a circular negative cutout.
- Do not add full words, Chinese text, a watermark bar, outer icon rounding, or an outer drop shadow.
- Google Play output is a full-square `512 × 512`, 32-bit sRGB PNG without a pre-rendered outer mask.

---

### Task 1: Create deterministic icon masters and source assets

**Files:**
- Create: `tool/icon-requirements.txt`
- Create: `tool/generate_launcher_icon.py`
- Create: `tool/test_generate_launcher_icon.py`
- Create: `assets/branding/sitemark-icon.png`
- Create: `assets/branding/sitemark-icon-background.png`
- Create: `assets/branding/sitemark-icon-foreground.png`
- Create: `assets/branding/sitemark-icon-monochrome.png`
- Create: `docs/images/branding/sitemark-icon-master.svg`
- Create: `docs/images/branding/sitemark-play-icon.png`
- Create: `docs/images/branding/README.md`

**Interfaces:**
- Consumes: approved geometry and palette from `docs/superpowers/specs/2026-07-16-sitemark-android-icon-design.md`
- Produces: `write_assets(root: Path) -> dict[str, Path]` plus four PNG inputs used by Task 2

- [ ] **Step 1: Add the Pillow requirement and failing geometry/output tests**

Create `tool/icon-requirements.txt`:

```text
Pillow==12.2.0
```

Create `tool/test_generate_launcher_icon.py`:

```python
from __future__ import annotations

import math
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))

import generate_launcher_icon as icon


class LauncherIconGeneratorTest(unittest.TestCase):
    def test_geometry_is_centered_safe_and_non_overlapping(self) -> None:
        self.assertEqual(icon.LENS_CENTER_DP, (54.0, 54.0))
        left, top, right, bottom = icon.SAFE_ZONE_DP
        camera_left, camera_top, camera_right, camera_bottom = icon.CAMERA_BOUNDS_DP
        self.assertGreaterEqual(camera_left, left)
        self.assertGreaterEqual(camera_top, top)
        self.assertLessEqual(camera_right, right)
        self.assertLessEqual(camera_bottom, bottom)
        distance = math.dist(icon.LENS_CENTER_DP, icon.RED_DOT_CENTER_DP)
        self.assertGreater(distance, icon.LENS_RADIUS_DP + icon.RED_DOT_RADIUS_DP)

    def test_generated_assets_have_required_sizes_modes_and_safe_bounds(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            paths = icon.write_assets(root)

            with Image.open(paths["legacy"]) as image:
                self.assertEqual(image.size, (1024, 1024))
                self.assertEqual(image.mode, "RGB")
            with Image.open(paths["background"]) as image:
                self.assertEqual(image.size, (432, 432))
                self.assertEqual(image.mode, "RGB")
            with Image.open(paths["play"]) as image:
                self.assertEqual(image.size, (512, 512))
                self.assertEqual(image.mode, "RGBA")
                self.assertEqual(image.getchannel("A").getextrema(), (255, 255))

            with Image.open(paths["foreground"]).convert("RGBA") as image:
                self.assertEqual(image.size, (432, 432))
                alpha_bounds = image.getchannel("A").getbbox()
                self.assertIsNotNone(alpha_bounds)
                safe = tuple(round(value * 4) for value in icon.SAFE_ZONE_DP)
                self.assertGreaterEqual(alpha_bounds[0], safe[0] - 1)
                self.assertGreaterEqual(alpha_bounds[1], safe[1] - 1)
                self.assertLessEqual(alpha_bounds[2], safe[2] + 1)
                self.assertLessEqual(alpha_bounds[3], safe[3] + 1)

            with Image.open(paths["monochrome"]).convert("RGBA") as image:
                self.assertEqual(image.size, (432, 432))
                opaque_rgb = {
                    (red, green, blue)
                    for red, green, blue, alpha in image.getdata()
                    if alpha > 0
                }
                self.assertEqual(opaque_rgb, {(255, 255, 255)})

            svg = paths["master_svg"].read_text(encoding="utf-8")
            self.assertIn('cx="54" cy="54"', svg)
            self.assertIn('#FF4D4F', svg)
            self.assertNotIn('rx="22"', svg)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the test and verify it fails before the generator exists**

Run:

```powershell
& 'C:\Users\Administrator\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' `
  -m unittest tool/test_generate_launcher_icon.py -v
```

Expected: FAIL with `ModuleNotFoundError: No module named 'generate_launcher_icon'`.

- [ ] **Step 3: Implement the deterministic generator**

Create `tool/generate_launcher_icon.py`:

```python
from __future__ import annotations

import math
import textwrap
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ARTBOARD_DP = 108.0
SAFE_ZONE_DP = (21.0, 21.0, 87.0, 87.0)
CAMERA_BOUNDS_DP = (21.0, 25.0, 87.0, 80.0)
CAMERA_BODY_DP = (21.0, 32.0, 87.0, 80.0)
CAMERA_BUMP_DP = (43.0, 25.0, 65.0, 38.0)
LENS_CENTER_DP = (54.0, 54.0)
LENS_RADIUS_DP = 16.0
RED_DOT_CENTER_DP = (74.0, 42.0)
RED_DOT_RADIUS_DP = 3.5
M_POINTS_DP = ((45.0, 62.0), (45.0, 46.0), (54.0, 56.0), (63.0, 46.0), (63.0, 62.0))

BACKGROUND_STOPS = ((9, 47, 42), (23, 107, 85), (37, 141, 109))
GLASS_STOPS = ((255, 255, 255), (208, 255, 235), (119, 229, 182))
M_STOPS = ((246, 255, 251), (217, 255, 240), (147, 242, 201))


def _px(value: float, size: int) -> int:
    return round(value / ARTBOARD_DP * size)


def _rect_px(rect: tuple[float, float, float, float], size: int) -> tuple[int, int, int, int]:
    return tuple(_px(value, size) for value in rect)


def _circle_box(center: tuple[float, float], radius: float, size: int) -> tuple[int, int, int, int]:
    x, y = center
    return _rect_px((x - radius, y - radius, x + radius, y + radius), size)


def _mix(start: int, end: int, amount: float) -> int:
    return round(start + (end - start) * amount)


def _three_stop_gradient(size: int, stops: tuple[tuple[int, int, int], ...]) -> Image.Image:
    ramp = Image.linear_gradient("L").resize((size, size)).rotate(
        315,
        resample=Image.Resampling.BICUBIC,
        expand=False,
    )
    channels: list[Image.Image] = []
    for channel_index in range(3):
        values: list[int] = []
        for index in range(256):
            amount = index / 255
            if amount <= 0.5:
                value = _mix(stops[0][channel_index], stops[1][channel_index], amount * 2)
            else:
                value = _mix(stops[1][channel_index], stops[2][channel_index], (amount - 0.5) * 2)
            values.append(value)
        channels.append(ramp.point(values))
    return Image.merge("RGB", channels).convert("RGBA")


def _camera_mask(size: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle(
        _rect_px(CAMERA_BODY_DP, size),
        radius=_px(9.0, size),
        fill=255,
    )
    draw.rounded_rectangle(
        _rect_px(CAMERA_BUMP_DP, size),
        radius=_px(4.0, size),
        fill=255,
    )
    return mask


def _rounded_polyline_mask(size: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    points = [(_px(x, size), _px(y, size)) for x, y in M_POINTS_DP]
    width = _px(4.2, size)
    radius = width // 2
    draw.line(points, fill=255, width=width, joint="curve")
    for x, y in points:
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=255)
    return mask


def render_background(size: int) -> Image.Image:
    return _three_stop_gradient(size, BACKGROUND_STOPS)


def render_foreground(size: int, monochrome: bool = False) -> Image.Image:
    camera_mask = _camera_mask(size)
    lens_box = _circle_box(LENS_CENTER_DP, LENS_RADIUS_DP, size)
    red_dot_box = _circle_box(RED_DOT_CENTER_DP, RED_DOT_RADIUS_DP, size)
    m_mask = _rounded_polyline_mask(size)

    if monochrome:
        alpha = camera_mask.copy()
        alpha_draw = ImageDraw.Draw(alpha)
        alpha_draw.ellipse(lens_box, fill=0)
        alpha_draw.ellipse(red_dot_box, fill=0)
        result = Image.new("RGBA", (size, size), (255, 255, 255, 0))
        result.putalpha(alpha)
        m_layer = Image.new("RGBA", (size, size), (255, 255, 255, 0))
        m_layer.putalpha(m_mask)
        result.alpha_composite(m_layer)
        return result

    result = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    glass = _three_stop_gradient(size, GLASS_STOPS)
    noise = Image.effect_noise((size, size), 18).filter(
        ImageFilter.GaussianBlur(_px(0.8, size))
    )
    noise_alpha = noise.point(lambda value: max(118, min(178, round(118 + value * 0.24))))
    glass.putalpha(ImageChops.multiply(camera_mask, noise_alpha))
    result.alpha_composite(glass)

    softened = camera_mask.filter(ImageFilter.GaussianBlur(_px(0.9, size)))
    edge = ImageChops.subtract(camera_mask, softened).point(lambda value: min(255, value * 4))
    highlight = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    highlight.putalpha(edge)
    result.alpha_composite(highlight)

    draw = ImageDraw.Draw(result)
    draw.ellipse(lens_box, fill=(10, 73, 61, 196))

    m_layer = _three_stop_gradient(size, M_STOPS)
    m_layer.putalpha(m_mask)
    result.alpha_composite(m_layer)

    draw = ImageDraw.Draw(result)
    draw.ellipse(red_dot_box, fill=(255, 77, 79, 255))
    highlight_radius = RED_DOT_RADIUS_DP * 0.34
    highlight_center = (
        RED_DOT_CENTER_DP[0] - RED_DOT_RADIUS_DP * 0.28,
        RED_DOT_CENTER_DP[1] - RED_DOT_RADIUS_DP * 0.28,
    )
    draw.ellipse(
        _circle_box(highlight_center, highlight_radius, size),
        fill=(255, 151, 152, 190),
    )
    return result


def render_full_icon(size: int) -> Image.Image:
    result = render_background(size)
    result.alpha_composite(render_foreground(size))
    return result.convert("RGB")


def build_master_svg() -> str:
    return textwrap.dedent(
        """\
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="1080" height="1080" viewBox="0 0 108 108">
          <defs>
            <linearGradient id="background" x1="0" y1="0" x2="1" y2="1">
              <stop offset="0" stop-color="#092F2A"/>
              <stop offset="0.55" stop-color="#176B55"/>
              <stop offset="1" stop-color="#258D6D"/>
            </linearGradient>
            <linearGradient id="glass" x1="0" y1="0" x2="1" y2="1">
              <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.78"/>
              <stop offset="0.5" stop-color="#D0FFEB" stop-opacity="0.40"/>
              <stop offset="1" stop-color="#77E5B6" stop-opacity="0.25"/>
            </linearGradient>
            <linearGradient id="letter" x1="0" y1="0" x2="1" y2="1">
              <stop offset="0" stop-color="#F6FFFB"/>
              <stop offset="1" stop-color="#93F2C9"/>
            </linearGradient>
            <filter id="frost" x="-20%" y="-20%" width="140%" height="140%">
              <feTurbulence type="fractalNoise" baseFrequency="0.03" numOctaves="2" seed="7" result="noise"/>
              <feDisplacementMap in="SourceGraphic" in2="noise" scale="0.7"/>
              <feGaussianBlur stdDeviation="0.08"/>
            </filter>
          </defs>
          <rect width="108" height="108" fill="url(#background)"/>
          <path d="M30 32H43L47 25H61L65 32H78A9 9 0 0 1 87 41V71A9 9 0 0 1 78 80H30A9 9 0 0 1 21 71V41A9 9 0 0 1 30 32Z" fill="url(#glass)" filter="url(#frost)"/>
          <circle cx="54" cy="54" r="16" fill="#0A493D" fill-opacity="0.77"/>
          <path d="M45 62V46L54 56L63 46V62" fill="none" stroke="url(#letter)" stroke-width="4.2" stroke-linecap="round" stroke-linejoin="round"/>
          <circle cx="74" cy="42" r="3.5" fill="#FF4D4F"/>
        </svg>
        """
    )


def write_assets(root: Path) -> dict[str, Path]:
    branding = root / "assets" / "branding"
    docs_branding = root / "docs" / "images" / "branding"
    branding.mkdir(parents=True, exist_ok=True)
    docs_branding.mkdir(parents=True, exist_ok=True)

    paths = {
        "legacy": branding / "sitemark-icon.png",
        "background": branding / "sitemark-icon-background.png",
        "foreground": branding / "sitemark-icon-foreground.png",
        "monochrome": branding / "sitemark-icon-monochrome.png",
        "master_svg": docs_branding / "sitemark-icon-master.svg",
        "play": docs_branding / "sitemark-play-icon.png",
    }
    render_full_icon(1024).save(paths["legacy"], optimize=True)
    render_background(432).convert("RGB").save(paths["background"], optimize=True)
    render_foreground(432).save(paths["foreground"], optimize=True)
    render_foreground(432, monochrome=True).save(paths["monochrome"], optimize=True)
    render_full_icon(512).convert("RGBA").save(paths["play"], optimize=True)
    paths["master_svg"].write_text(build_master_svg(), encoding="utf-8")
    return paths


if __name__ == "__main__":
    repository_root = Path(__file__).resolve().parents[1]
    for name, path in write_assets(repository_root).items():
        print(f"{name}: {path}")
```

- [ ] **Step 4: Generate assets and run the tests**

Run:

```powershell
$python = 'C:\Users\Administrator\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
& $python tool/generate_launcher_icon.py
& $python -m unittest tool/test_generate_launcher_icon.py -v
```

Expected: six paths are printed and both tests report `ok`.

- [ ] **Step 5: Add asset regeneration documentation**

Create `docs/images/branding/README.md`:

````markdown
# SiteMark launcher icon assets

The editable source is `sitemark-icon-master.svg`. Generated Android inputs live
under `assets/branding/`; the Google Play upload asset is
`sitemark-play-icon.png`.

On Windows, regenerate all source and Android launcher assets from the repository
root with:

```powershell
pwsh.exe -NoLogo -NoProfile -File tool/generate_launcher_icons.ps1
```

The geometry is intentionally code-generated: the lens stays at `(54, 54)` on a
`108 × 108 dp` artboard, and the foreground stays inside the central `66 × 66 dp`
safe zone.
````

- [ ] **Step 6: Inspect source assets and commit the deterministic design source**

Open the four PNG outputs and the SVG with the local image viewer. Reject any
version where the lens is off-center, the red point touches the lens, the `M`
looks thinner at 48 px, or the glass body becomes a flat white block.

```powershell
git add tool/icon-requirements.txt tool/generate_launcher_icon.py `
  tool/test_generate_launcher_icon.py assets/branding docs/images/branding
git diff --cached --check
git commit -m "feat: add reproducible SiteMark icon artwork"
```

Expected: one commit containing the generator, tests, editable master, Android
source PNGs, Play PNG, and regeneration notes.

### Task 2: Generate and wire Android launcher resources

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Create: `flutter_launcher_icons.yaml`
- Create: `tool/generate_launcher_icons.ps1`
- Create: `tool/verify_launcher_icon_resources.py`
- Generate: `android/app/src/main/res/mipmap-*/ic_launcher.png`
- Generate: `android/app/src/main/res/drawable-*/ic_launcher_{background,foreground,monochrome}.png`
- Create: `android/app/src/main/res/mipmap-*/ic_launcher_round.png`
- Create: `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`
- Create: `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml`

**Interfaces:**
- Consumes: the four PNG inputs from Task 1
- Produces: `@mipmap/ic_launcher` and `@mipmap/ic_launcher_round` referenced by the Android manifest

- [ ] **Step 1: Add the launcher generator dependency and configuration**

Add this line under `dev_dependencies` in `pubspec.yaml`:

```yaml
  flutter_launcher_icons: ^0.14.4
```

Create `flutter_launcher_icons.yaml`:

```yaml
flutter_launcher_icons:
  android: true
  ios: false
  image_path_android: assets/branding/sitemark-icon.png
  min_sdk_android: 31
  adaptive_icon_background: assets/branding/sitemark-icon-background.png
  adaptive_icon_foreground: assets/branding/sitemark-icon-foreground.png
  adaptive_icon_monochrome: assets/branding/sitemark-icon-monochrome.png
  adaptive_icon_foreground_inset: 0
```

Run:

```powershell
& 'C:\Users\Administrator\Development\flutter\bin\flutter.bat' pub get
```

Expected: dependency resolution succeeds and `pubspec.lock` records
`flutter_launcher_icons 0.14.4`.

- [ ] **Step 2: Write the failing Android resource verifier**

Create `tool/verify_launcher_icon_resources.py`:

```python
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "android" / "app" / "src" / "main" / "res"
LEGACY = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
ADAPTIVE = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}


def require_png(path: Path, size: int) -> None:
    assert path.exists(), f"Missing {path.relative_to(ROOT)}"
    with Image.open(path) as image:
        assert image.size == (size, size), (
            f"{path.relative_to(ROOT)} is {image.size}, expected {(size, size)}"
        )


def main() -> None:
    manifest = (ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml").read_text(
        encoding="utf-8"
    )
    assert 'android:icon="@mipmap/ic_launcher"' in manifest
    assert 'android:roundIcon="@mipmap/ic_launcher_round"' in manifest

    adaptive_xml = RES / "mipmap-anydpi-v26" / "ic_launcher.xml"
    round_xml = RES / "mipmap-anydpi-v26" / "ic_launcher_round.xml"
    assert adaptive_xml.exists(), "Missing adaptive ic_launcher.xml"
    assert round_xml.exists(), "Missing adaptive ic_launcher_round.xml"
    xml = adaptive_xml.read_text(encoding="utf-8")
    for required in (
        "@drawable/ic_launcher_background",
        "@drawable/ic_launcher_foreground",
        "@drawable/ic_launcher_monochrome",
        'android:inset="0%"',
    ):
        assert required in xml, f"Missing {required} in adaptive icon XML"
    assert round_xml.read_text(encoding="utf-8") == xml

    for density, size in LEGACY.items():
        require_png(RES / f"mipmap-{density}" / "ic_launcher.png", size)
        require_png(RES / f"mipmap-{density}" / "ic_launcher_round.png", size)

    for density, size in ADAPTIVE.items():
        for name in (
            "ic_launcher_background.png",
            "ic_launcher_foreground.png",
            "ic_launcher_monochrome.png",
        ):
            require_png(RES / f"drawable-{density}" / name, size)

    print("Launcher icon resources verified")


if __name__ == "__main__":
    main()
```

Run:

```powershell
& 'C:\Users\Administrator\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' `
  tool/verify_launcher_icon_resources.py
```

Expected: FAIL on the first missing adaptive or round resource.

- [ ] **Step 3: Add round-icon manifest wiring and the reproducible PowerShell wrapper**

Update the `<application>` opening tag in
`android/app/src/main/AndroidManifest.xml` to include:

```xml
    <application
        android:label="@string/app_name"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:roundIcon="@mipmap/ic_launcher_round">
```

Create `tool/generate_launcher_icons.ps1`:

```powershell
param(
    [string]$Python = 'python',
    [string]$Flutter = 'flutter',
    [string]$Dart = 'dart'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    & $Python tool/generate_launcher_icon.py
    if ($LASTEXITCODE -ne 0) { throw 'Icon source generation failed' }

    & $Flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }

    & $Dart run flutter_launcher_icons -f flutter_launcher_icons.yaml
    if ($LASTEXITCODE -ne 0) { throw 'flutter_launcher_icons failed' }

    foreach ($density in @('mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi')) {
        $mipmap = Join-Path $root "android/app/src/main/res/mipmap-$density"
        Copy-Item -LiteralPath (Join-Path $mipmap 'ic_launcher.png') `
            -Destination (Join-Path $mipmap 'ic_launcher_round.png') -Force
    }

    $adaptive = Join-Path $root 'android/app/src/main/res/mipmap-anydpi-v26'
    Copy-Item -LiteralPath (Join-Path $adaptive 'ic_launcher.xml') `
        -Destination (Join-Path $adaptive 'ic_launcher_round.xml') -Force
}
finally {
    Pop-Location
}
```

- [ ] **Step 4: Generate the Android resources**

Run:

```powershell
pwsh.exe -NoLogo -NoProfile -File tool/generate_launcher_icons.ps1 `
  -Python 'C:\Users\Administrator\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' `
  -Flutter 'C:\Users\Administrator\Development\flutter\bin\flutter.bat' `
  -Dart 'C:\Users\Administrator\Development\flutter\bin\cache\dart-sdk\bin\dart.exe'
```

Expected: the tool reports default, adaptive, and monochrome Android icon
generation; five `mipmap-*` and five `drawable-*` density directories contain
the expected outputs.

- [ ] **Step 5: Run static resource verification and inspect the generated diff**

```powershell
& 'C:\Users\Administrator\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' `
  tool/verify_launcher_icon_resources.py
git status --short
git diff --check
```

Expected: `Launcher icon resources verified`; no old Flutter logo remains in an
`ic_launcher*` file; only the dependency/configuration, manifest, tooling, and
launcher resources are changed.

- [ ] **Step 6: Commit Android launcher integration**

```powershell
git add pubspec.yaml pubspec.lock flutter_launcher_icons.yaml `
  tool/generate_launcher_icons.ps1 tool/verify_launcher_icon_resources.py `
  android/app/src/main/AndroidManifest.xml android/app/src/main/res
git diff --cached --check
git commit -m "feat: add adaptive SiteMark launcher icon"
```

Expected: one commit containing the generated Android resources and their
reproducible configuration.

### Task 3: Verify APK, launcher masks, settings surface, and splash

**Files:**
- Modify: `docs/release-checklist.md`
- Verify: `build/app/outputs/flutter-apk/app-debug.apk`
- Produce untracked QA evidence: `build/icon-qa/launcher.png`, `settings.png`, `splash.mp4`, and `splash-montage.png`

**Interfaces:**
- Consumes: generated resources and manifest wiring from Task 2
- Produces: verified debug APK and a permanent release-checklist guard

- [ ] **Step 1: Add permanent icon checks to the release checklist**

Under `## Automated`, add:

```markdown
- `python tool/verify_launcher_icon_resources.py`
```

Under `## Device acceptance`, add:

```markdown
- Inspect the launcher icon under circle, squircle, and rounded-rectangle masks.
- On Android 13+, enable themed icons and verify the monochrome `M` plus red-dot cutout.
- Cold-start the app and verify the Android 12+ splash icon is centered and unclipped.
```

- [ ] **Step 2: Run the complete static and build verification suite**

```powershell
$flutter = 'C:\Users\Administrator\Development\flutter\bin\flutter.bat'
$python = 'C:\Users\Administrator\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
& $python -m unittest tool/test_generate_launcher_icon.py -v
& $python tool/verify_launcher_icon_resources.py
& $flutter analyze
& $flutter test
cargo fmt --check --manifest-path rust/Cargo.toml
cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path rust/Cargo.toml
Push-Location android
try { .\gradlew.bat :app:testDebugUnitTest } finally { Pop-Location }
& $flutter build apk --debug
```

Expected: Python tests pass, resource verification succeeds, Flutter/Rust/Android
checks pass, and `build/app/outputs/flutter-apk/app-debug.apk` is rebuilt.

- [ ] **Step 3: Inspect the packaged icon resources with AAPT**

```powershell
$aapt = 'C:\Users\Administrator\AppData\Local\Android\Sdk\build-tools\37.0.0\aapt.exe'
$apk = 'build\app\outputs\flutter-apk\app-debug.apk'
& $aapt dump badging $apk | Select-String 'application-icon|application:'
& $aapt dump xmltree $apk res/mipmap-anydpi-v26/ic_launcher.xml | `
  Select-String 'background|foreground|monochrome|inset'
```

Expected: the APK advertises `@mipmap/ic_launcher`; the adaptive XML references
background, foreground, and monochrome resources with zero extra inset.

- [ ] **Step 4: Boot the API 36 emulator, install the APK, and capture launcher/settings evidence**

```powershell
$sdk = 'C:\Users\Administrator\AppData\Local\Android\Sdk'
$adb = Join-Path $sdk 'platform-tools\adb.exe'
$emulator = Join-Path $sdk 'emulator\emulator.exe'
$qa = 'build\icon-qa'
New-Item -ItemType Directory -Force -Path $qa | Out-Null

if (-not (& $adb devices | Select-String '^emulator-')) {
    Start-Process -FilePath $emulator `
      -ArgumentList @('-avd','SiteMark_API_36','-no-audio','-no-boot-anim','-gpu','swiftshader_indirect') `
      -WindowStyle Hidden
}
for ($i = 0; $i -lt 60; $i++) {
    if ((& $adb shell getprop sys.boot_completed 2>$null).Trim() -eq '1') { break }
    Start-Sleep -Seconds 2
}

& $adb install -r build\app\outputs\flutter-apk\app-debug.apk
& $adb shell input keyevent KEYCODE_HOME
Start-Sleep -Seconds 1
$physical = (& $adb shell wm size | Select-String 'Physical size').ToString().Split(':')[1].Trim().Split('x')
$x = [int]$physical[0] / 2
$fromY = [int]($physical[1] * 0.86)
$toY = [int]($physical[1] * 0.28)
& $adb shell input swipe $x $fromY $x $toY 350
Start-Sleep -Seconds 1
& $adb shell screencap -p /sdcard/sitemark-launcher.png
& $adb pull /sdcard/sitemark-launcher.png "$qa\launcher.png"

& $adb shell am start -a android.settings.APPLICATION_DETAILS_SETTINGS `
  -d package:io.github.wikg1018.sitemark
Start-Sleep -Seconds 1
& $adb shell screencap -p /sdcard/sitemark-settings.png
& $adb pull /sdcard/sitemark-settings.png "$qa\settings.png"
```

Expected: launcher/app drawer and Android app-details settings both show the new
green glass camera icon with a centered `M` and separate red point.

- [ ] **Step 5: Capture and inspect the cold-start splash sequence**

```powershell
$adb = 'C:\Users\Administrator\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$qa = 'build\icon-qa'
& $adb shell am force-stop io.github.wikg1018.sitemark
$record = Start-Process -FilePath $adb `
  -ArgumentList @('shell','screenrecord','--time-limit','4','/sdcard/sitemark-splash.mp4') `
  -PassThru -WindowStyle Hidden
Start-Sleep -Milliseconds 500
& $adb shell monkey -p io.github.wikg1018.sitemark -c android.intent.category.LAUNCHER 1
Wait-Process -Id $record.Id
& $adb pull /sdcard/sitemark-splash.mp4 "$qa\splash.mp4"
& 'C:\Users\Administrator\AppData\Local\Microsoft\WinGet\Links\ffmpeg.exe' `
  -y -i "$qa\splash.mp4" -vf 'fps=5,scale=360:-1,tile=5x2' -frames:v 1 `
  "$qa\splash-montage.png"
```

Inspect `launcher.png`, `settings.png`, and `splash-montage.png` with the image
viewer. Reject the build if the icon is clipped, the lens is not centered, the
red point merges into the lens, the `M` loses a stroke, or the splash zooms the
camera outside the safe zone.

- [ ] **Step 6: Verify the worktree and commit the release-checklist guard**

```powershell
git status --short
git diff --check
git add docs/release-checklist.md
git commit -m "docs: add launcher icon release checks"
```

Expected: QA files remain under ignored `build/`; the final tracked commit only
updates the reusable release checklist, and the worktree is clean afterward.
