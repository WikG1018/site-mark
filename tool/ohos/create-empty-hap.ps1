$ErrorActionPreference = 'Stop'
$dest = 'C:\Users\Administrator\Development\flutter-ohos'
$app = 'C:\Users\Administrator\Development\sitemark-ohos-empty'
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
  $jsonPath = Join-Path $dest 'bin\cache\flutter.version.json'
  $verPath = Join-Path $dest 'version'
  $json = @'
{
  "frameworkVersion": "3.27.4",
  "channel": "[user-branch]",
  "repositoryUrl": "https://gitcode.com/CPF-Flutter/flutter_flutter.git",
  "frameworkRevision": "269265738b3e388113f81f82f5aaa101011f3e18",
  "frameworkCommitDate": "2026-07-28 16:37:44 +0800",
  "engineRevision": "e672b006cb34c921db85b8e2f482ed3144a4574b",
  "dartSdkVersion": "3.6.2",
  "devToolsVersion": "2.40.0",
  "flutterVersion": "3.27.4"
}
'@
  $utf8 = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllText($jsonPath, $json, $utf8)
  [System.IO.File]::WriteAllText($verPath, "3.27.4`n", [System.Text.Encoding]::ASCII)
}

function Invoke-OhosFlutter {
  Write-OhosFlutterVersionStamp
  Write-Host ("=== flutter " + ($args -join ' ') + " ===")
  & $dart --packages=$pkgs $snap @args
  if ($LASTEXITCODE -ne 0) { throw "flutter $($args -join ' ') failed: $LASTEXITCODE" }
}

if (Test-Path $app) {
  Write-Host "APP_EXISTS $app"
} else {
  Invoke-OhosFlutter --suppress-analytics create --platforms=ohos --org=com.sitemark --project-name=sitemark_ohos_empty $app
}

Set-Location $app
Invoke-OhosFlutter --suppress-analytics pub get
Write-OhosFlutterVersionStamp
Write-Host '=== flutter --suppress-analytics build hap --debug --target-platform ohos-x64 ==='
& $dart --packages=$pkgs $snap --suppress-analytics build hap --debug --target-platform ohos-x64
$buildExit = $LASTEXITCODE
$hap = Join-Path $app 'ohos\entry\build\default\outputs\default\entry-default-unsigned.hap'
if (-not (Test-Path $hap)) { throw "HAP not found after build exit $buildExit: $hap" }
if ($buildExit -ne 0) {
  Write-Host "BUILD_EXIT=$buildExit (unsigned HAP present; continue emulator install)"
}
Write-Host "=== HDC INSTALL $hap ==="
& $hdc -t 127.0.0.1:15555 install $hap
Write-Host ("INSTALL_EXIT=" + $LASTEXITCODE)
Write-Host '=== BUNDLES ==='
& $hdc -t 127.0.0.1:15555 shell bm dump -a
Write-Host '=== TRY START ==='
& $hdc -t 127.0.0.1:15555 shell aa start -a EntryAbility -b com.sitemark.sitemark_ohos_empty
Start-Sleep -Seconds 4
Write-Host '=== PROCESSES ==='
& $hdc -t 127.0.0.1:15555 shell "ps -ef | grep -i sitemark"
Write-Host '=== DONE ==='
