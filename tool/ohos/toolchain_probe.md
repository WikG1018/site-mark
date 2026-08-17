# Task 0 toolchain probe

Date: 2026-08-17 22:33 +08:00  
Worktree: `C:\Users\Administrator\Documents\Codex\2026-07-15\new-chat\.worktrees\ohos`  
Branch: `ohos`  
HEAD: `0e267c0` (`docs: add HarmonyOS NEXT adaptation implementation plan`)  
Parents: `a5d7992` (spec) on `847c74b` (v1.0.8 / SiteMark `1.0.8+23`)

Verdict: **FAIL**. Empty HAP was not built and did not cold-start on HarmonyOS NEXT. Stop after this probe. Do not implement camera, plugin, or Rust.

## Gate result

| Gate | Result | Evidence |
|---|---|---|
| Empty HAP cold-starts on HarmonyOS NEXT | **FAIL** | No device; HAP not generated |
| Official Flutter still works / not overwritten | **PASS** | Official trees left untouched |
| `main` checkout / `.github/workflows/ci.yml` / `android/` untouched by this task | **PASS** | Only this worktree was written |

## Commands and outputs

### Git baseline (ohos worktree)

```text
git status -sb
## ohos

git log -5 --oneline
0e267c0 docs: add HarmonyOS NEXT adaptation implementation plan
a5d7992 docs: add HarmonyOS NEXT adaptation design
847c74b chore: prepare SiteMark 1.0.8 release (#71)
8a6fe79 fix: XML-safe journal keys and bounded cleanup retries (#70)
c3e699a fix: 媒体与生命周期热修（MediaStore 安全替换 / 幂等删除 / 启动卸载保护 / MEMORY_KILL ACK） (#69)

git rev-parse HEAD
0e267c02b5f5edc68384fe5097c0456e644bf16e
```

### Official Flutter (must remain untouched)

Paths present:

- `C:\Users\Administrator\Development\flutter`
- `C:\Users\Administrator\Development\flutter-3.44.6`

`PATH` resolves `flutter` to `C:\Users\Administrator\Development\flutter\bin\flutter.bat`.

`C:\Users\Administrator\Development\flutter\bin\cache\flutter.version.json`:

```json
{
  "frameworkVersion": "3.44.6",
  "channel": "stable",
  "repositoryUrl": "https://github.com/flutter/flutter.git",
  "frameworkRevision": "ee80f08bbf97172ec030b8751ceab557177a34a6",
  "frameworkCommitDate": "2026-07-08 15:02:06 -0700",
  "engineRevision": "83675ed27633283e7fc296c8bca22e841224c096",
  "dartSdkVersion": "3.12.2",
  "flutterVersion": "3.44.6"
}
```

`C:\Users\Administrator\Development\flutter\bin\internal\engine.version`:

```text
83675ed27633283e7fc296c8bca22e841224c096
```

`C:\Users\Administrator\Development\flutter-3.44.6` exists as a second official tree. Its `bin\cache\flutter.version.json` was not present at probe time.

`flutter.bat --version` via redirected capture returned empty stdout (bat/cmd wrapper). Version above is from the official cache stamp, not from overwriting the SDK.

Official Flutter was **not** modified. No files under either official tree were written.

### Community OHOS Flutter

```text
OHOS_FLUTTER_ROOT=UNSET
```

`Get-ChildItem C:\Users\Administrator\Development` names:

```text
flutter
flutter-3.44.6
```

Recursive search (depth 2) for directories matching `ohos|harmony` under `Development\`: **NONE**.

No community OHOS Flutter SDK was cloned. Clone URL / commit: **N/A**.

`$OHOS_FLUTTER_ROOT\bin\flutter doctor` was **not run** (SDK absent).

Reason for not installing: Task 0 acceptance is a real-device empty HAP launch. `hdc list targets` is `[Empty]`. Installing a community SDK cannot pass the hard gate without a NEXT device, and the plan says stop if doctor fails **or** no device **or** HAP cannot cold-start.

### DevEco Studio / OpenHarmony SDK / hdc

DevEco Studio: `C:\Program Files\Huawei\DevEco Studio`

`product-info.json`:

```text
name=DevEco Studio
version=6.0.0.858
buildNumber=DS.192.20260312.1835
productCode=DS
env=production
```

OpenHarmony uni-package `C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\oh-uni-package.json`:

```json
{
  "apiVersion": "22",
  "displayName": "Toolchains",
  "meta": { "metaVersion": "3.0.0" },
  "path": "toolchains",
  "releaseType": "Release",
  "version": "6.0.2.150"
}
```

hdc binary: `C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe` (exists)

hdc on PATH: **no**

```text
hdc version
Ver: 3.2.0d

hdc list targets
[Empty]
```

Device model: **none**  
HarmonyOS NEXT API on device: **none**

### Empty HAP

Not created. No `ohos/` application tree. No `flutter create --platforms ohos`. No `flutter build hap`. No install / cold start.

### Main checkout isolation (controller dirty tree, not modified by this task)

Path: `C:\Users\Administrator\Documents\Codex\2026-07-15\new-chat`  
Branch: `agent/journal-key-and-cleanup-observability` (dirty, ahead of origin by 2)  
HEAD: `fc91300285dc7e4888a073cc50a760382a636226`

This Task 0 session did not write that checkout, `android/`, `.github/workflows/ci.yml`, or `release.yml`.

## Why Task 0 stops

Hard gate from the plan:

1. Empty HAP cold-start on HarmonyOS NEXT — **failed** (no target).
2. Official Flutter remains usable and not overwritten — **held**.
3. `main` CI / Android tree not edited — **held**.

Follow-up (human): attach a HarmonyOS NEXT device so `hdc list targets` is non-empty, then install community OHOS Flutter **outside** the repo (e.g. `C:\Users\Administrator\Development\flutter-ohos`) without touching official Flutter, and retry the empty HAP spike.

Per spec: Phase 0 failed. Do not start Task 1+. Re-evaluate a pure ArkTS path if the Flutter OHOS toolchain still cannot launch on NEXT after a device is available.
