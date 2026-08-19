[CmdletBinding()]
param(
  [string]$NativeSdkRoot = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$rustRoot = Join-Path $repoRoot 'rust'
$libsRoot = Join-Path $repoRoot 'ohos-native\entry\src\main\libs'
$clang = Join-Path $NativeSdkRoot 'llvm\bin\clang.exe'
$sysroot = Join-Path $NativeSdkRoot 'sysroot'
if (-not (Test-Path -LiteralPath $clang) -or -not (Test-Path -LiteralPath $sysroot)) {
  throw "HarmonyOS native SDK not found at: $NativeSdkRoot"
}

function Build-CoreTarget {
  param(
    [Parameter(Mandatory)] [string]$RustTarget,
    [Parameter(Mandatory)] [string]$ClangTarget,
    [Parameter(Mandatory)] [string]$Abi
  )
  $linkerKey = 'CARGO_TARGET_' + $RustTarget.ToUpperInvariant().Replace('-', '_') + '_LINKER'
  [Environment]::SetEnvironmentVariable($linkerKey, $clang, 'Process')
  $separator = [char]0x1f
  $env:CARGO_ENCODED_RUSTFLAGS = @(
    '-Clink-arg=-target',
    "-Clink-arg=$ClangTarget",
    "-Clink-arg=--sysroot=$sysroot",
    '-Clink-arg=-D__MUSL__'
  ) -join $separator
  & cargo build --manifest-path (Join-Path $rustRoot 'Cargo.toml') --release `
    --no-default-features --features ohos-native --target $RustTarget
  if ($LASTEXITCODE -ne 0) { throw "Rust build failed for $RustTarget" }
  $targetDir = Join-Path $rustRoot "target\$RustTarget\release"
  $abiDir = Join-Path $libsRoot $Abi
  New-Item -ItemType Directory -Force -Path $abiDir | Out-Null
  Copy-Item -LiteralPath (Join-Path $targetDir 'libsitemark_core.a') -Destination $abiDir -Force
  Copy-Item -LiteralPath (Join-Path $targetDir 'libsitemark_core.so') -Destination $abiDir -Force
}

try {
  Build-CoreTarget -RustTarget 'x86_64-unknown-linux-ohos' -ClangTarget 'x86_64-linux-ohos' -Abi 'x86_64'
  Build-CoreTarget -RustTarget 'aarch64-unknown-linux-ohos' -ClangTarget 'aarch64-linux-ohos' -Abi 'arm64-v8a'
} finally {
  Remove-Item Env:CARGO_ENCODED_RUSTFLAGS -ErrorAction SilentlyContinue
  Remove-Item Env:CARGO_TARGET_X86_64_UNKNOWN_LINUX_OHOS_LINKER -ErrorAction SilentlyContinue
  Remove-Item Env:CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER -ErrorAction SilentlyContinue
}

Get-FileHash -Algorithm SHA256 `
  (Join-Path $libsRoot 'x86_64\libsitemark_core.a'), `
  (Join-Path $libsRoot 'arm64-v8a\libsitemark_core.a') |
  Select-Object Path, Hash
