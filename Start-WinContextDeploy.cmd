@echo off
setlocal EnableExtensions

set "SOURCE_DIR=%~dp0"
if "%SOURCE_DIR:~-1%"=="\" set "SOURCE_DIR=%SOURCE_DIR:~0,-1%"

set "PROJECT_MARKER=%SOURCE_DIR%\WinContextDeploy.psd1"
set "SCRIPT_MARKER=%SOURCE_DIR%\src\Invoke-WcdConfiguration.ps1"
set "TEMP_ROOT=C:\Temp"
set "TARGET_DIR=%TEMP_ROOT%\WinContextDeploy"
set "HISTORY_LOG=%SOURCE_DIR%\log.txt"

if not exist "%PROJECT_MARKER%" (
    echo [ERROR] WinContextDeploy.psd1 not found on the USB drive.
    pause
    exit /b 1
)

if not exist "%SCRIPT_MARKER%" (
    echo [ERROR] src\Invoke-WcdConfiguration.ps1 not found on the USB drive.
    pause
    exit /b 1
)

echo.
echo === Preparing local copy ===

if not exist "%TEMP_ROOT%" (
    mkdir "%TEMP_ROOT%"
    if errorlevel 1 (
        echo [ERROR] Cannot create %TEMP_ROOT%.
        pause
        exit /b 1
    )
)

if exist "%TARGET_DIR%" (
    echo Removing existing local folder: %TARGET_DIR%
    rmdir /s /q "%TARGET_DIR%"
    if exist "%TARGET_DIR%" (
        echo [ERROR] Cannot remove %TARGET_DIR%.
        pause
        exit /b 1
    )
)

mkdir "%TARGET_DIR%"
if errorlevel 1 (
    echo [ERROR] Cannot create %TARGET_DIR%.
    pause
    exit /b 1
)

echo Copying project to %TARGET_DIR%...
robocopy "%SOURCE_DIR%" "%TARGET_DIR%" /E /R:2 /W:1 /NFL /NDL /NJH /NJS /NP /XD ".git"
set "ROBOCOPY_EXIT=%ERRORLEVEL%"
if %ROBOCOPY_EXIT% GEQ 8 (
    echo [ERROR] Robocopy failed. Code: %ROBOCOPY_EXIT%
    pause
    exit /b %ROBOCOPY_EXIT%
)

echo.
echo === Running from local copy ===
echo The interactive PowerShell script is starting in this window.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%TARGET_DIR%\src\Invoke-WcdConfiguration.ps1" -ScriptUI EN -HistoryLogPath "%HISTORY_LOG%" -LocalProjectRoot "%TARGET_DIR%" -UsbSourceRoot "%SOURCE_DIR%"
set "SCRIPT_EXIT=%ERRORLEVEL%"

echo.
if "%SCRIPT_EXIT%"=="0" (
    echo Cleaning up local copy...
    rmdir /s /q "%TARGET_DIR%"

    if exist "%TARGET_DIR%" (
        echo [WARNING] Execution finished, but cleanup failed.
        echo Local copy preserved in %TARGET_DIR%.
        pause
        exit /b 2
    )

    echo Execution complete. History added to %HISTORY_LOG%
    exit /b 0
)

echo [WARNING] Execution finished with a problem or incomplete export.
echo Local copy preserved in %TARGET_DIR% for recovery.
pause
exit /b %SCRIPT_EXIT%
