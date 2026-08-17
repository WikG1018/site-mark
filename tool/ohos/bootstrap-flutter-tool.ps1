$ErrorActionPreference = 'Stop'
$dest = 'C:\Users\Administrator\Development\flutter-ohos'
$dart = Join-Path $dest 'bin\cache\dart-sdk\bin\dart.exe'
$snap = Join-Path $dest 'bin\cache\flutter_tools.snapshot'
$script = Join-Path $dest 'packages\flutter_tools\bin\flutter_tools.dart'
$pkgs = Join-Path $dest 'packages\flutter_tools\.dart_tool\package_config.json'
$stamp = Join-Path $dest 'bin\cache\flutter_tools.stamp'

$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
$env:PUB_CACHE = Join-Path $dest '.pub-cache'

Write-Host 'SNAPSHOT_START'
& $dart --verbosity=error --snapshot=$snap --snapshot-kind=app-jit --packages=$pkgs --no-enable-mirrors $script
Write-Host "SNAP_EXIT=$LASTEXITCODE"
Write-Host "SNAP_EXISTS=$(Test-Path $snap)"
$rev = git -C $dest rev-parse HEAD
Set-Content -Path $stamp -Value "`"$rev`":" -Encoding ASCII
Write-Host "STAMP=$(Get-Content $stamp -Raw)"
