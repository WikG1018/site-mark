$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\TestResult.ps1')

$fixtures = Join-Path $PSScriptRoot 'fixtures'

function Assert-Throws([scriptblock]$Action, [string]$ExpectedText) {
  $thrown = $false
  try {
    & $Action
  } catch {
    $thrown = $true
    if ($_.Exception.Message -notlike "*$ExpectedText*") {
      throw "Expected '$ExpectedText' but got '$($_.Exception.Message)'"
    }
  }
  if (-not $thrown) {
    throw "Expected an exception containing '$ExpectedText'"
  }
}

$clean = Assert-ArkTsWarnBudget -Path (Join-Path $fixtures 'warn-budget-clean.log') -MaxWarnings 0
if ($clean.WarnCount -ne 0) {
  throw 'Clean fixture should report zero warnings'
}

$loaded = Assert-ArkTsWarnBudget -Path (Join-Path $fixtures 'warn-budget-three.log') -MaxWarnings 3
if ($loaded.WarnCount -ne 3) {
  throw "Three-warning fixture should report 3 warnings, got $($loaded.WarnCount)"
}

Assert-Throws { Assert-ArkTsWarnBudget -Path (Join-Path $fixtures 'warn-budget-three.log') -MaxWarnings 2 } 'exceed'
Assert-Throws { Assert-ArkTsWarnBudget -Path (Join-Path $fixtures 'warn-budget-missing.log') -MaxWarnings 5 } 'not generated'

Write-Output 'verify-warn-budget fixtures passed'
