[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string]$Hap,
  # AGC-issued material (AppGallery Connect -> 证书/APP/Profile):
  #   Profile  = signed release .p7b provisioning profile
  #   AppCert  = release certificate .cer
  #   Keystore = the .p12 that matches the certificate request
  [Parameter(Mandatory)] [string]$Profile,
  [Parameter(Mandatory)] [string]$AppCert,
  [Parameter(Mandatory)] [string]$Keystore,
  [Parameter(Mandatory)] [string]$KeyAlias,
  [Parameter(Mandatory)] [string]$KeystorePass,
  [Parameter(Mandatory)] [string]$KeyPass,
  [string]$Out,
  [string]$DevEcoRoot = 'C:\Program Files\Huawei\DevEco Studio'
)

$ErrorActionPreference = 'Stop'
$signTool = Join-Path $DevEcoRoot 'sdk\default\openharmony\toolchains\lib\hap-sign-tool.jar'
$javaExe = 'java'
foreach ($required in @($signTool, $Hap, $Profile, $AppCert, $Keystore)) {
  if (-not (Test-Path -LiteralPath $required)) {
    throw "Required file not found: $required"
  }
}

if (-not $Out) {
  $Out = [IO.Path]::ChangeExtension($Hap, '.signed.hap')
}

& $javaExe -jar $signTool sign-app `
  -keyAlias $KeyAlias `
  -signAlg 'SHA256withECDSA' `
  -mode 'localSign' `
  -appCertFile $AppCert `
  -profileFile $Profile `
  -inFile $Hap `
  -keystoreFile $Keystore `
  -outFile $Out `
  -keystorePass $KeystorePass `
  -keyPass $KeyPass
if ($LASTEXITCODE -ne 0) { throw 'hap-sign-tool sign-app failed' }

& $javaExe -jar $signTool verify-app `
  -inFile $Out `
  -appCertFile $AppCert `
  -profileFile $Profile
if ($LASTEXITCODE -ne 0) { throw 'hap-sign-tool verify-app failed' }

$signed = Get-Item -LiteralPath $Out
if ($signed.Length -lt 1) { throw 'Signed HAP is empty' }
Get-FileHash -Algorithm SHA256 -LiteralPath $Out | Select-Object Path, Hash
Write-Output ("Signed HAP: {0} ({1:N0} bytes)" -f $signed.FullName, $signed.Length)
