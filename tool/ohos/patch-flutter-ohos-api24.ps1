$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not (Test-Path (Join-Path $root 'ohos'))) {
  $root = (Get-Location).Path
}
$ohosRoot = Join-Path $root 'ohos'
$patch = Join-Path $PSScriptRoot 'patches\OhosAutoFillHelper.api24.ets'
if (-not (Test-Path $patch)) {
  throw "API24 AutoFill stub missing: $patch"
}

$searchRoots = @(
  (Join-Path $ohosRoot 'oh_modules'),
  (Join-Path $ohosRoot 'entry\oh_modules'),
  (Join-Path $ohosRoot 'har')
) | Where-Object { Test-Path $_ }

if ($searchRoots.Count -eq 0) {
  Write-Host 'API24_AUTOFILL_PATCH=skip (oh_modules not extracted yet)'
  return
}

$targets = Get-ChildItem -Path $searchRoots -Recurse -Filter 'OhosAutoFillHelper.ets' -ErrorAction SilentlyContinue
if (-not $targets) {
  Write-Host 'API24_AUTOFILL_PATCH=skip (helper not extracted yet)'
  return
}

$patched = 0
foreach ($target in $targets) {
  $text = Get-Content -Raw -LiteralPath $target.FullName
  if ($text -match 'SITEMARK_API24_AUTOFILL_STUB') {
    continue
  }
  Copy-Item -LiteralPath $patch -Destination $target.FullName -Force
  $patched++
  Write-Host ("API24_AUTOFILL_PATCHED=" + $target.FullName)
}

Write-Host ("API24_AUTOFILL_PATCH_COUNT=" + $patched)
