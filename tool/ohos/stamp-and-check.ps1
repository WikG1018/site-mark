$ErrorActionPreference = 'Stop'
$dest = 'C:\Users\Administrator\Development\flutter-ohos'
$dart = Join-Path $dest 'bin\cache\dart-sdk\bin\dart.exe'
$snap = Join-Path $dest 'bin\cache\flutter_tools.snapshot'
$pkgs = Join-Path $dest 'packages\flutter_tools\.dart_tool\package_config.json'
$hdc = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
$official = 'C:\Users\Administrator\Development\flutter\bin\flutter.bat'

Write-Host '=== VERSION FILE ==='
Get-Content (Join-Path $dest 'version')
Write-Host '=== VERSION JSON ==='
Get-Content (Join-Path $dest 'bin\cache\flutter.version.json')

$env:OHOS_FLUTTER_ROOT = $dest
$env:FLUTTER_ROOT = $dest
$env:FLUTTER_GIT_URL = 'https://gitcode.com/CPF-Flutter/flutter_flutter.git'
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'

Write-Host '=== OHOS FLUTTER --version ==='
& $dart --packages=$pkgs $snap --suppress-analytics --version
Write-Host ("OHOS_VERSION_EXIT=" + $LASTEXITCODE)

Write-Host '=== OFFICIAL FLUTTER --version ==='
& $official --version
Write-Host ("OFFICIAL_EXIT=" + $LASTEXITCODE)

Write-Host '=== HDC LIST TARGETS ==='
& $hdc list targets
Write-Host ("HDC_EXIT=" + $LASTEXITCODE)
Write-Host '=== HDC SHELL id ==='
& $hdc -t 127.0.0.1:15555 shell id
Write-Host '=== DONE ==='
