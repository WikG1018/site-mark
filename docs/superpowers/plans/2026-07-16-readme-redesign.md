# SiteMark README Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the developer-heavy README with a Chinese-first product landing page backed by four real Android screenshots and honest alpha-release information.

**Architecture:** Keep all presentation in the repository-native `README.md` and committed image assets under `docs/images/readme/`. Capture images from the existing API 36 AVD and render the final Markdown through GitHub's API before pushing the documentation-only commits to PR #1.

**Tech Stack:** GitHub-flavored Markdown, HTML image sizing, Android Emulator/ADB, GitHub CLI.

## Global Constraints

- Chinese is the primary narrative language; compact English summaries remain for international visitors.
- Screenshots must come from the actual SiteMark app and external AOSP system camera, never mockups.
- Use synthetic project/site data only.
- Do not claim a production-signed APK is currently available.
- Do not claim forensic tamper resistance; SHA-256 is traceability metadata.
- Do not name or make unverifiable claims about competing products.
- Keep screenshots under `docs/images/readme/` and verify every relative target.

---

### Task 1: Capture and commit real product screenshots

**Files:**
- Create: `docs/images/readme/01-projects.png`
- Create: `docs/images/readme/02-capture-form.png`
- Create: `docs/images/readme/03-system-camera.png`
- Create: `docs/images/readme/04-watermarked-output.jpg`

**Interfaces:**
- Consumes: `SiteMark_API_36` AVD and `build/app/outputs/flutter-apk/app-debug.apk`
- Produces: four stable relative image paths consumed by `README.md`

- [ ] **Step 1: Start the API 36 AVD and wait for Android boot**

Run PowerShell with the SDK paths already installed on the host:

```powershell
$sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
Start-Process -FilePath "$sdk\emulator\emulator.exe" `
  -ArgumentList @('-avd','SiteMark_API_36','-no-window','-no-audio','-no-boot-anim','-gpu','swiftshader_indirect') `
  -WindowStyle Hidden
$adb = "$sdk\platform-tools\adb.exe"
for ($i = 0; $i -lt 30; $i++) {
  if ((& $adb shell getprop sys.boot_completed 2>$null).Trim() -eq '1') { break }
  Start-Sleep -Seconds 2
}
```

Expected: `adb devices` lists an `emulator-*` device and
`adb shell getprop sys.boot_completed` returns `1`.

- [ ] **Step 2: Install the current debug build and select Chinese**

```powershell
& 'C:\Users\Administrator\Development\flutter\bin\flutter.bat' build apk --debug
& $adb install -r build\app\outputs\flutter-apk\app-debug.apk
& $adb shell cmd locale set-app-localeconfig io.github.wikg1018.sitemark --locales zh-CN,en
& $adb shell cmd locale set-app-locales io.github.wikg1018.sitemark --locales zh-CN
& $adb shell monkey -p io.github.wikg1018.sitemark -c android.intent.category.LAUNCHER 1
```

Expected: the launcher opens SiteMark with Chinese interface strings.

- [ ] **Step 3: Capture the project-list screenshot**

Use the existing synthetic `SiteMarkDemo` project. If the AVD was reset, create
that project through the visible form with ADB taps and ASCII input. Then run:

```powershell
& $adb shell screencap -p /sdcard/01-projects.png
& $adb pull /sdcard/01-projects.png docs/images/readme/01-projects.png
```

Expected: the screenshot shows `工程印记`, the no-ads/no-cloud chip, a synthetic
project card, and the new-project action.

- [ ] **Step 4: Capture the record form and external camera screenshots**

Open the project, tap `拍摄`, and capture the form before entering fields:

```powershell
& $adb shell screencap -p /sdcard/02-capture-form.png
& $adb pull /sdcard/02-capture-form.png docs/images/readme/02-capture-form.png
```

Enter synthetic fields (`AreaA`, `Inspection`, `Engineer`), grant foreground
location with `pm grant`, and tap `调用系统相机`. Wait until
`dumpsys window` reports `com.android.camera2/com.android.camera.CaptureActivity`,
then run:

```powershell
& $adb shell screencap -p /sdcard/03-system-camera.png
& $adb pull /sdcard/03-system-camera.png docs/images/readme/03-system-camera.png
```

Expected: `02-capture-form.png` shows SiteMark's metadata form and
`03-system-camera.png` shows the separate AOSP camera activity.

- [ ] **Step 5: Complete capture and pull the rendered output**

Tap the system shutter and review confirmation, wait for SiteMark to show a
ready record, determine the newest file in `/sdcard/Pictures/SiteMark`, and pull
it as the stable README asset:

```powershell
$remote = (& $adb shell ls -t /sdcard/Pictures/SiteMark/*.jpg | Select-Object -First 1).Trim()
& $adb pull $remote docs/images/readme/04-watermarked-output.jpg
```

Expected: the JPEG contains the synthetic photo and the bottom watermark card
with project, work, person, number, time, and coordinate fields.

- [ ] **Step 6: Inspect and commit the four assets**

Open all four files with the local image viewer. Reject screenshots with
keyboards, loading spinners, customer data, clipped controls, or missing
watermark text.

```bash
git add docs/images/readme/
git commit -m "docs: add SiteMark product screenshots"
```

Expected: exactly four image assets are committed.

### Task 2: Rewrite README as a product landing page

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: the four image paths produced by Task 1
- Produces: the repository landing page rendered by GitHub

- [ ] **Step 1: Replace the hero and add status badges**

Use this exact hierarchy at the top of `README.md`:

```markdown
# SiteMark 工程印记

> 调用手机厂商系统相机的开源工程水印相机：无广告、无云端、原图留在本机。

An open-source, offline-first engineering watermark camera that keeps the
manufacturer camera experience.

[![CI](https://github.com/WikG1018/site-mark/actions/workflows/ci.yml/badge.svg)](https://github.com/WikG1018/site-mark/actions/workflows/ci.yml)
![Android 12+](https://img.shields.io/badge/Android-12%2B-3DDC84?logo=android&logoColor=white)
[![License](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](LICENSE)
![Offline](https://img.shields.io/badge/Network-offline--first-176B55)
![Status](https://img.shields.io/badge/status-v0.1.0--alpha-orange)

**当前状态：v0.1.0-alpha。尚未发布生产签名 APK，欢迎开发者测试。**
```

Badge targets must point to the repository CI workflow, Android 12+, the local
license, offline status, and alpha status. Do not add a release-download badge.

- [ ] **Step 2: Add the 2 x 2 screenshot gallery**

Use a compact HTML table so desktop displays two images per row and GitHub mobile
can still scale them:

```html
<table>
  <tr>
    <td><img src="docs/images/readme/01-projects.png" alt="项目列表" width="260"></td>
    <td><img src="docs/images/readme/02-capture-form.png" alt="现场记录表单" width="260"></td>
  </tr>
  <tr>
    <td><img src="docs/images/readme/03-system-camera.png" alt="Android 系统相机" width="260"></td>
    <td><img src="docs/images/readme/04-watermarked-output.jpg" alt="工程水印成片" width="260"></td>
  </tr>
</table>
```

Add captions stating that the images are from an Android 16 AVD with synthetic
data and that vendor UI varies by phone.

- [ ] **Step 3: Write the product and trust sections**

Add these sections in order:

```markdown
## 为什么做工程印记 / Why SiteMark
## 核心能力
## 使用流程
## 安装与当前状态
## 隐私与权限
## 水印与项目导出
```

The capability table must cover system-camera intent, offline processing,
private originals, MediaStore output, immutable evidence fields, constrained
watermark settings, and open-source licensing. Installation must distinguish CI
debug artifacts from future production-signed releases.

- [ ] **Step 4: Preserve contributor information below product content**

Add or retain these sections after the trust content:

```markdown
## 技术架构 / Architecture
## 本地构建 / Build locally
## 验证状态与路线图
## 参与贡献
## License
```

Link to the design, implementation plan, verification record, release checklist,
privacy policy, contributing guide, security policy, and third-party notices.

- [ ] **Step 5: Commit the README rewrite**

```bash
git add README.md
git diff --cached --check
git commit -m "docs: redesign README product landing page"
```

Expected: the README references all four screenshots and contains no claim that
a production-signed APK is downloadable.

### Task 3: Verify GitHub rendering and update PR #1

**Files:**
- Verify: `README.md`
- Verify: `docs/images/readme/01-projects.png`
- Verify: `docs/images/readme/02-capture-form.png`
- Verify: `docs/images/readme/03-system-camera.png`
- Verify: `docs/images/readme/04-watermarked-output.jpg`

**Interfaces:**
- Consumes: committed README and image assets
- Produces: updated `feat/sitemark-v0.1.0` branch and Draft PR #1

- [ ] **Step 1: Validate local targets and content rules**

```powershell
$targets = @(
  'docs/images/readme/01-projects.png',
  'docs/images/readme/02-capture-form.png',
  'docs/images/readme/03-system-camera.png',
  'docs/images/readme/04-watermarked-output.jpg',
  'docs/release-checklist.md',
  'docs/verification-v0.1.0-alpha.md',
  'PRIVACY.md','CONTRIBUTING.md','SECURITY.md','THIRD_PARTY_NOTICES.md','LICENSE'
)
$targets | ForEach-Object { if (-not (Test-Path $_)) { throw "Missing: $_" } }
rg -n 'production-signed APK is available|正式版已经发布|点击下载正式版' README.md
```

Expected: all targets exist and the prohibited-claim scan returns no matches.

- [ ] **Step 2: Render Markdown through GitHub's API**

Submit the README text to `POST /markdown` with repository context and save the
returned HTML under `C:\tmp\sitemark-readme-preview.html` for inspection.

Expected: headings appear in the intended order; the response contains four
`docs/images/readme/` image references and a valid table.

- [ ] **Step 3: Push and inspect the PR branch**

```bash
git push origin feat/sitemark-v0.1.0
gh pr checks 1 --repo WikG1018/site-mark
```

Open the branch README on GitHub and inspect desktop/mobile scaling, image
loading, badges, and tables. Keep PR #1 as Draft because signing secrets and the
physical-device matrix remain incomplete.

- [ ] **Step 4: Confirm final repository state**

```bash
git status -sb
git log -5 --oneline
gh pr view 1 --repo WikG1018/site-mark --json url,isDraft,statusCheckRollup
```

Expected: the worktree is clean, the branch tracks origin, PR #1 remains Draft,
and the latest CI result is visible.
