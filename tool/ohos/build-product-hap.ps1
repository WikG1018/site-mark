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

$staleKernelFiles = @(
  (Join-Path $app 'build\ohos\intermediates\flutter\defaultDebug\flutter_assets\kernel_blob.bin'),
  (Join-Path $app 'ohos\entry\src\main\resources\rawfile\flutter_assets\kernel_blob.bin')
)
foreach ($file in $staleKernelFiles) {
  if (Test-Path $file) {
    Remove-Item -Force $file
    Write-Host ("REMOVED " + $file)
  }
}
$flutterBuild = Join-Path $app '.dart_tool\flutter_build'
if (Test-Path $flutterBuild) {
  Remove-Item -Recurse -Force $flutterBuild
  Write-Host 'REMOVED .dart_tool/flutter_build'
}

Write-Host '=== Force flutter assemble debug_ohos_application ==='
$assembleOut = Join-Path $app 'build\ohos\intermediates\flutter\defaultDebug'
New-Item -ItemType Directory -Force -Path $assembleOut | Out-Null
$assembleArgs = @(
  "--packages=$pkgs",
  $snap,
  '--suppress-analytics',
  'assemble',
  '--no-version-check',
  '--output', $assembleOut,
  '-dTargetFile=lib/main.dart',
  '-dTargetPlatform=ohos',
  '-dBuildMode=debug',
  '-dTrackWidgetCreation=true',
  '-dOhosArchs=ohos-x64',
  '--DartDefines=U0lURU1BUktfT0hPUz10cnVl',
  'debug_ohos_application'
)
& $dart @assembleArgs
Write-Host ("ASSEMBLE_EXIT=" + $LASTEXITCODE)
if ($LASTEXITCODE -ne 0) {
  throw "flutter assemble failed: $LASTEXITCODE"
}
$assembledKernel = Join-Path $assembleOut 'flutter_assets\kernel_blob.bin'
if (-not (Test-Path $assembledKernel)) {
  throw "assemble did not write $assembledKernel"
}
$assembledAscii = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($assembledKernel))
Write-Host ("ASSEMBLED_KERNEL_SIZE=" + (Get-Item $assembledKernel).Length)
Write-Host ("ASSEMBLED_HAS_SITEMARK_DB_V3=" + $assembledAscii.Contains('SITEMARK_DB_V3'))
if (-not $assembledAscii.Contains('SITEMARK_DB_V3')) {
  throw 'assemble produced stale kernel without SITEMARK_DB_V3'
}

$injectManifest = Join-Path $app 'tool\ohos\inject-native-assets-manifest.ps1'
Write-Host '=== Inject NativeAssetsManifest.json into flutter_assets ==='
& $injectManifest

$patchScript = Join-Path $app 'tool\ohos\patch-flutter-ohos-api24.ps1'
if (Test-Path $patchScript) {
  Write-Host '=== Apply API24 AutoFill stub if oh_modules already extracted ==='
  & $patchScript
}

$compileSqlite = Join-Path $app 'tool\ohos\compile-ohos-sqlite3.ps1'
Write-Host '=== Compile HarmonyOS musl libsqlite3.so (x86_64) ==='
& $compileSqlite -Arch x86_64

$hap = Join-Path $app 'ohos\entry\build\default\outputs\default\entry-default-unsigned.hap'
if (Test-Path $hap) {
  $stamp = Get-Date -Format 'yyyyMMddHHmmss'
  $oldHap = "$hap.old-$stamp"
  Move-Item -Force $hap $oldHap
  Write-Host ("MOVED_OLD_HAP=" + $oldHap)
}

Write-Host '=== Flutter-OH 3.44 build hap --debug --target-platform ohos-x64 --target lib/main.dart ==='
& $dart --packages=$pkgs $snap --suppress-analytics build hap --debug --target-platform ohos-x64 --target lib/main.dart --dart-define=SITEMARK_OHOS=true
$buildExit = $LASTEXITCODE
Write-Host ("BUILD_EXIT=" + $buildExit)
Write-Host ("HAP_EXISTS=" + (Test-Path $hap))
if (-not (Test-Path $hap)) { throw "HAP not found after build exit ${buildExit}: ${hap}" }
Write-Host ("HAP_TIME=" + (Get-Item $hap).LastWriteTime.ToString('s'))
Write-Host ("HAP_SIZE=" + (Get-Item $hap).Length)

$replaceSqlite = Join-Path $app 'tool\ohos\replace-ohos-sqlite3.ps1'
Write-Host '=== Replace Linux glibc libsqlite3.so with OH musl build ==='
& $replaceSqlite -Arch x86_64

Write-Host '=== Inject NativeAssetsManifest.json into HAP ==='
& $injectManifest

$kernelCheck = Join-Path $app 'tool\ohos\task10-kernel-strings.ps1'
Write-Host '=== Verify kernel contains SITEMARK_DB ==='
& $kernelCheck
$kernelTmp = Join-Path $app 'tool\ohos\.cache\hap-kernel-check\kernel_blob.bin'
if (-not (Test-Path $kernelTmp)) {
  throw 'kernel_blob.bin missing after kernel string check'
}
$kernelBytes = [IO.File]::ReadAllBytes($kernelTmp)
$kernelAscii = [Text.Encoding]::ASCII.GetString($kernelBytes)
if (-not $kernelAscii.Contains('SITEMARK_DB_V3')) {
  throw 'kernel_blob.bin missing SITEMARK_DB_V3; refusing to install stale kernel'
}
if (-not $kernelAscii.Contains('SITEMARK_TASK11')) {
  throw 'kernel_blob.bin missing SITEMARK_TASK11; refusing to install stale kernel'
}
Write-Host 'KERNEL_HAS_SITEMARK_DB_V3=True'
Write-Host 'KERNEL_HAS_SITEMARK_TASK11=True'

Write-Host '=== Uninstall previous bundle then install ==='
& $hdc -t 127.0.0.1:5555 uninstall io.github.wikg1018.sitemark
Write-Host ("UNINSTALL_EXIT=" + $LASTEXITCODE)
& $hdc -t 127.0.0.1:5555 install $hap
Write-Host ("INSTALL_EXIT=" + $LASTEXITCODE)
if ($LASTEXITCODE -ne 0) {
  throw "hdc install failed: $LASTEXITCODE"
}
Write-Host '=== TRY START ==='
& $hdc -t 127.0.0.1:5555 shell aa start -a EntryAbility -b io.github.wikg1018.sitemark
Write-Host ("START_EXIT=" + $LASTEXITCODE)
