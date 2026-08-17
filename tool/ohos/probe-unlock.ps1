$ErrorActionPreference = 'Continue'
$hdc = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
function Run-Hdc([string]$Title, [string]$Cmd) {
  Write-Host "=== $Title ==="
  & $hdc -t 127.0.0.1:15555 shell $Cmd
  Write-Host ("EXIT=" + $LASTEXITCODE)
  Write-Host
}

Run-Hdc 'power-shell help' 'power-shell help'
Run-Hdc 'uinput help' 'uinput -h'
Run-Hdc 'uitest help' 'uitest --help'
Run-Hdc 'aa help' 'aa help'
Run-Hdc 'param lockscreen' 'param get persist.sys.lockscreen'
Run-Hdc 'param screenlock' 'param get const.secure.screenlock'
Run-Hdc 'param developer' 'param get persist.sys.usb.config'
Run-Hdc 'hidumper display' 'hidumper -s DisplayManagerService -a -a'
