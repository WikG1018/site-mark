@echo off
setlocal
set "HVIGORW_HOME=%~dp0"
set "PATCH_SCRIPT=%HVIGORW_HOME%..\tool\ohos\patch-flutter-ohos-api24.ps1"
if exist "%PATCH_SCRIPT%" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%PATCH_SCRIPT%"
  if errorlevel 1 exit /b 1
)
set "DEVECO_HVIGORW=C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat"
if not exist "%DEVECO_HVIGORW%" (
  echo ERROR: DevEco hvigorw.bat not found: %DEVECO_HVIGORW%
  exit /b 1
)
call "%DEVECO_HVIGORW%" %*
exit /b %ERRORLEVEL%
