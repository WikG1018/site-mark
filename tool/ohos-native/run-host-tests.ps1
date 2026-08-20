[CmdletBinding()]
param(
  [string]$PythonCommand = 'python',
  [string[]]$PythonTestModules = @(
    'tool.test_verify_ohos_native_manifest',
    'tool.test_seed_ohos_performance_db',
    'tool.test_ohos_capture_database_contract',
    'tool.test_ohos_host_test_gate'
  ),
  [string[]]$PowerShellTestScripts = @(
    'tool/ohos-native/test/verify-test-result.Tests.ps1'
  )
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$powerShell = (Get-Process -Id $PID).Path

Push-Location $repoRoot
try {
  & $PythonCommand -m unittest @PythonTestModules
  if ($LASTEXITCODE -ne 0) {
    throw "HarmonyOS Python host tests failed with exit code $LASTEXITCODE"
  }

  foreach ($relativePath in $PowerShellTestScripts) {
    $testPath = Join-Path $repoRoot $relativePath
    if (-not (Test-Path -LiteralPath $testPath -PathType Leaf)) {
      throw "HarmonyOS PowerShell host test not found: $relativePath"
    }
    & $powerShell -NoLogo -NoProfile -File $testPath
    if ($LASTEXITCODE -ne 0) {
      throw "HarmonyOS PowerShell host test failed: $relativePath (exit code $LASTEXITCODE)"
    }
  }
} finally {
  Pop-Location
}

Write-Output 'HarmonyOS host tests passed'
