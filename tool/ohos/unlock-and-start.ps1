$ErrorActionPreference = 'Continue'
$hdc = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
function Run-Hdc([string]$Title, [string]$Cmd) {
  Write-Host "=== $Title ==="
  & $hdc -t 127.0.0.1:15555 shell $Cmd
  Write-Host ("EXIT=" + $LASTEXITCODE)
  Write-Host
}

Run-Hdc 'power-shell help' 'power-shell help'
Run-Hdc 'wakeup' 'power-shell wakeup'
Start-Sleep -Seconds 1
Run-Hdc 'setmode 602' 'power-shell setmode 602'
Start-Sleep -Seconds 1
Run-Hdc 'uitest swipe up' 'uitest uiInput swipe 628 2200 628 600 800'
Start-Sleep -Seconds 1
Run-Hdc 'uinput swipe' 'uinput -T -m 628 2200 628 600 300'
Start-Sleep -Seconds 2
Run-Hdc 'aa start' 'aa start -a EntryAbility -b com.sitemark.sitemark_ohos_empty'
Start-Sleep -Seconds 4
Run-Hdc 'ps grep' 'ps -ef'
