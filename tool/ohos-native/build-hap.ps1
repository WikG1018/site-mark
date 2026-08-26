[CmdletBinding()]
param(
  [string]$DevEcoRoot = 'C:\Program Files\Huawei\DevEco Studio',
  [ValidateSet('debug', 'release')]
  [string]$BuildMode = 'debug',
  [switch]$SkipRust,
  [switch]$RunTests
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$projectRoot = Join-Path $repoRoot 'ohos-native'
$node = Join-Path $DevEcoRoot 'tools\node\node.exe'
$hvigor = Join-Path $DevEcoRoot 'tools\hvigor\bin\hvigorw.js'
$ohpm = Join-Path $DevEcoRoot 'tools\ohpm\bin\pm-cli.js'
. (Join-Path $PSScriptRoot 'TestResult.ps1')
foreach ($required in @($node, $hvigor, $ohpm)) {
  if (-not (Test-Path -LiteralPath $required)) {
    throw "DevEco build tool not found: $required"
  }
}
$env:DEVECO_SDK_HOME = Join-Path $DevEcoRoot 'sdk'
$env:NODE_HOME = Join-Path $DevEcoRoot 'tools\node'

# ArkTS compiler warnings are tracked with a ratchet: this budget is the
# committed baseline, and any build that introduces new warnings fails below.
# Baseline composition (2026-08-26, 296 total):
#   295x "Function may throw exceptions" - the data layer deliberately uses
#        try/finally so relationalStore/resultSet errors propagate to callers
#        that already catch them; the compiler asks for a local catch anyway.
#     1x SDK 23 isAnimationReduceEnabled notice - runtime-guarded via
#        ReduceMotionQueryPolicy.read().
# Lower this number whenever warnings are genuinely removed.
$MaxArkTsWarnings = 296
if (-not $SkipRust) {
  & (Join-Path $PSScriptRoot 'build-rust.ps1') `
    -NativeSdkRoot (Join-Path $env:DEVECO_SDK_HOME 'default\openharmony\native')
}
if ($RunTests) {
  & (Join-Path $PSScriptRoot 'run-host-tests.ps1')
  if ($LASTEXITCODE -ne 0) { throw 'HarmonyOS host tests failed' }
}
Push-Location $projectRoot
try {
  & $node $ohpm install --all
  if ($LASTEXITCODE -ne 0) { throw 'ohpm install failed' }
  if ($RunTests) {
    $testResult = Join-Path $projectRoot 'entry\.test\default\intermediates\test\coverage_data\test_result.txt'
    Remove-Item -LiteralPath $testResult -Force -ErrorAction SilentlyContinue
    & $node $hvigor --mode module -p product=default test --no-daemon
    if ($LASTEXITCODE -ne 0) { throw 'ArkTS tests failed' }
    $testSummary = Assert-ArkTsTestResult -Path $testResult
    Write-Output ("ArkTS tests verified: {0} run, {1} passed, {2} ignored" -f
      $testSummary.TestsRun, $testSummary.Pass, $testSummary.Ignore)
  }
  $buildLog = Join-Path $env:TEMP ("sitemark-hap-build-{0}.log" -f [guid]::NewGuid().ToString('N'))
  $previousEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    & $node $hvigor --mode module -p product=default -p "buildMode=$BuildMode" assembleHap --no-daemon 2>&1 |
      Tee-Object -FilePath $buildLog
    $hvigorExit = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousEap
  }
  if ($hvigorExit -ne 0) { throw 'HAP build failed' }
  $warnBudget = Assert-ArkTsWarnBudget -Path $buildLog -MaxWarnings $MaxArkTsWarnings
  Write-Output ("ArkTS warnings within budget: {0}/{1}" -f $warnBudget.WarnCount, $MaxArkTsWarnings)
  Remove-Item -LiteralPath $buildLog -Force -ErrorAction SilentlyContinue
  $hap = Get-ChildItem -LiteralPath (Join-Path $projectRoot 'entry\build') -Recurse -Filter '*.hap' |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($null -eq $hap -or $hap.Length -lt 1) {
    throw 'HAP build completed without a non-empty artifact'
  }
  Get-FileHash -Algorithm SHA256 -LiteralPath $hap.FullName | Select-Object Path, Hash
} finally {
  Pop-Location
}
