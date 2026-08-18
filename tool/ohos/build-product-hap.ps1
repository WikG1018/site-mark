$ErrorActionPreference = 'Stop'
$app = 'C:\Users\Administrator\Documents\Codex\2026-07-15\new-chat\.worktrees\ohos'
$dest = 'C:\Users\Administrator\Development\flutter-ohos'
$dart = Join-Path $dest 'bin\cache\dart-sdk\bin\dart.exe'
$snap = Join-Path $dest 'bin\cache\flutter_tools.snapshot'
$pkgs = Join-Path $dest 'packages\flutter_tools\.dart_tool\package_config.json'
$hdc = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'

$env:OHOS_FLUTTER_ROOT = $dest
$env:FLUTTER_ROOT = $dest
$env:FLUTTER_GIT_URL = 'https://gitcode.com/CPF-Flutter/flutter_flutter.git'
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
$env:PUB_CACHE = Join-Path $dest '.pub-cache'
$env:DEVECO_SDK_HOME = 'C:\Program Files\Huawei\DevEco Studio\sdk'
$env:HOS_SDK_HOME = $env:DEVECO_SDK_HOME
$env:JAVA_HOME = 'C:\Program Files\Huawei\DevEco Studio\jbr'
$env:PATH = @(
  (Join-Path $dest 'bin'),
  'C:\Program Files\Huawei\DevEco Studio\tools\ohpm\bin',
  'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin',
  'C:\Program Files\Huawei\DevEco Studio\tools\node',
  'C:\Program Files\Huawei\DevEco Studio\jbr\bin',
  'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains',
  $env:PATH
) -join ';'

function Write-OhosFlutterVersionStamp {
  Write-Host '=== skip writing flutter.version.json (sandbox / permission) ==='
}

$overlayRoot = Join-Path $app 'tool\ohos\community-overlay'
$appPubspec = Join-Path $app 'pubspec.yaml'
$pluginPubspec = Join-Path $app 'packages\sitemark_system_api\pubspec.yaml'
$appLock = Join-Path $app 'pubspec.lock'
$appBackup = Join-Path $overlayRoot 'pubspec.yaml.official.bak'
$pluginBackup = Join-Path $overlayRoot 'sitemark_system_api.pubspec.yaml.official.bak'
$lockBackup = Join-Path $overlayRoot 'pubspec.lock.official.bak'
$overlayApplied = $false

function Restore-OfficialPubspecs {
  if (-not $overlayApplied) { return }
  if (Test-Path $appBackup) {
    Copy-Item -Force $appBackup $appPubspec
    Remove-Item -Force $appBackup
  }
  if (Test-Path $pluginBackup) {
    Copy-Item -Force $pluginBackup $pluginPubspec
    Remove-Item -Force $pluginBackup
  }
  if (Test-Path $lockBackup) {
    Copy-Item -Force $lockBackup $appLock
    Remove-Item -Force $lockBackup
  }
  $overlayApplied = $false
  Write-Host '=== restored official pubspec.yaml / pubspec.lock ==='
}

function Apply-CommunityOverlay {
  Copy-Item -Force $appPubspec $appBackup
  Copy-Item -Force $pluginPubspec $pluginBackup
  if (Test-Path $appLock) {
    Copy-Item -Force $appLock $lockBackup
  }
  Copy-Item -Force (Join-Path $overlayRoot 'pubspec.yaml') $appPubspec
  Copy-Item -Force (Join-Path $overlayRoot 'sitemark_system_api.pubspec.yaml') $pluginPubspec
  $script:overlayApplied = $true
  Write-Host '=== applied community overlay (official files restored after build) ==='
}

Set-Location $app
try {
Apply-CommunityOverlay
Write-OhosFlutterVersionStamp
Write-Host '=== community flutter pub get (product tree + overlay) ==='
& $dart --packages=$pkgs $snap --suppress-analytics pub get
Write-Host ("PUB_GET_EXIT=" + $LASTEXITCODE)
if ($LASTEXITCODE -ne 0) {
  throw "community pub get failed: $LASTEXITCODE"
}

Write-OhosFlutterVersionStamp
Write-Host '=== community flutter build hap --debug --target-platform ohos-x64 --target lib/ohos_review_main.dart ==='
& $dart --packages=$pkgs $snap --suppress-analytics build hap --debug --target-platform ohos-x64 --target lib/ohos_review_main.dart --dart-define=SITEMARK_OHOS=true
$buildExit = $LASTEXITCODE
$hap = Join-Path $app 'ohos\entry\build\default\outputs\default\entry-default-unsigned.hap'
Write-Host ("BUILD_EXIT=" + $buildExit)
Write-Host ("HAP_EXISTS=" + (Test-Path $hap))
if (-not (Test-Path $hap)) { throw "HAP not found after build exit ${buildExit}: ${hap}" }

Write-Host "=== HDC INSTALL $hap ==="
& $hdc -t 127.0.0.1:15555 install $hap
Write-Host ("INSTALL_EXIT=" + $LASTEXITCODE)
Write-Host '=== TRY START ==='
& $hdc -t 127.0.0.1:15555 shell aa start -a EntryAbility -b io.github.wikg1018.sitemark
Write-Host ("START_EXIT=" + $LASTEXITCODE)
} finally {
  Restore-OfficialPubspecs
}
