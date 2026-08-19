param(
  [ValidateSet('x86_64', 'aarch64')]
  [string]$Arch = 'x86_64'
)

$ErrorActionPreference = 'Stop'

$app = 'C:\Users\Administrator\Documents\Codex\2026-07-15\new-chat\.worktrees\ohos'
$native = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native'
$clang = Join-Path $native 'llvm\bin\clang.exe'
$sysroot = Join-Path $native 'sysroot'
$cache = Join-Path $app 'tool\ohos\.cache\sqlite-amalgamation'
$zipPath = Join-Path $cache 'sqlite-amalgamation-3500200.zip'
$srcDir = Join-Path $cache 'sqlite-amalgamation-3500200'
$src = Join-Path $srcDir 'sqlite3.c'
$outDir = Join-Path $app ("tool\ohos\.cache\libsqlite3-ohos\$Arch")
$outSo = Join-Path $outDir 'libsqlite3.so'
$target = if ($Arch -eq 'x86_64') { 'x86_64-linux-ohos' } else { 'aarch64-linux-ohos' }

if (-not (Test-Path $clang)) { throw "OH NDK clang missing: $clang" }
if (-not (Test-Path $sysroot)) { throw "OH NDK sysroot missing: $sysroot" }

New-Item -ItemType Directory -Force -Path $cache | Out-Null
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

if (-not (Test-Path $src)) {
  if (-not (Test-Path $zipPath)) {
    Write-Host '=== Download sqlite amalgamation 3500200 ==='
    Invoke-WebRequest -Uri 'https://sqlite.org/2025/sqlite-amalgamation-3500200.zip' -OutFile $zipPath
  }
  Write-Host '=== Expand amalgamation ==='
  Expand-Archive -Path $zipPath -DestinationPath $cache -Force
}

if (-not (Test-Path $src)) { throw "sqlite3.c missing after extract: $src" }

$defines = @(
  'SQLITE_ENABLE_DBSTAT_VTAB',
  'SQLITE_ENABLE_FTS5',
  'SQLITE_ENABLE_RTREE',
  'SQLITE_ENABLE_MATH_FUNCTIONS',
  'SQLITE_DQS=0',
  'SQLITE_DEFAULT_MEMSTATUS=0',
  'SQLITE_TEMP_STORE=2',
  'SQLITE_MAX_EXPR_DEPTH=0',
  'SQLITE_STRICT_SUBTYPE=1',
  'SQLITE_OMIT_AUTHORIZATION',
  'SQLITE_OMIT_DECLTYPE',
  'SQLITE_OMIT_DEPRECATED',
  'SQLITE_OMIT_PROGRESS_CALLBACK',
  'SQLITE_OMIT_SHARED_CACHE',
  'SQLITE_OMIT_TCL_VARIABLE',
  'SQLITE_OMIT_TRACE',
  'SQLITE_USE_ALLOCA',
  'SQLITE_ENABLE_SESSION',
  'SQLITE_ENABLE_PREUPDATE_HOOK',
  'SQLITE_UNTESTABLE',
  'SQLITE_HAVE_ISNAN',
  'SQLITE_HAVE_LOCALTIME_R',
  'SQLITE_THREADSAFE=1'
)

$defineFlags = @()
foreach ($item in $defines) {
  $defineFlags += "-D$item"
}

Write-Host "=== Compile $outSo for $target ==="
& $clang -shared -fPIC -O2 --target=$target --sysroot=$sysroot @defineFlags -o $outSo $src -lm
if ($LASTEXITCODE -ne 0) { throw "clang failed: $LASTEXITCODE" }

$readelf = Join-Path $native 'llvm\bin\llvm-readelf.exe'
Write-Host '=== NEEDED ==='
& $readelf -d $outSo | Select-String 'NEEDED|SONAME'
Write-Host '=== SQLITE EXPORTS ==='
& $readelf -s $outSo | Select-String 'GLOBAL +DEFAULT +.* sqlite3_open$'
Write-Host ("SQLITE_SO=" + $outSo)
Write-Host ("SQLITE_SIZE=" + (Get-Item $outSo).Length)
