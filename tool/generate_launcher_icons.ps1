param(
    [string]$Python = 'python',
    [string]$Flutter = 'flutter',
    [string]$Dart = 'dart'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    & $Python tool/generate_launcher_icon.py
    if ($LASTEXITCODE -ne 0) { throw 'Icon source generation failed' }

    & $Flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }

    & $Dart run flutter_launcher_icons -f flutter_launcher_icons.yaml
    if ($LASTEXITCODE -ne 0) { throw 'flutter_launcher_icons failed' }

    foreach ($density in @('mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi')) {
        $mipmap = Join-Path $root "android/app/src/main/res/mipmap-$density"
        Copy-Item -LiteralPath (Join-Path $mipmap 'ic_launcher.png') `
            -Destination (Join-Path $mipmap 'ic_launcher_round.png') -Force
    }

    $adaptive = Join-Path $root 'android/app/src/main/res/mipmap-anydpi-v26'
    Copy-Item -LiteralPath (Join-Path $adaptive 'ic_launcher.xml') `
        -Destination (Join-Path $adaptive 'ic_launcher_round.xml') -Force

    & $Python tool/verify_launcher_icon_resources.py
    if ($LASTEXITCODE -ne 0) { throw 'Launcher icon resource verification failed' }
}
finally {
    Pop-Location
}
