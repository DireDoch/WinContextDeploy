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
    echo [ERREUR] WinContextDeploy.psd1 introuvable dans la cle USB.
    pause
    exit /b 1
)

if not exist "%SCRIPT_MARKER%" (
    echo [ERREUR] src\Invoke-WcdConfiguration.ps1 introuvable dans la cle USB.
    pause
    exit /b 1
)

echo.
echo === Preparation de la copie locale ===

if not exist "%TEMP_ROOT%" (
    mkdir "%TEMP_ROOT%"
    if errorlevel 1 (
        echo [ERREUR] Impossible de creer %TEMP_ROOT%.
        pause
        exit /b 1
    )
)

if exist "%TARGET_DIR%" (
    echo Suppression du dossier local existant: %TARGET_DIR%
    rmdir /s /q "%TARGET_DIR%"
    if exist "%TARGET_DIR%" (
        echo [ERREUR] Impossible de supprimer %TARGET_DIR%.
        pause
        exit /b 1
    )
)

mkdir "%TARGET_DIR%"
if errorlevel 1 (
    echo [ERREUR] Impossible de creer %TARGET_DIR%.
    pause
    exit /b 1
)

echo Copie du projet vers %TARGET_DIR%...
robocopy "%SOURCE_DIR%" "%TARGET_DIR%" /E /R:2 /W:1 /NFL /NDL /NJH /NJS /NP /XD ".git"
set "ROBOCOPY_EXIT=%ERRORLEVEL%"
if %ROBOCOPY_EXIT% GEQ 8 (
    echo [ERREUR] Echec de copie Robocopy. Code: %ROBOCOPY_EXIT%
    pause
    exit /b %ROBOCOPY_EXIT%
)

echo.
echo === Execution depuis la copie locale ===
echo Le script PowerShell interactif demarre dans cette fenetre.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%TARGET_DIR%\src\Invoke-WcdConfiguration.ps1" -HistoryLogPath "%HISTORY_LOG%" -LocalProjectRoot "%TARGET_DIR%" -UsbSourceRoot "%SOURCE_DIR%"
set "SCRIPT_EXIT=%ERRORLEVEL%"

echo.
if "%SCRIPT_EXIT%"=="0" (
    echo Nettoyage de la copie locale...
    rmdir /s /q "%TARGET_DIR%"

    if exist "%TARGET_DIR%" (
        echo [AVERTISSEMENT] Execution terminee, mais le nettoyage a echoue.
        echo La copie locale est conservee dans %TARGET_DIR%.
        pause
        exit /b 2
    )

    echo Execution terminee. Historique ajoute a %HISTORY_LOG%
    exit /b 0
)

echo [AVERTISSEMENT] Execution terminee avec un probleme ou un export incomplet.
echo La copie locale est conservee dans %TARGET_DIR% pour recuperation.
pause
exit /b %SCRIPT_EXIT%