$ErrorActionPreference = 'Continue'
$hdc = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
$hap = 'C:\Users\Administrator\Documents\Codex\2026-07-15\new-chat\.worktrees\ohos\ohos\entry\build\default\outputs\default\entry-default-unsigned.hap'
$target = '127.0.0.1:5555'

Write-Host '=== hdc -t target list ==='
& $hdc -t $target shell aa dump -a
Write-Host '=== force-stop empty ==='
& $hdc -t $target shell aa force-stop com.sitemark.sitemark_ohos_empty
Write-Host '=== install hap ==='
& $hdc -t $target install $hap
Write-Host "INSTALL_EXIT=$LASTEXITCODE"
Write-Host '=== start product ==='
& $hdc -t $target shell aa start -a EntryAbility -b io.github.wikg1018.sitemark
Write-Host "START_EXIT=$LASTEXITCODE"
Start-Sleep -Seconds 5
Write-Host '=== dump abilities ==='
& $hdc -t $target shell aa dump -a
