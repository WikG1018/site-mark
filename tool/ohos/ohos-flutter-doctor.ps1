$ErrorActionPreference = 'Continue'
$dest = 'C:\Users\Administrator\Development\flutter-ohos'
$dart = Join-Path $dest 'bin\cache\dart-sdk\bin\dart.exe'
$snap = Join-Path $dest 'bin\cache\flutter_tools.snapshot'
$pkgs = Join-Path $dest 'packages\flutter_tools\.dart_tool\package_config.json'
$official = 'C:\Users\Administrator\Development\flutter\bin\flutter.bat'
$hdc = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'

$me = $PID
Get-CimInstance Win32_Process |
  Where-Object {
    $_.ProcessId -ne $me -and
    $_.ParentProcessId -ne $me -and
    $_.CommandLine -and
    $_.CommandLine -match 'flutter-ohos\\bin\\flutter.bat'
  } |
  ForEach-Object {
    Write-Host "KILL $($_.ProcessId) $($_.Name)"
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
  }
Start-Sleep -Seconds 1
Remove-Item (Join-Path $dest 'bin\cache\flutter.bat.lock') -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $dest 'bin\cache\lockfile') -Force -ErrorAction SilentlyContinue

$env:OHOS_FLUTTER_ROOT = $dest
$env:FLUTTER_ROOT = $dest
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

function Invoke-OhosFlutter {
  param([string[]]$FlutterArgs)
  Write-Host ("=== flutter " + ($FlutterArgs -join ' ') + " ===")
  & $dart --packages=$pkgs $snap @FlutterArgs
  Write-Host "EXIT=$LASTEXITCODE"
}

Invoke-OhosFlutter --version --suppress-analytics
Invoke-OhosFlutter doctor -v --suppress-analytics
Invoke-OhosFlutter devices --suppress-analytics
Write-Host '=== HDC ==='
& $hdc list targets
Write-Host '=== OFFICIAL ==='
& $official --version --suppress-analytics
Write-Host "OFFICIAL_EXIT=$LASTEXITCODE"
