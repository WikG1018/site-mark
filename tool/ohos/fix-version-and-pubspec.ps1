$ErrorActionPreference = 'Stop'
$jsonPath = 'C:\Users\Administrator\Development\flutter-ohos\bin\cache\flutter.version.json'
$verPath = 'C:\Users\Administrator\Development\flutter-ohos\version'
$pubspec = 'C:\Users\Administrator\Development\sitemark-ohos-empty\pubspec.yaml'

$json = @'
{
  "frameworkVersion": "3.27.4",
  "channel": "[user-branch]",
  "repositoryUrl": "https://gitcode.com/CPF-Flutter/flutter_flutter.git",
  "frameworkRevision": "269265738b3e388113f81f82f5aaa101011f3e18",
  "frameworkCommitDate": "2026-07-28 16:37:44 +0800",
  "engineRevision": "e672b006cb34c921db85b8e2f482ed3144a4574b",
  "dartSdkVersion": "3.6.2",
  "devToolsVersion": "2.40.0",
  "flutterVersion": "3.27.4"
}
'@
$utf8 = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($jsonPath, $json, $utf8)
[System.IO.File]::WriteAllText($verPath, "3.27.4`n", [System.Text.Encoding]::ASCII)

Write-Host 'JSON_BYTES_HEAD'
[System.BitConverter]::ToString([System.IO.File]::ReadAllBytes($jsonPath)[0..7])

$src = Get-Content $pubspec -Raw
$src = [regex]::Replace($src, "(?m)^\s*flutter_test:\r?\n\s*sdk: flutter\r?\n", "")
[System.IO.File]::WriteAllText($pubspec, $src, $utf8)

Write-Host 'PUBSPEC_SNIP'
Select-String -Path $pubspec -Pattern 'flutter_test|dev_dependencies|flutter_lints' | ForEach-Object { $_.Line }
Write-Host 'VERSION_NOW'
Get-Content $verPath
Write-Host 'JSON_NOW'
Get-Content $jsonPath
