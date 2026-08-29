@echo off
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& { Set-Location -LiteralPath '%SCRIPT_DIR%'; $result = Invoke-Pester .\tests\*.Tests.ps1 -Output Detailed -PassThru; if ($result.FailedCount -gt 0) { exit 1 } }"
set "TEST_EXIT=%ERRORLEVEL%"

echo.
if "%TEST_EXIT%"=="0" (
    echo Tous les tests Pester sont passes.
) else (
    echo Des tests Pester ont echoue.
)

pause
exit /b %TEST_EXIT%
