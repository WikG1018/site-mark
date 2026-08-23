Set-StrictMode -Version Latest

function Assert-ArkTsTestResult {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$Path
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "ArkTS test result was not generated: $Path"
  }

  $summaryPattern = '^Tests run:\s*(\d+),\s*Failure:\s*(\d+),\s*Error:\s*(\d+),\s*Pass:\s*(\d+),\s*Ignore:\s*(\d+)\s*$'
  $summary = Get-Content -LiteralPath $Path | Select-String -Pattern $summaryPattern | Select-Object -Last 1
  if ($null -eq $summary) {
    throw "ArkTS test result summary is missing or malformed: $Path"
  }

  $match = [regex]::Match($summary.Line, $summaryPattern)
  $testsRun = [int]$match.Groups[1].Value
  $failure = [int]$match.Groups[2].Value
  $errorCount = [int]$match.Groups[3].Value
  $pass = [int]$match.Groups[4].Value
  $ignore = [int]$match.Groups[5].Value
  if ($testsRun -lt 1) {
    throw "ArkTS test result contains no executed tests: $($summary.Line)"
  }
  if (($failure + $errorCount + $pass + $ignore) -ne $testsRun) {
    throw "ArkTS test result totals are inconsistent: $($summary.Line)"
  }
  if ($failure -ne 0 -or $errorCount -ne 0) {
    throw "ArkTS tests failed: $($summary.Line)"
  }

  [pscustomobject]@{
    TestsRun = $testsRun
    Failure = $failure
    Error = $errorCount
    Pass = $pass
    Ignore = $ignore
    Path = (Resolve-Path -LiteralPath $Path).Path
  }
}

function Assert-ArkTsWarnBudget {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$Path,
    [Parameter(Mandatory)]
    [int]$MaxWarnings
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "ArkTS build log was not generated: $Path"
  }

  $warnCount = @(Select-String -LiteralPath $Path -Pattern 'ArkTS:WARN' -SimpleMatch).Count
  if ($warnCount -gt $MaxWarnings) {
    throw ("ArkTS warnings ({0}) exceed the tracked budget ({1}). Fix the new warnings, " +
      'or knowingly raise the budget in tool/ohos-native/build-hap.ps1 after review.') -f $warnCount, $MaxWarnings
  }

  [pscustomobject]@{
    WarnCount = $warnCount
    MaxWarnings = $MaxWarnings
    Path = (Resolve-Path -LiteralPath $Path).Path
  }
}
