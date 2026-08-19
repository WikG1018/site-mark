$ErrorActionPreference = 'Stop'

$app = 'C:\Users\Administrator\Documents\Codex\2026-07-15\new-chat\.worktrees\ohos'
$hap = Join-Path $app 'ohos\entry\build\default\outputs\default\entry-default-unsigned.hap'
$cacheDir = Join-Path $app 'tool\ohos\.cache'
$manifestPath = Join-Path $cacheDir 'NativeAssetsManifest.json'
$sourceJson = $null

$candidates = @(
  Get-ChildItem -Path (Join-Path $app '.dart_tool\flutter_build') -Filter 'native_assets.json' -Recurse -ErrorAction SilentlyContinue
  Get-ChildItem -Path (Join-Path $app 'build') -Filter 'native_assets.json' -Recurse -ErrorAction SilentlyContinue
) | Sort-Object LastWriteTime -Descending

if ($candidates) {
  $sourceJson = $candidates[0].FullName
  Write-Host ("SOURCE_JSON=" + $sourceJson)
}

$manifest = @{
  'format-version' = @(1, 0, 0)
  'native-assets' = @{
    'ohos_x64' = @{
      'package:sqlite3/src/ffi/libsqlite3.g.dart' = @('absolute', 'libsqlite3.so')
    }
    'linux_x64' = @{
      'package:sqlite3/src/ffi/libsqlite3.g.dart' = @('absolute', 'libsqlite3.so')
    }
  }
}

if ($sourceJson -and (Test-Path $sourceJson)) {
  try {
    $parsed = Get-Content -Raw -Encoding utf8 $sourceJson | ConvertFrom-Json
    if ($parsed.'native-assets') {
      $manifest = @{
        'format-version' = @(1, 0, 0)
        'native-assets' = @{}
      }
      foreach ($osProp in $parsed.'native-assets'.PSObject.Properties) {
        $assets = @{}
        foreach ($assetProp in $osProp.Value.PSObject.Properties) {
          $assets[$assetProp.Name] = @($assetProp.Value)
        }
        $manifest['native-assets'][$osProp.Name] = $assets
      }
      if (-not $manifest['native-assets'].ContainsKey('ohos_x64') -and $manifest['native-assets'].ContainsKey('linux_x64')) {
        $manifest['native-assets']['ohos_x64'] = $manifest['native-assets']['linux_x64']
      }
    }
  } catch {
    Write-Host ("PARSE_SOURCE_FAILED=" + $_.Exception.Message)
  }
}

New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
$jsonText = $manifest | ConvertTo-Json -Compress -Depth 8
[IO.File]::WriteAllText($manifestPath, $jsonText)
Write-Host ("MANIFEST_WRITTEN=" + $manifestPath)
Write-Host ("MANIFEST=" + $jsonText)

$assetDirs = @(
  (Join-Path $app 'build\ohos\intermediates\flutter\defaultDebug\flutter_assets'),
  (Join-Path $app 'ohos\entry\src\main\resources\rawfile\flutter_assets')
)
foreach ($dir in $assetDirs) {
  if (Test-Path $dir) {
    Copy-Item -Force $manifestPath (Join-Path $dir 'NativeAssetsManifest.json')
    Write-Host ("COPIED_ASSETS=" + (Join-Path $dir 'NativeAssetsManifest.json'))
  }
}

if (-not (Test-Path $hap)) {
  Write-Host 'HAP_MISSING skip zip inject'
  return
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($hap, [System.IO.Compression.ZipArchiveMode]::Update)
try {
  $entryName = 'resources/rawfile/flutter_assets/NativeAssetsManifest.json'
  $existing = @($zip.Entries | Where-Object { $_.FullName -eq $entryName -or $_.FullName -eq 'resources\rawfile\flutter_assets\NativeAssetsManifest.json' })
  foreach ($entry in $existing) {
    Write-Host ("DELETE_EXISTING=" + $entry.FullName)
    $entry.Delete()
  }
  $created = $zip.CreateEntry($entryName, [System.IO.Compression.CompressionLevel]::Optimal)
  $inputStream = [System.IO.File]::OpenRead($manifestPath)
  $outputStream = $created.Open()
  try {
    $inputStream.CopyTo($outputStream)
  } finally {
    $outputStream.Dispose()
    $inputStream.Dispose()
  }
  Write-Host ("HAP_INJECTED=" + $entryName + " SIZE=" + $created.Length)
} finally {
  $zip.Dispose()
}
Write-Host ("HAP_SIZE=" + (Get-Item $hap).Length)
