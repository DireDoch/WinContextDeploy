@echo off
setlocal EnableExtensions

rem WinContextDeploy launcher.
rem
rem   WinContextDeploy.cmd            run in place (correct for a git clone)
rem   WinContextDeploy.cmd -Usb       copy to %TEMP%, run there, write the
rem                                   history log back, clean up
rem   WinContextDeploy.cmd -FR|-EN    force the UI language
rem
rem Without -Usb nothing is copied and nothing is deleted. The UI language
rem defaults from the system locale, so neither flag is normally needed.

set "SOURCE_DIR=%~dp0"
if "%SOURCE_DIR:~-1%"=="\" set "SOURCE_DIR=%SOURCE_DIR:~0,-1%"

set "USE_USB="
set "UI_ARGS="

:parse
if "%~1"=="" goto parsed
if /I "%~1"=="-Usb"  ( set "USE_USB=1"                & shift & goto parse )
if /I "%~1"=="/Usb"  ( set "USE_USB=1"                & shift & goto parse )
if /I "%~1"=="-FR"   ( set "UI_ARGS=-ScriptUI FR"     & shift & goto parse )
if /I "%~1"=="-EN"   ( set "UI_ARGS=-ScriptUI EN"     & shift & goto parse )
if /I "%~1"=="-Help" ( goto usage )
if /I "%~1"=="/?"    ( goto usage )
echo [ERROR] Unknown option: %~1
goto usage

:parsed

if not exist "%SOURCE_DIR%\WinContextDeploy.psd1" (
    echo [ERROR] WinContextDeploy.psd1 not found next to this launcher.
    pause
    exit /b 1
)

if not exist "%SOURCE_DIR%\src\Invoke-WcdConfiguration.ps1" (
    echo [ERROR] src\Invoke-WcdConfiguration.ps1 not found next to this launcher.
    pause
    exit /b 1
)

if defined USE_USB goto usb

rem --- Default: run in place ---------------------------------------------
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SOURCE_DIR%\src\Invoke-WcdConfiguration.ps1" %UI_ARGS%
exit /b %ERRORLEVEL%

rem --- -Usb: copy to a private folder under %TEMP%, run, export, clean up --
rem PowerShell off removable media is slow, and the key can be pulled
rem mid-run. The copy lives under %TEMP% in a uniquely named folder, so
rem concurrent runs cannot collide and no pre-existing folder is ever wiped.
:usb
set "TARGET_DIR=%TEMP%\WinContextDeploy-%RANDOM%%RANDOM%"
set "HISTORY_LOG=%SOURCE_DIR%\log.txt"

if exist "%TARGET_DIR%" (
    echo [ERROR] Temporary folder %TARGET_DIR% already exists. Run again.
    pause
    exit /b 1
)

echo.
echo === Preparing local copy ===
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

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%TARGET_DIR%\src\Invoke-WcdConfiguration.ps1" %UI_ARGS% -HistoryLogPath "%HISTORY_LOG%" -LocalProjectRoot "%TARGET_DIR%" -UsbSourceRoot "%SOURCE_DIR%"
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

:usage
echo.
echo Usage: WinContextDeploy.cmd [-Usb] [-FR^|-EN]
echo.
echo   (no option)  Run in place. Nothing is copied, nothing is deleted.
echo   -Usb         Copy to %%TEMP%%, run there, append the history log back
echo                next to this launcher, then remove the copy.
echo   -FR ^| -EN    Force the UI language. Defaults from the system locale.
echo.
exit /b 1
