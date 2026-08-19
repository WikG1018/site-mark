$ErrorActionPreference = 'Continue'
$root = 'C:\Users\Administrator\Documents\Codex\2026-07-15\new-chat\.worktrees\ohos'
$official = 'C:\Users\Administrator\Development\flutter'
$dart = Join-Path $official 'bin\cache\dart-sdk\bin\dart.exe'
$snap = Join-Path $official 'bin\cache\flutter_tools.snapshot'
$pkgs = Join-Path $official 'packages\flutter_tools\.dart_tool\package_config.json'
Set-Location $root
Write-Host '=== restore lock from HEAD then official pub get ==='
git checkout -- pubspec.lock
& $dart --packages=$pkgs $snap --suppress-analytics pub get
Write-Host ("PUBGET_EXIT=" + $LASTEXITCODE)
Write-Host '=== file_picker in lock ==='
Select-String -Path (Join-Path $root 'pubspec.lock') -Pattern 'file_picker' -Context 0,8 | Select-Object -First 20
Write-Host '=== lock stat ==='
git diff --stat -- pubspec.lock
