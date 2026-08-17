# Task 0 toolchain probe

Worktree: `C:\Users\Administrator\Documents\Codex\2026-07-15\new-chat\.worktrees\ohos`  
Branch: `ohos`

Overall verdict: **FAIL**. Empty HAP was not built and did not cold-start on HarmonyOS NEXT (device or emulator). Stop after this probe. Do not implement camera, plugin, or Rust.

---

## Attempt 1 — no device (2026-08-17 22:33 +08:00)

HEAD at write time: `0e267c0` (`docs: add HarmonyOS NEXT adaptation implementation plan`)  
Parents: `a5d7992` (spec) on `847c74b` (v1.0.8 / SiteMark `1.0.8+23`)

Verdict: **FAIL**. No NEXT device. HAP not generated.

### Gate result

| Gate | Result | Evidence |
|---|---|---|
| Empty HAP cold-starts on HarmonyOS NEXT | **FAIL** | No device; HAP not generated |
| Official Flutter still works / not overwritten | **PASS** | Official trees left untouched |
| `main` checkout / `.github/workflows/ci.yml` / `android/` untouched by this task | **PASS** | Only this worktree was written |

### Commands and outputs

#### Git baseline (ohos worktree)

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

#### Official Flutter (must remain untouched)

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

Official Flutter was **not** modified. No files under either official tree were written.

#### Community OHOS Flutter

```text
OHOS_FLUTTER_ROOT=UNSET
```

`Get-ChildItem C:\Users\Administrator\Development` names:

```text
flutter
flutter-3.44.6
```

No community OHOS Flutter SDK was cloned. Clone URL / commit: **N/A**.

Reason for not installing: Task 0 acceptance required a launchable NEXT target. `hdc list targets` was `[Empty]`.

#### DevEco Studio / OpenHarmony SDK / hdc

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

#### Empty HAP

Not created. No `ohos/` application tree. No `flutter create --platforms ohos`. No `flutter build hap`. No install / cold start.

Follow-up after Attempt 1: user stated they have no real device and chose the emulator path. Spec/plan hard gate was amended in `7890263` to accept DevEco NEXT emulator cold start for Phase 0.

---

## Attempt 2 — DevEco NEXT emulator (2026-08-17 +08:00)

HEAD at write time: `7890263` (`docs(ohos): allow NEXT emulator for phase-0 hard gate`)

User constraint: no HarmonyOS NEXT real device. Phase 0 gate after `7890263`: empty HAP cold-start on DevEco NEXT emulator is sufficient for Phase 0. Camera / gallery / ACL full parity still cannot be claimed on emulator.

Verdict: **FAIL**. Phone image and AVD exist, but the VM did not boot and hdc stayed empty. HAP still not generated. Community OHOS Flutter still absent.

### Gate result

| Gate | Result | Evidence |
|---|---|---|
| Empty HAP cold-starts on HarmonyOS NEXT emulator | **FAIL** | AVD created; VM did not boot; hdc `[Empty]`; HAP not generated |
| Official Flutter still works / not overwritten | **PASS** | Official trees left untouched |
| `main` checkout / `.github/workflows/ci.yml` / `android/` untouched by this task | **PASS** | Only this worktree was written |
| Community OHOS Flutter doctor sees HarmonyOS | **FAIL** | SDK not cloned; install deferred because hdc empty |

### Commands and outputs

#### Git baseline (ohos worktree)

```text
git status -sb
## ohos

git log -6 --oneline
7890263 docs(ohos): allow NEXT emulator for phase-0 hard gate
fa634e4 chore(ohos): record toolchain probe failure
0e267c0 docs: add HarmonyOS NEXT adaptation implementation plan
a5d7992 docs: add HarmonyOS NEXT adaptation design
847c74b chore: prepare SiteMark 1.0.8 release (#71)
8a6fe79 fix: XML-safe journal keys and bounded cleanup retries (#70)

git rev-parse HEAD
7890263625a9f56cda1d083cb6c44d4be44c5a26
```

#### Official Flutter

Unchanged from Attempt 1. Official 3.44.6 at `C:\Users\Administrator\Development\flutter` (revision `ee80f08…`) was **not** modified. Second official tree `flutter-3.44.6` also untouched.

#### Community OHOS Flutter

Still **absent**.

```text
OHOS_FLUTTER_ROOT=UNSET
Development\ contents: flutter, flutter-3.44.6
```

Reason for not installing: even after the emulator-gate amendment, Task 0 still requires a launchable hdc target. `hdc list targets` remained `[Empty]`. Cloning a community SDK cannot pass the hard gate without a running emulator or device.

#### Emulator CLI / image / AVD

DevEco Emulator binary: `C:\Program Files\Huawei\DevEco Studio\tools\emulator\emulator.exe` version **6.1.1.300**.

CLI notes:

- Android-style `emulator -list-avds` is invalid here.
- DevEco CLI uses `-imageList` / `-install` / `-create` / `-start` / `-stop` / `-list -details` / `-license accept`.
- AVD name `sitemark-phone-602` was **rejected** (hyphens not allowed). Recreated as `SiteMarkPhone602`.

License: accepted; stored under `C:\Users\Administrator\AppData\Local\Huawei\Emulator6.1\.emu_config`.

Image install:

```text
emulator -license accept
emulator -install -deviceType Phone -osVersion 'HarmonyOS 6.0.2(22)' -force
```

Installed image on disk:

- Path: `C:\Users\Administrator\AppData\Local\Huawei\Sdk\system-image\HarmonyOS-6.0.2\phone_all_x86\`
- Device type: Phone
- OS: HarmonyOS 6.0.2(22)
- Software: 6.0.0.130
- Measured size (recursive files): **4,521,670,456** bytes

AVD create:

```text
emulator -create SiteMarkPhone602
```

AVD path: `C:\Users\Administrator\AppData\Local\Huawei\Emulator\deployed\SiteMarkPhone602\`

`config.ini` (key fields):

```text
name=SiteMarkPhone602
deviceType=phone
deviceModel=PHEMU-FD00
productModel=Pura 90 Pro
os.osVersion=HarmonyOS 6.0.2(22)
os.apiVersion=22
os.softwareVersion=6.0.0.130
hw.cpu.arch=x86_64
hw.cpu.ncore=4
hw.ramSize=4096
hw.dataPartitionSize=6144
hw.hdc.port=notset
imageSubPath=system-image/HarmonyOS-6.0.2/phone_all_x86/
instancePath=C:/Users/Administrator/AppData/Local/Huawei/Emulator/deployed/SiteMarkPhone602
```

#### Start attempt (agent / sandbox)

`emulator -start` and a retry with `-hdcPort 15555` spawned `Emulator.exe` only.

Observed while the process was alive:

- `emulator -list -details` briefly reported `isRunning=true`
- No `qemu` / `hvd` child process
- `hw.hdc.port=notset`
- Port 15555 not listening
- `hdc list targets` = `[Empty]`
- `hdc list targets -v` showed only COM1 / COM3 / COM4 UART
- Hyper-V: Enabled; VBS: Running
- `emulator -stop` reported the instance "is not exists" while `Emulator.exe` still lived
- Leftover process killed with `Stop-Process`

Re-check after cleanup (this write):

```text
hdc version
Ver: 3.2.0d

hdc list targets
[Empty]

emulator -list -details
name=SiteMarkPhone602
isRunning=false
hw.hdc.port=notset
os.osVersion=HarmonyOS 6.0.2(22)
os.apiVersion=22
productModel=Pura 90 Pro
hw.cpu.arch=x86_64
```

Conclusion: image + AVD exist on disk. The GUI / hypervisor VM did **not** actually boot under this agent session. hdc has no target.

#### Empty HAP

Still not created. No `ohos/` application tree. No `flutter create --platforms ohos`. No `flutter build hap`. No install / cold start.

#### Isolation

Primary checkout `C:\Users\Administrator\Documents\Codex\2026-07-15\new-chat` (dirty `agent/journal-key-and-cleanup-observability` @ `fc91300`) was not written. Official Flutter trees were not written. `android/`, `.github/workflows/ci.yml`, `release.yml` were not written.

## Why Task 0 still stops

Hard gate after `7890263`:

1. Empty HAP cold-start on HarmonyOS NEXT **emulator or device** — **failed** (no hdc target; HAP not built).
2. Official Flutter remains usable and not overwritten — **held**.
3. `main` CI / Android tree not edited — **held**.

Human unlock before retrying Phase 0:

1. In DevEco Studio Device Manager, start instance `SiteMarkPhone602` (Phone, HarmonyOS 6.0.2 API 22) **outside this agent sandbox**, so a window appears and qemu actually runs.
2. Confirm `hdc list targets` is non-empty.
3. Install community OHOS Flutter **outside** the repo (e.g. `C:\Users\Administrator\Development\flutter-ohos` from `https://gitcode.com/openharmony-sig/flutter_flutter.git`). Do not overwrite official 3.44.6. Record clone URL + commit/branch. Set `OHOS_FLUTTER_ROOT`.
4. `$OHOS_FLUTTER_ROOT\bin\flutter doctor` must see HarmonyOS / OpenHarmony.
5. Retry empty HAP: `flutter create --platforms ohos`, `build hap --debug`, install, cold start.

If a DevEco-started emulator plus OHOS Flutter still cannot launch an empty HAP: re-evaluate a pure ArkTS path. Do not start Task 1+ camera / plugin / Rust on Flutter.

Camera / gallery / ACL full-parity claims remain blocked even after a successful emulator Phase 0.
