param(
  [ValidateSet('x86_64', 'aarch64')]
  [string]$Arch = 'x86_64'
)

$ErrorActionPreference = 'Stop'

$app = 'C:\Users\Administrator\Documents\Codex\2026-07-15\new-chat\.worktrees\ohos'
$src = Join-Path $app ("tool\ohos\.cache\libsqlite3-ohos\$Arch\libsqlite3.so")
if (-not (Test-Path $src)) { throw "compiled sqlite missing: $src" }

$destinations = @(
  (Join-Path $app "ohos\entry\libs\$Arch\libsqlite3.so"),
  (Join-Path $app "build\native_assets\ohos\libs\$Arch\libsqlite3.so"),
  (Join-Path $app "ohos\entry\build\default\intermediates\libs\default\$Arch\libsqlite3.so"),
  (Join-Path $app "ohos\entry\build\default\intermediates\stripped_native_libs\default\$Arch\libsqlite3.so")
)

foreach ($dest in $destinations) {
  $dir = Split-Path $dest -Parent
  if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  Copy-Item -Force $src $dest
  Write-Host ("REPLACED=" + $dest)
}

$hap = Join-Path $app 'ohos\entry\build\default\outputs\default\entry-default-unsigned.hap'
if (Test-Path $hap) {
  Add-Type -AssemblyName System.IO.Compression
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [System.IO.Compression.ZipFile]::Open($hap, [System.IO.Compression.ZipArchiveMode]::Update)
  try {
    $entries = @($zip.Entries | Where-Object { $_.Name -eq 'libsqlite3.so' })
    if (-not $entries) { throw "libsqlite3.so not found inside HAP: $hap" }
    foreach ($entry in $entries) {
      $name = $entry.FullName
      Write-Host ("HAP_ENTRY=" + $name + " OLD_SIZE=" + $entry.Length)
      $entry.Delete()
      $created = $zip.CreateEntry($name, [System.IO.Compression.CompressionLevel]::NoCompression)
      $inputStream = [System.IO.File]::OpenRead($src)
      $outputStream = $created.Open()
      try {
        $inputStream.CopyTo($outputStream)
      } finally {
        $outputStream.Dispose()
        $inputStream.Dispose()
      }
      Write-Host ("HAP_REPLACED=" + $name + " NEW_SIZE=" + $created.Length)
    }
  } finally {
    $zip.Dispose()
  }
  Write-Host ("HAP_UPDATED=" + $hap)
  Write-Host ("HAP_SIZE=" + (Get-Item $hap).Length)
}

$readelf = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native\llvm\bin\llvm-readelf.exe'
Write-Host '=== REPLACED NEEDED ==='
& $readelf -d $src | Select-String 'NEEDED|SONAME'
Write-Host '=== REPLACED EXPORTS ==='
& $readelf -s $src | Select-String 'GLOBAL +DEFAULT +.* sqlite3_open$'
