$ErrorActionPreference = 'Continue'
$hdc = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
$shot = '/data/local/tmp/sitemark_empty.png'
$local = 'C:\Users\Administrator\Documents\Codex\2026-07-15\new-chat\.worktrees\ohos\tool\ohos\sitemark-empty-coldstart.png'

Write-Host '=== STILL RUNNING ==='
& $hdc -t 127.0.0.1:15555 shell ps -ef
Write-Host '=== UITEST CAP ==='
& $hdc -t 127.0.0.1:15555 shell uitest screenCap -p $shot
Write-Host '=== LS SHOT ==='
& $hdc -t 127.0.0.1:15555 shell ls -l $shot
Write-Host '=== RECV ==='
& $hdc -t 127.0.0.1:15555 file recv $shot $local
Write-Host ("RECV_EXIT=" + $LASTEXITCODE)
if (Test-Path $local) { Get-Item $local | Format-List FullName,Length,LastWriteTime }
Write-Host '=== OFFICIAL ==='
& 'C:\Users\Administrator\Development\flutter\bin\flutter.bat' --version
Write-Host ("OFFICIAL_EXIT=" + $LASTEXITCODE)
Write-Host '=== AA DUMP ==='
& $hdc -t 127.0.0.1:15555 shell aa dump -a
