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

$success = Assert-ArkTsTestResult -Path (Join-Path $fixtures 'success.txt')
if ($success.TestsRun -ne 149 -or $success.Pass -ne 149) {
  throw 'Success fixture totals were not parsed correctly'
}

Assert-Throws { Assert-ArkTsTestResult -Path (Join-Path $fixtures 'failure.txt') } 'Failure: 1'
Assert-Throws { Assert-ArkTsTestResult -Path (Join-Path $fixtures 'error.txt') } 'Error: 1'
Assert-Throws { Assert-ArkTsTestResult -Path (Join-Path $fixtures 'missing-summary.txt') } 'summary'

Write-Output 'verify-test-result fixtures passed'
