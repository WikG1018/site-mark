$ErrorActionPreference = 'Stop'
$app = 'C:\Users\Administrator\Documents\Codex\2026-07-15\new-chat\.worktrees\ohos'
$dest = 'C:\Users\Administrator\Development\flutter-ohos-3.44'
$dart = Join-Path $dest 'bin\cache\dart-sdk\bin\dart.exe'
$snap = Join-Path $dest 'bin\cache\flutter_tools.snapshot'
$pkgs = Join-Path $dest 'packages\flutter_tools\.dart_tool\package_config.json'
$hdc = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
$localProperties = Join-Path $app 'ohos\local.properties'

$env:OHOS_FLUTTER_ROOT = $dest
$env:FLUTTER_ROOT = $dest
$env:FLUTTER_GIT_URL = 'https://gitcode.com/CPF-Flutter/flutter_flutter.git'
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
$env:PUB_CACHE = Join-Path $dest '.pub-cache'
$env:DEVECO_SDK_HOME = 'C:\Program Files\Huawei\DevEco Studio\sdk'
$env:HOS_SDK_HOME = $env:DEVECO_SDK_HOME
$env:OHOS_SDK_HOME = $env:DEVECO_SDK_HOME
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

if (-not (Test-Path $dart)) { throw "dart.exe missing: $dart" }
if (-not (Test-Path $snap)) { throw "flutter_tools.snapshot missing: $snap" }
if (-not (Test-Path $pkgs)) { throw "package_config.json missing: $pkgs" }

@"
hwsdk.dir=C:\\Program Files\\Huawei\\DevEco Studio\\sdk
flutter.sdk=C:\\Users\\Administrator\\Development\\flutter-ohos-3.44
flutter.versionName=1.0.8
flutter.versionCode=23
"@ | Set-Content -Encoding ascii -NoNewline $localProperties

Set-Location $app
Write-Host '=== Flutter-OH 3.44 official pub get (no community overlay) ==='
& $dart --packages=$pkgs $snap --suppress-analytics pub get
Write-Host ("PUB_GET_EXIT=" + $LASTEXITCODE)
if ($LASTEXITCODE -ne 0) {
  throw "pub get failed: $LASTEXITCODE"
}

$patchScript = Join-Path $app 'tool\ohos\patch-flutter-ohos-api24.ps1'
if (Test-Path $patchScript) {
  Write-Host '=== Apply API24 AutoFill stub if oh_modules already extracted ==='
  & $patchScript
}

Write-Host '=== Flutter-OH 3.44 build hap --debug --target-platform ohos-x64 --target lib/main.dart ==='
& $dart --packages=$pkgs $snap --suppress-analytics build hap --debug --target-platform ohos-x64 --target lib/main.dart --dart-define=SITEMARK_OHOS=true
$buildExit = $LASTEXITCODE
$hap = Join-Path $app 'ohos\entry\build\default\outputs\default\entry-default-unsigned.hap'
Write-Host ("BUILD_EXIT=" + $buildExit)
Write-Host ("HAP_EXISTS=" + (Test-Path $hap))
if (-not (Test-Path $hap)) { throw "HAP not found after build exit ${buildExit}: ${hap}" }

Write-Host "=== HDC INSTALL $hap ==="
& $hdc -t 127.0.0.1:5555 install $hap
Write-Host ("INSTALL_EXIT=" + $LASTEXITCODE)
Write-Host '=== TRY START ==='
& $hdc -t 127.0.0.1:5555 shell aa start -a EntryAbility -b io.github.wikg1018.sitemark
Write-Host ("START_EXIT=" + $LASTEXITCODE)
