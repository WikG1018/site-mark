$ErrorActionPreference = 'Continue'
$hap = 'C:\Users\Administrator\Documents\Codex\2026-07-15\new-chat\.worktrees\ohos\ohos\entry\build\default\outputs\default\entry-default-unsigned.hap'
$tmp = 'C:\Users\Administrator\Documents\Codex\2026-07-15\new-chat\.worktrees\ohos\tool\ohos\.cache\hap-kernel-check'
$kernel = Join-Path $tmp 'kernel_blob.bin'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
if (Test-Path $kernel) { Remove-Item -Force $kernel }
Write-Host ("HAP=" + $hap)
Write-Host ("HAP_EXISTS=" + (Test-Path $hap))
if (Test-Path $hap) {
  $item = Get-Item $hap
  Write-Host ("HAP_SIZE=" + $item.Length)
  Write-Host ("HAP_MTIME=" + $item.LastWriteTime.ToString('s'))
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($hap)
$entry = $zip.Entries | Where-Object { $_.FullName -match 'kernel_blob.bin$' } | Select-Object -First 1
Write-Host ("KERNEL_ENTRY=" + $entry.FullName)
Write-Host ("KERNEL_ENTRY_LEN=" + $entry.Length)
[System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $kernel, $true)
$zip.Dispose()
$bytes = [IO.File]::ReadAllBytes($kernel)
$ascii = [Text.Encoding]::ASCII.GetString($bytes)
$uni = [Text.Encoding]::Unicode.GetString($bytes)
$needles = @(
  'SITEMARK_DB',
  'SITEMARK_DB_V2',
  'SITEMARK_DB_V3',
  'sitemark_db_open.log',
  '_openOhosNativeDatabase',
  'shareAcrossIsolates',
  'SITEMARK_OHOS',
  'constructed',
  'after_native',
  'before_open',
  'before_native',
  'NativeDatabase',
  '_useSameIsolateNativeDatabase',
  'sqlite_setup',
  'mark_failed',
  'SITEMARK_TASK11'
)
foreach ($p in $needles) {
  Write-Host ("ASCII " + $p + "=" + $ascii.Contains($p) + " UNICODE=" + $uni.Contains($p))
}
Write-Host ("KERNEL_SIZE=" + $bytes.Length)
