# Invoke-WcdConfiguration.ps1
# Script central qui charge les helpers, execute chaque module de configuration
# et affiche un diagnostic complet avec debug.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\src\Invoke-WcdConfiguration.ps1
#   powershell -ExecutionPolicy Bypass -File .\src\Invoke-WcdConfiguration.ps1 -FormFactor Laptop
#   powershell -ExecutionPolicy Bypass -File .\src\Invoke-WcdConfiguration.ps1 -Language en-US -FormFactor Desktop -Environment Vdi -NonInteractive
#   powershell -ExecutionPolicy Bypass -File .\src\Invoke-WcdConfiguration.ps1 -FormFactor Desktop -LogPath C:\temp\log.txt
#   powershell -ExecutionPolicy Bypass -File .\src\Invoke-WcdConfiguration.ps1 -HistoryLogPath D:\log.txt -LocalProjectRoot C:\Temp\WinContextDeploy

[CmdletBinding()]
param(
    [ValidateSet('fr-CA', 'en-US')]
    [string]$Language,

    [ValidateSet('Laptop', 'Desktop')]
    [string]$FormFactor,

    [ValidateSet('Workstation', 'Vdi')]
    [string]$Environment,

    [string]$LogPath,

    [string]$ConfigPath,

    [switch]$OpenApps,

    [string]$OptionalTools,

    [string]$HistoryLogPath,

    [string]$LocalProjectRoot,

    [string]$UsbSourceRoot,

    [switch]$NonInteractive,

    [ValidateSet('FR', 'EN')]
    [string]$ScriptUI = 'FR'
)

# --- Table de traduction / Translation table ---
$T = if ($ScriptUI -eq 'EN') {
    @{
        BannerSubtitle          = 'Post-image configuration and quick device diagnostics'
        Checklist               = @{
            Taskbar        = 'Taskbar aligned left'
            SoftwareCenter = 'Software Center'
            DeviceManager  = 'Device Manager'
            Outlook        = 'Outlook'
            Signature      = 'Mail signature'
            Vpn            = 'VPN client'
            Wifi           = 'Wi-Fi'
            Snipping       = 'Snipping Tool'
            Erp            = 'ERP client'
            Language       = 'Display language'
            Keyboard       = 'Keyboard layout'
            Decimal        = 'Decimal separator'
            Power          = 'Power options'
            Terminal       = 'Terminal emulator'
            Teams          = 'Teams'
            NetworkDrives  = 'Network drives'
            Sync           = 'Account sync'
            Vdi            = 'Citrix / VDI'
            Cad            = 'CAD viewer'
            Printers       = 'Printers'
            Desktop        = 'Windows desktop'
            Helpdesk       = 'Helpdesk portal'
            Favorites      = 'Browser favorites'
        }
        KeyLaptop               = 'L'
        KeyDesktop              = 'D'
        KeyWorkstation          = 'W'
        KeyVdi                  = 'V'
        KeyYes                  = 'Y'
        KeyNo                   = 'N'
        Labels                  = @{
            Laptop      = 'Laptop'
            Desktop     = 'Desktop'
            Workstation = 'Workstation'
            Vdi         = 'Citrix / VDI'
            Yes         = 'Yes'
            No          = 'No'
        }
        NoChoicesAvailable      = 'No choices available.'
        DefaultLabel            = '[default]'
        InvalidChoice           = 'Invalid choice. Try again.'
        NavHint                 = 'Use Left/Right to change, then Enter to confirm.'
        FallbackEnterHint       = 'Press Enter to continue'
        EngineerBoxTitle        = 'Engineer configuration - multiple choices'
        EngineerCombineHint     = '  Combine numbers for multiple choices (e.g: 12 = Nvidia + GPS)'
        EngineerChoicePrompt    = '  Your choice'
        EngineerAtLeastOne      = '  Please enter at least one number.'
        EngineerInvalidChoice   = '  Invalid choice. Valid numbers: {0}'
        EngineerSelection       = '  Selection: {0}'
        WaitEnterFinish         = 'Press Enter to finish the script.'
        WaitEnterExport         = 'Press Enter to finish the script and export logs to the removable drive.'
        PromptLanguage          = 'Windows system language'
        PromptLanguageDesc      = '  fr-CA = French Canadian Windows interface  |  en-US = American English'
        PromptDeviceType        = 'Device type (Portable or Bureau?)'
        PromptDeviceDesc1       = '  Portable = laptop with battery  |  Bureau = desktop without battery'
        PromptDeviceDesc2       = '  Affects sleep and power management settings.'
        PromptUsage             = 'Device usage (Principal = local | Secondaire = Citrix?)'
        PromptUsageDesc1        = '  Principal = local physical device  -> opens SAP Front End and MicroFocus files'
        PromptUsageDesc2        = '  Secondaire = Citrix device         -> opens the Citrix Workspace download page'
        PromptOpenApps          = 'Open {0} configuration applications?'
        PromptOpenAppsDesc1     = '  Automatically opens: Outlook, Teams, Software Center, GlobalProtect, ServiceNow.'
        PromptOpenAppsDesc2     = '  Answer Yes unless applications were already opened manually.'
        PromptEngineer          = 'Engineer computer? (adds Nvidia / GPS)'
        PromptEngineerDesc1     = '  Adds tools: Nvidia App, GPS portal.'
        PromptEngineerDesc2     = '  Answer No for a standard device.'
        MissingModuleData       = 'No data returned by the module.'
        MissingStepTech         = 'Missing technical step: {0}'
        ApplicationManualDetail = 'Launch skipped (answered No). Manual verification required.'
        StandardManualDetail    = 'Must be done manually.'
        SecondaryNA             = 'Not applicable on secondary device.'
        DeskWindowsDetail       = 'Must be done manually on the Windows desktop.'
        StepCount               = 'step(s)'
        ModuleResult            = '  Result: {0} ({1} steps, {2} failures, {3} warnings, {4:N0}ms)'
        ModuleNotFound          = 'Module not found: {0}'
        ModuleLoadFail          = 'Failed to load module {0}: {1}'
        StatusCrash             = 'CRASH'
        StatusPartial           = 'PARTIAL'
        StatusWarning           = 'WARNING'
        StatusOk                = 'OK'
        StatusError             = 'ERROR'
        FailDetails             = 'Failures: {0}'
        WarningDetails          = 'Warnings: {0}'
        SectionByModule         = 'FINAL DIAGNOSTIC - BY MODULE'
        SectionByStep           = 'FINAL DIAGNOSTIC - BY STEP'
        SummaryLine             = 'Summary: {0} OK, {1} warning(s), {2} error(s), {3} manual, {4} N/A.'
        LogOutput               = 'Full log: {0}'
        AutoExportLog           = 'Automatic log export to: {0}'
        HistoryExported         = 'History added to: {0}'
        HistoryExportFailed     = '[WARNING] History export failed. Local copy preserved. Detail: {0}'
        FatalHelpersMissing     = '[FATAL ERROR] WcdHelpers.ps1 not found in: {0}'
        FatalConfig             = '[FATAL ERROR] {0}'
        FatalLogConflict        = '[FATAL ERROR] -LogPath and -HistoryLogPath must be different.'
        DiagStyleInProgress     = 'IN PROGRESS'
        DiagStyleOk             = 'OK'
        DiagStyleWarning        = 'WARNING'
        DiagStyleError          = 'ERROR'
        DiagStyleManual         = 'MANUAL'
        DiagStyleNA             = 'N/A'
        DiagFinalByModule       = '         FINAL DIAGNOSTIC - BY MODULE         '
        DiagFinalByStep         = '         FINAL DIAGNOSTIC - BY STEP           '
        LogEndSummary           = '=== Execution complete: {0} OK, {1} warning(s), {2} error(s), {3} manual, {4} N/A ==='
    }
} else {
    @{
        BannerSubtitle          = 'Configuration post-image et diagnostic rapide du poste'
        Checklist               = @{
            Taskbar        = 'Taskbar a gauche'
            SoftwareCenter = 'Software Center'
            DeviceManager  = 'Device Manager'
            Outlook        = 'Outlook'
            Signature      = 'Signature courriel'
            Vpn            = 'Client VPN'
            Wifi           = 'Wifi'
            Snipping       = 'Outil Capture'
            Erp            = 'Client ERP'
            Language       = 'Langue d affichage'
            Keyboard       = 'Disposition clavier'
            Decimal        = 'Separateur decimal'
            Power          = 'Options d alimentation'
            Terminal       = 'Emulateur terminal'
            Teams          = 'Teams'
            NetworkDrives  = 'Lecteurs reseau'
            Sync           = 'Synchronisation du compte'
            Vdi            = 'Citrix / VDI'
            Cad            = 'Visionneuse CAO'
            Printers       = 'Imprimantes'
            Desktop        = 'Bureau Windows'
            Helpdesk       = 'Portail de soutien'
            Favorites      = 'Favoris du navigateur'
        }
        KeyLaptop               = 'P'
        KeyDesktop              = 'B'
        KeyWorkstation          = 'P'
        KeyVdi                  = 'S'
        KeyYes                  = 'O'
        KeyNo                   = 'N'
        Labels                  = @{
            Laptop      = 'Portable'
            Desktop     = 'Bureau'
            Workstation = 'Principal'
            Vdi         = 'Citrix'
            Yes         = 'Oui'
            No          = 'Non'
        }
        NoChoicesAvailable      = 'Aucun choix disponible.'
        DefaultLabel            = '[defaut]'
        InvalidChoice           = 'Choix invalide. Reessayer.'
        NavHint                 = 'Utiliser Gauche/Droite pour changer, puis Entree pour confirmer.'
        FallbackEnterHint       = 'Appuyer sur Enter pour continuer'
        EngineerBoxTitle        = 'Configuration ingenieur - choix multiples'
        EngineerCombineHint     = '  Combiner les numeros pour plusieurs choix (ex: 12 = Nvidia + GPS)'
        EngineerChoicePrompt    = '  Votre choix'
        EngineerAtLeastOne      = '  Veuillez entrer au moins un numero.'
        EngineerInvalidChoice   = '  Choix invalide. Numeros valides: {0}'
        EngineerSelection       = '  Selection: {0}'
        WaitEnterFinish         = 'Cliquer sur Enter pour terminer le script.'
        WaitEnterExport         = 'Cliquer sur Enter pour terminer le script et envoyer les logs vers le disque amovible.'
        PromptLanguage          = 'Langue du systeme Windows'
        PromptLanguageDesc      = '  fr-CA = interface Windows en francais canadien  |  en-US = anglais americain'
        PromptDeviceType        = 'Type de poste (Portable ou Bureau ?)'
        PromptDeviceDesc1       = '  Portable = laptop avec batterie  |  Bureau = ordinateur fixe sans batterie'
        PromptDeviceDesc2       = "  Affecte les parametres de veille et de gestion d energie."
        PromptUsage             = 'Usage du poste (Principal = local | Secondaire = Citrix ?)'
        PromptUsageDesc1        = '  Principal = poste physique local  -> ouvre les fichiers de SAP Front End et MicroFocus'
        PromptUsageDesc2        = '  Secondaire = poste Citrix         -> ouvre la page de telechargement Citrix Workspace'
        PromptOpenApps          = 'Ouvrir les applications de configuration {0} ?'
        PromptOpenAppsDesc1     = '  Ouvre automatiquement : Outlook, Teams, Software Center, GlobalProtect, ServiceNow.'
        PromptOpenAppsDesc2     = '  Repondre Oui sauf si les applications ont deja ete ouvertes manuellement.'
        PromptEngineer          = "Ordinateur d ingenieur ? (ajoute Nvidia / GPS)"
        PromptEngineerDesc1     = '  Ajoute des outils : Nvidia App, portail GPS.'
        PromptEngineerDesc2     = '  Repondre Non pour un poste standard.'
        MissingModuleData       = 'Aucune donnee retournee par le module.'
        MissingStepTech         = 'Etape technique manquante: {0}'
        ApplicationManualDetail = 'Ouverture ignoree (repondu Non). Verification manuelle requise.'
        StandardManualDetail    = 'A faire manuellement.'
        SecondaryNA             = 'Non applicable sur poste secondaire.'
        DeskWindowsDetail       = 'A faire manuellement sur le bureau Windows.'
        StepCount               = 'etape(s)'
        ModuleResult            = '  Resultat: {0} ({1} etapes, {2} echecs, {3} avertissements, {4:N0}ms)'
        ModuleNotFound          = 'Module introuvable: {0}'
        ModuleLoadFail          = 'Echec chargement module {0}: {1}'
        StatusCrash             = 'CRASH'
        StatusPartial           = 'PARTIEL'
        StatusWarning           = 'WARNING'
        StatusOk                = 'OK'
        StatusError             = 'ERREUR'
        FailDetails             = 'Echecs: {0}'
        WarningDetails          = 'Avertissements: {0}'
        SectionByModule         = 'DIAGNOSTIC FINAL - PAR MODULE'
        SectionByStep           = 'DIAGNOSTIC FINAL - PAR ETAPE'
        SummaryLine             = 'Resume: {0} OK, {1} warning(s), {2} erreur(s), {3} manuel(le)(s), {4} N/A.'
        LogOutput               = 'Log complet: {0}'
        AutoExportLog           = 'Export automatique des logs vers: {0}'
        HistoryExported         = 'Historique ajoute dans: {0}'
        HistoryExportFailed     = '[AVERTISSEMENT] Export historique impossible. La copie locale est conservee. Detail: {0}'
        FatalHelpersMissing     = '[ERREUR FATALE] WcdHelpers.ps1 introuvable dans: {0}'
        FatalConfig             = '[ERREUR FATALE] {0}'
        FatalLogConflict        = '[ERREUR FATALE] -LogPath et -HistoryLogPath doivent etre differents.'
        DiagStyleInProgress     = 'EN COURS'
        DiagStyleOk             = 'OK'
        DiagStyleWarning        = 'WARNING'
        DiagStyleError          = 'ERREUR'
        DiagStyleManual         = 'MANUEL'
        DiagStyleNA             = 'N/A'
        DiagFinalByModule       = '         DIAGNOSTIC FINAL - PAR MODULE         '
        DiagFinalByStep         = '         DIAGNOSTIC FINAL - PAR ETAPE          '
        LogEndSummary           = '=== Fin execution: {0} OK, {1} warning(s), {2} erreur(s), {3} manuel(le)(s), {4} N/A ==='
    }
}

# --- Resolution du dossier de scripts ---
$scriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptDir)) {
    $scriptDir = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
}
if ([string]::IsNullOrWhiteSpace($scriptDir)) {
    $scriptDir = (Get-Location).Path
}

# --- Chargement des helpers partages ---
$helpersPath = Join-Path $scriptDir 'WcdHelpers.ps1'
if (-not (Test-Path -LiteralPath $helpersPath)) {
    Write-Host ($T.FatalHelpersMissing -f $scriptDir) -ForegroundColor Red
    exit 1
}
. $helpersPath

# --- Chargement de la configuration statique ---
try {
    $script:WcdConfig = Import-WcdConfig -ConfigPath $ConfigPath
} catch {
    Write-Host ($T.FatalConfig -f $_.Exception.Message) -ForegroundColor Red
    exit 1
}

function Show-WcdBanner {
    [CmdletBinding()]
    param()

    # Logo: banner.txt at the project root. To rebrand, paste ASCII art from
    # https://patorjk.com/software/taag/ into that file and save. Art wider than
    # the console (or a missing file) falls back to a plain title.
    $bannerPath = Join-Path (Split-Path -Path $scriptDir -Parent) 'banner.txt'
    $bannerLines = @()
    if (Test-Path -LiteralPath $bannerPath) {
        $bannerLines = @(Get-Content -LiteralPath $bannerPath -ErrorAction SilentlyContinue)
    }

    $consoleWidth = 80
    try {
        $reportedWidth = $Host.UI.RawUI.WindowSize.Width
        if ($reportedWidth -gt 0) { $consoleWidth = $reportedWidth }
    } catch { }

    $fits = $bannerLines.Count -gt 0
    foreach ($line in $bannerLines) {
        if ($line.Length -ge $consoleWidth) { $fits = $false; break }
    }

    Write-Host ''
    if ($fits) {
        foreach ($line in $bannerLines) {
            Write-Host $line -ForegroundColor Cyan
        }
    } else {
        Write-Host 'WinContextDeploy' -ForegroundColor Cyan
    }
    Write-Host $T.BannerSubtitle -ForegroundColor DarkGray
    Write-Host ''
}

function Read-WcdChoice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Choices,

        [Parameter(Mandatory)]
        [string]$DefaultKey,

        [string[]]$Description = @()
    )

    $entries = @($Choices.GetEnumerator())
    if ($entries.Count -eq 0) {
        throw $T.NoChoicesAvailable
    }

    $selectedIndex = 0
    for ($i = 0; $i -lt $entries.Count; $i++) {
        if ([string]$entries[$i].Key -eq $DefaultKey) {
            $selectedIndex = $i
            break
        }
    }

    # Mode texte de secours: utilise UNIQUEMENT lorsque la lecture clavier
    # interactive n'est pas disponible (entree redirigee, hote sans RawUI).
    function Invoke-WcdChoiceFallback {
        foreach ($desc in $Description) { Write-Host $desc -ForegroundColor DarkGray }
        while ($true) {
            $suffix = ($entries | ForEach-Object {
                if ([string]$_.Key -eq $DefaultKey) {
                    ('{0}= {1} ' + $T.DefaultLabel) -f $_.Key, (Get-WcdChoiceLabel -Value $_.Value -Labels $T.Labels)
                } else {
                    '{0}= {1}' -f $_.Key, (Get-WcdChoiceLabel -Value $_.Value -Labels $T.Labels)
                }
            }) -join ' | '

            $answer = Read-Host ('{0} ({1})' -f $Prompt, $suffix)
            if ([string]::IsNullOrWhiteSpace($answer)) {
                return $Choices[$DefaultKey]
            }

            $normalized = $answer.Trim().ToUpperInvariant()
            if ($Choices.Contains($normalized)) {
                return $Choices[$normalized]
            }

            Write-Host $T.InvalidChoice -ForegroundColor Yellow
        }
    }

    # Determiner si on peut lire les fleches du clavier. On ne bascule en mode
    # texte que si l'entree est redirigee ou si l'hote n'expose pas RawUI: la
    # geometrie du tampon n'intervient plus, donc les questions 3-4-5 restent
    # interactives comme la premiere.
    $canUseArrowKeys = $true
    try {
        if ([System.Console]::IsInputRedirected) { $canUseArrowKeys = $false }
        $null = $Host.UI.RawUI
    } catch {
        $canUseArrowKeys = $false
    }

    if (-not $canUseArrowKeys) {
        return Invoke-WcdChoiceFallback
    }

    # Partie statique (ecrite une seule fois): question, description, aide.
    Write-Host $Prompt -ForegroundColor Cyan
    foreach ($desc in $Description) { Write-Host $desc -ForegroundColor DarkGray }
    Write-Host $T.NavHint -ForegroundColor DarkGray

    # La ligne d'options est redessinee sur place via un retour chariot (`r).
    # Aucune coordonnee absolue n'est utilisee, donc le rendu reste fiable
    # partout dans le tampon, y compris tout en bas (apres defilement).
    while ($true) {
        Write-Host "`r" -NoNewline
        for ($i = 0; $i -lt $entries.Count; $i++) {
            $label = '{0}: {1}' -f $entries[$i].Key, (Get-WcdChoiceLabel -Value $entries[$i].Value -Labels $T.Labels)
            if ($i -eq $selectedIndex) {
                Write-Host ('[ {0} ] ' -f $label) -NoNewline -ForegroundColor Black -BackgroundColor Yellow
            } else {
                Write-Host ('  {0}   ' -f $label) -NoNewline -ForegroundColor Gray
            }
        }
        # Espaces de garde pour effacer un eventuel reste du rendu precedent.
        Write-Host '    ' -NoNewline

        try {
            $keyInfo = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        } catch {
            Write-Host ''
            return Invoke-WcdChoiceFallback
        }

        switch ($keyInfo.VirtualKeyCode) {
            37 { $selectedIndex = ($selectedIndex - 1 + $entries.Count) % $entries.Count }  # Gauche
            38 { $selectedIndex = ($selectedIndex - 1 + $entries.Count) % $entries.Count }  # Haut
            39 { $selectedIndex = ($selectedIndex + 1) % $entries.Count }                   # Droite
            40 { $selectedIndex = ($selectedIndex + 1) % $entries.Count }                   # Bas
            13 {
                Write-Host ''
                return $entries[$selectedIndex].Value
            }
            default {
                if ($keyInfo.Character) {
                    $normalized = ([string]$keyInfo.Character).Trim().ToUpperInvariant()
                    for ($i = 0; $i -lt $entries.Count; $i++) {
                        if ([string]$entries[$i].Key -eq $normalized) {
                            $selectedIndex = $i
                            break
                        }
                    }
                }
            }
        }
    }
}

function ConvertTo-WcdOptionalToolSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RawInput,

        [Parameter(Mandatory)]
        [string[]]$ValidKeys
    )

    $chars = @($RawInput.Trim().ToCharArray() |
        ForEach-Object { [string]$_ } |
        Where-Object { $_ -match '\S' } |
        Sort-Object { [int]$_ } -Unique)

    $invalid = @($chars | Where-Object { $_ -notin $ValidKeys })
    if ($invalid.Count -gt 0) {
        return @()
    }

    return $chars
}

function Read-WcdOptionalToolChoice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Candidates
    )

    $options = [ordered]@{}
    for ($i = 0; $i -lt $Candidates.Count; $i++) {
        $options[[string]($i + 1)] = [string]$Candidates[$i].Name
    }

    Write-Host ''
    Write-Host (' +{0}+' -f ('-' * ($T.EngineerBoxTitle.Length + 2))) -ForegroundColor Cyan
    Write-Host (' |  {0}  |' -f $T.EngineerBoxTitle) -ForegroundColor Cyan
    Write-Host (' +{0}+' -f ('-' * ($T.EngineerBoxTitle.Length + 2))) -ForegroundColor Cyan
    Write-Host ''
    foreach ($key in $options.Keys) {
        Write-Host ("    {0}. {1}" -f $key, $options[$key]) -ForegroundColor White
    }
    Write-Host ''
    Write-Host $T.EngineerCombineHint -ForegroundColor DarkGray

    while ($true) {
        Write-Host ''
        $answer = Read-Host $T.EngineerChoicePrompt
        if ([string]::IsNullOrWhiteSpace($answer)) {
            Write-Host $T.EngineerAtLeastOne -ForegroundColor Yellow
            continue
        }

        $parsed = ConvertTo-WcdOptionalToolSelection -RawInput $answer -ValidKeys @($options.Keys)
        if ($parsed.Count -eq 0) {
            Write-Host ($T.EngineerInvalidChoice -f ($options.Keys -join ', ')) -ForegroundColor Yellow
            continue
        }

        $selectedNames = @($parsed | ForEach-Object { $options[$_] })
        Write-Host ($T.EngineerSelection -f ($selectedNames -join ' + ')) -ForegroundColor Green
        return $selectedNames
    }
}

function Wait-WcdForEnter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    Write-Host $Message -ForegroundColor Cyan

    $canUseRawUi = $false
    try {
        $null = $Host.UI.RawUI
        $canUseRawUi = $true
    } catch {
        $canUseRawUi = $false
    }

    if (-not $canUseRawUi) {
        [void](Read-Host $T.FallbackEnterHint)
        return
    }

    while ($true) {
        $keyInfo = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        if ($keyInfo.VirtualKeyCode -eq 13) {
            Write-Host ''
            return
        }
    }
}

function Resolve-WcdExecutionOptions {
    [CmdletBinding()]
    param(
        [string]$SelectedLanguage,
        [string]$SelectedFormFactor,
        [string]$SelectedEnvironment,
        [string]$SelectedOpenApps,
        [string]$SelectedOptionalTools,
        [object[]]$OptionalToolCandidates = @(),
        [switch]$DisablePrompt
    )

    $languageResult = $SelectedLanguage
    $deviceResult = $SelectedFormFactor
    $usageResult = $SelectedEnvironment
    $openAppsResult = $SelectedOpenApps
    $engineerResult = $SelectedOptionalTools

    $engineerTypes = @()

    if (-not $DisablePrompt) {
        if (-not $languageResult) {
            Write-Host ''
            $languageResult = Read-WcdChoice -Prompt $T.PromptLanguage -Choices ([ordered]@{ FR = 'fr-CA'; EN = 'en-US' }) -DefaultKey 'FR' `
                -Description @($T.PromptLanguageDesc)
        }

        if (-not $deviceResult) {
            Write-Host ''
            $deviceResult = Read-WcdChoice -Prompt $T.PromptDeviceType -Choices ([ordered]@{ $T.KeyLaptop = 'Laptop'; $T.KeyDesktop = 'Desktop' }) -DefaultKey $T.KeyLaptop `
                -Description @($T.PromptDeviceDesc1, $T.PromptDeviceDesc2)
        }

        if (-not $usageResult) {
            Write-Host ''
            $usageResult = Read-WcdChoice -Prompt $T.PromptUsage -Choices ([ordered]@{ $T.KeyWorkstation = 'Workstation'; $T.KeyVdi = 'Vdi' }) -DefaultKey $T.KeyWorkstation `
                -Description @($T.PromptUsageDesc1, $T.PromptUsageDesc2)
        }

        $usageLabel = Get-WcdChoiceLabel -Value $usageResult -Labels $T.Labels

        if (-not $openAppsResult) {
            Write-Host ''
            $openAppsResult = Read-WcdChoice -Prompt ($T.PromptOpenApps -f $usageLabel) -Choices ([ordered]@{ $T.KeyYes = 'Yes'; $T.KeyNo = 'No' }) -DefaultKey $T.KeyYes `
                -Description @($T.PromptOpenAppsDesc1, $T.PromptOpenAppsDesc2)
        }

        if (-not $engineerResult -and @($OptionalToolCandidates).Count -gt 0) {
            Write-Host ''
            $engineerYesNo = Read-WcdChoice -Prompt $T.PromptEngineer -Choices ([ordered]@{ $T.KeyYes = 'Yes'; $T.KeyNo = 'No' }) -DefaultKey $T.KeyNo `
                -Description @($T.PromptEngineerDesc1, $T.PromptEngineerDesc2)
            if ($engineerYesNo -eq 'Yes') {
                $engineerTypes = Read-WcdOptionalToolChoice -Candidates $OptionalToolCandidates
            } else {
                $engineerTypes = @()
            }
        }
    }

    # -OptionalTools accepts a comma-separated list of Application Target names.
    if ($engineerTypes.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($engineerResult)) {
        $engineerTypes = @($engineerResult -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }

    if (-not $languageResult)  { $languageResult  = 'fr-CA' }
    if (-not $deviceResult)    { $deviceResult    = 'Laptop' }
    if (-not $usageResult)     { $usageResult     = 'Workstation' }
    if (-not $openAppsResult)  { $openAppsResult  = 'Yes' }


    return [pscustomobject]@{
        Language      = $languageResult
        FormFactor    = $deviceResult
        Environment   = $usageResult
        OpenApps      = ($openAppsResult -eq 'Yes')
        OptionalTools = $engineerTypes
    }
}

# --- Resolution des options et du log ---
Show-WcdBanner

$resolvedLocalProjectRoot = $LocalProjectRoot
if ([string]::IsNullOrWhiteSpace($resolvedLocalProjectRoot)) {
    $resolvedLocalProjectRoot = Split-Path -Path $scriptDir -Parent
}
if (-not [string]::IsNullOrWhiteSpace($resolvedLocalProjectRoot) -and (Test-Path -LiteralPath $resolvedLocalProjectRoot)) {
    $resolvedLocalProjectRoot = (Resolve-Path -LiteralPath $resolvedLocalProjectRoot).Path
}

$resolvedUsbSourceRoot = $UsbSourceRoot
if (-not [string]::IsNullOrWhiteSpace($resolvedUsbSourceRoot) -and (Test-Path -LiteralPath $resolvedUsbSourceRoot)) {
    $resolvedUsbSourceRoot = (Resolve-Path -LiteralPath $resolvedUsbSourceRoot).Path
}

$openAppsValue = if ($OpenApps) { 'Yes' } else { '' }

# Optional tools are Application Targets flagged Prompt in the manifest.
$optionalToolCandidates = @(Get-WcdPromptedApplicationTarget -Config $script:WcdConfig)

$executionOptions = Resolve-WcdExecutionOptions `
    -SelectedLanguage $Language `
    -SelectedFormFactor $FormFactor `
    -SelectedEnvironment $Environment `
    -SelectedOpenApps $openAppsValue `
    -SelectedOptionalTools $OptionalTools `
    -OptionalToolCandidates $optionalToolCandidates `
    -DisablePrompt:$NonInteractive

$resolvedLogPath = Resolve-WcdLogPath -CandidatePath $LogPath
if (-not [string]::IsNullOrWhiteSpace($HistoryLogPath)) {
    try {
        $sameLogTarget = [string]::Equals(
            [System.IO.Path]::GetFullPath($resolvedLogPath),
            [System.IO.Path]::GetFullPath($HistoryLogPath),
            [System.StringComparison]::OrdinalIgnoreCase
        )
        if ($sameLogTarget) {
            Write-Host $T.FatalLogConflict -ForegroundColor Red
            exit 1
        }
    } catch {
    }
}

Initialize-WcdLog -Path $resolvedLogPath
Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message '=== Debut execution WinContextDeploy ==='
Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ("Language: {0} | FormFactor: {1} | Environment: {2} | OpenApps: {3} | OptionalTools: {4} | LogPath: {5}" -f $executionOptions.Language, $executionOptions.FormFactor, $executionOptions.Environment, $executionOptions.OpenApps, ($executionOptions.OptionalTools -join ','), $resolvedLogPath)
if (-not [string]::IsNullOrWhiteSpace($resolvedLocalProjectRoot)) {
    Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ("LocalProjectRoot: {0}" -f $resolvedLocalProjectRoot)
}
if (-not [string]::IsNullOrWhiteSpace($resolvedUsbSourceRoot)) {
    Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ("UsbSourceRoot: {0}" -f $resolvedUsbSourceRoot)
}
if (-not [string]::IsNullOrWhiteSpace($HistoryLogPath)) {
    Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ("HistoryLogPath: {0}" -f $HistoryLogPath)
}

function Get-WcdSeverityRank {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Severity
    )

    switch ($Severity.ToUpperInvariant()) {
        'ERROR' { return 3 }
        'WARNING' { return 2 }
        default { return 1 }
    }
}

function Get-WcdResultsForSteps {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ResultLookup,

        [string[]]$StepKeys = @()
    )

    $results = @()
    foreach ($stepKey in @($StepKeys)) {
        if ($ResultLookup.ContainsKey($stepKey)) {
            $results += @($ResultLookup[$stepKey])
        }
    }

    return $results
}

function Get-WcdStrongestResult {
    [CmdletBinding()]
    param(
        [object[]]$Results = @()
    )

    $strongest = $null
    $strongestRank = 0
    foreach ($result in @($Results)) {
        $currentRank = Get-WcdSeverityRank -Severity (Get-WcdResultSeverity -Result $result)
        if ($currentRank -gt $strongestRank) {
            $strongest = $result
            $strongestRank = $currentRank
        }
    }

    return $strongest
}

function Get-WcdAggregateDetail {
    [CmdletBinding()]
    param(
        [object[]]$Results = @(),

        [Parameter(Mandatory)]
        [hashtable]$StepLabels
    )

    $details = @()
    foreach ($result in @($Results)) {
        $severity = Get-WcdResultSeverity -Result $result
        if ($severity -eq 'INFO' -and [string]::IsNullOrWhiteSpace($result.Error)) {
            continue
        }

        $stepLabel = if ($StepLabels.ContainsKey($result.Step)) { $StepLabels[$result.Step] } else { $result.Step }
        if ([string]::IsNullOrWhiteSpace($result.Error)) {
            $details += $stepLabel
        } else {
            $details += ('{0}: {1}' -f $stepLabel, $result.Error)
        }
    }

    return ($details -join ' | ')
}

function New-WcdDiagnosticEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Label,

        [Parameter(Mandatory)]
        [ValidateSet('success', 'warning', 'error', 'manual', 'na')]
        [string]$Kind,

        [string]$Detail = ''
    )

    return [pscustomobject]@{
        Label  = $Label
        Kind   = $Kind
        Detail = $Detail
    }
}

function Resolve-WcdAutomaticEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Label,

        [Parameter(Mandatory)]
        [hashtable]$ResultLookup,

        [string[]]$StepKeys = @(),

        [Parameter(Mandatory)]
        [hashtable]$StepLabels,

        [ValidateSet('warning', 'manual', 'na')]
        [string]$MissingKind = 'warning',

        [string]$MissingDetail = ''
    )

    if ([string]::IsNullOrWhiteSpace($MissingDetail)) { $MissingDetail = $T.MissingModuleData }

    $results = @(Get-WcdResultsForSteps -ResultLookup $ResultLookup -StepKeys $StepKeys)
    if ($results.Count -eq 0) {
        return New-WcdDiagnosticEntry -Label $Label -Kind $MissingKind -Detail $MissingDetail
    }

    $missingStepKeys = @($StepKeys | Where-Object { -not $ResultLookup.ContainsKey($_) })
    $strongest = Get-WcdStrongestResult -Results $results
    $severity = Get-WcdResultSeverity -Result $strongest

    if ($severity -eq 'ERROR') {
        return New-WcdDiagnosticEntry -Label $Label -Kind 'error' -Detail (Get-WcdAggregateDetail -Results $results -StepLabels $StepLabels)
    }

    if ($severity -eq 'WARNING') {
        return New-WcdDiagnosticEntry -Label $Label -Kind 'warning' -Detail (Get-WcdAggregateDetail -Results $results -StepLabels $StepLabels)
    }

    if ($missingStepKeys.Count -gt 0) {
        $missingLabels = @($missingStepKeys | ForEach-Object {
            if ($StepLabels.ContainsKey($_)) { $StepLabels[$_] } else { $_ }
        })
        return New-WcdDiagnosticEntry -Label $Label -Kind 'warning' -Detail ($T.MissingStepTech -f ($missingLabels -join ', '))
    }

    return New-WcdDiagnosticEntry -Label $Label -Kind 'success'
}

function Get-WcdModuleStatusKind {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Status
    )

    switch ($Status) {
        'OK' { return 'success' }
        'WARNING' { return 'warning' }
        default { return 'error' }
    }
}

function Format-WcdModuleLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $ModuleStatus
    )

    $kind = Get-WcdModuleStatusKind -Status $ModuleStatus.Status
    $style = Get-WcdDiagnosticStyle -Kind $kind
    $line = ('  {0}  {1,-25} {2,-9} {3} {4}' -f $style.Icon, $ModuleStatus.Module, $ModuleStatus.Status, $ModuleStatus.Etapes, $T.StepCount)
    if (-not [string]::IsNullOrWhiteSpace($ModuleStatus.Detail)) {
        $line += '  ' + $ModuleStatus.Detail
    }

    return $line
}

function Format-WcdChecklistLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Entry
    )

    $style = Get-WcdDiagnosticStyle -Kind $Entry.Kind
    $line = '  {0}  {1,-24} {2,-9}' -f $style.Icon, $Entry.Label, $style.Status
    if (-not [string]::IsNullOrWhiteSpace($Entry.Detail)) {
        $line += '  ' + $Entry.Detail
    }

    return $line
}

function Write-WcdSectionHeader {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title
    )

    Write-Host ''
    Write-Host '===============================================' -ForegroundColor Cyan
    Write-Host ('         {0,-37}' -f $Title) -ForegroundColor Cyan
    Write-Host '===============================================' -ForegroundColor Cyan
}

function Get-WcdFinalChecklistEntries {
    [CmdletBinding()]
    param(
        [object[]]$AllResults = @(),

        [Parameter(Mandatory)]
        [pscustomobject]$ExecutionOptions,

        [Parameter(Mandatory)]
        [hashtable]$StepLabels,

        [hashtable]$Config
    )

    $lookup = @{}
    foreach ($result in @($AllResults)) {
        if ($null -eq $result -or [string]::IsNullOrWhiteSpace([string]$result.Step)) { continue }
        if (-not $lookup.ContainsKey($result.Step)) { $lookup[$result.Step] = @() }
        $lookup[$result.Step] += $result
    }

    $entries = @()
    $applicationsSkipped = $lookup.ContainsKey('ApplicationsSkip')

    # --- OS configuration, in the order the modules run -----------------------
    $entries += Resolve-WcdAutomaticEntry -Label $T.Checklist.Taskbar -ResultLookup $lookup `
        -StepKeys @('TaskbarAlignLeft', 'DisableTaskView') -StepLabels $StepLabels
    $entries += Resolve-WcdAutomaticEntry -Label $T.Checklist.Language -ResultLookup $lookup `
        -StepKeys @('DisplayLanguage') -StepLabels $StepLabels
    $entries += Resolve-WcdAutomaticEntry -Label $T.Checklist.Keyboard -ResultLookup $lookup `
        -StepKeys @('KeyboardLayout') -StepLabels $StepLabels
    $entries += Resolve-WcdAutomaticEntry -Label $T.Checklist.Decimal -ResultLookup $lookup `
        -StepKeys @('DecimalAndCurrency') -StepLabels $StepLabels

    $powerStepKeys = if ($ExecutionOptions.FormFactor -eq 'Laptop') {
        @('ScreenTimeoutBattery', 'ScreenTimeoutAc', 'LidActionAcNone', 'LidActionBatteryNone', 'SetActiveSchemeCurrent')
    } else {
        @('ScreenTimeoutAc', 'SetActiveSchemeCurrent')
    }
    $entries += Resolve-WcdAutomaticEntry -Label $T.Checklist.Power -ResultLookup $lookup `
        -StepKeys $powerStepKeys -StepLabels $StepLabels
    $entries += Resolve-WcdAutomaticEntry -Label $T.Checklist.DeviceManager -ResultLookup $lookup `
        -StepKeys @('DeviceManagerStatus') -StepLabels $StepLabels

    # --- Application Targets, in manifest order -------------------------------
    # Targets excluded by the current Environment are reported Not Applicable
    # rather than omitted, so the technician can see they were considered.
    $selected = @(Get-WcdApplicationTarget -Config $Config `
        -Environment $ExecutionOptions.Environment `
        -FormFactor $ExecutionOptions.FormFactor `
        -OptionalTools $ExecutionOptions.OptionalTools |
        ForEach-Object { [string]$_.Step })

    foreach ($entry in @($Config.Applications)) {
        $step = [string]$entry.Step
        $name = [string]$entry.Name

        if (@($selected) -notcontains $step) {
            # Prompt entries the technician declined are simply not shown.
            if ($entry.Prompt) { continue }
            $entries += New-WcdDiagnosticEntry -Label $name -Kind 'na' -Detail $T.SecondaryNA
            continue
        }

        if ($applicationsSkipped) {
            $entries += New-WcdDiagnosticEntry -Label $name -Kind 'manual' -Detail $T.ApplicationManualDetail
            continue
        }

        $entries += Resolve-WcdAutomaticEntry -Label $name -ResultLookup $lookup `
            -StepKeys @($step) -StepLabels $StepLabels
    }

    # --- Deliberately manual: WinContextDeploy does not automate these --------
    foreach ($manualLabel in @(
        $T.Checklist.Signature,
        $T.Checklist.Wifi,
        $T.Checklist.NetworkDrives,
        $T.Checklist.Sync,
        $T.Checklist.Printers,
        $T.Checklist.Desktop,
        $T.Checklist.Favorites
    )) {
        $entries += New-WcdDiagnosticEntry -Label $manualLabel -Kind 'manual' -Detail $T.StandardManualDetail
    }

    return $entries
}

function Get-WcdFinalDiagnosticLines {
    [CmdletBinding()]
    param(
        [object[]]$ModuleStatus = @(),
        [object[]]$ChecklistEntries = @(),
        [string]$SummaryLine
    )

    $lines = @(
        '===============================================',
        $T.DiagFinalByModule,
        '==============================================='
    )

    foreach ($module in @($ModuleStatus)) {
        $lines += Format-WcdModuleLine -ModuleStatus $module
    }

    $lines += ''
    $lines += '==============================================='
    $lines += $T.DiagFinalByStep
    $lines += '==============================================='

    foreach ($entry in @($ChecklistEntries)) {
        $lines += Format-WcdChecklistLine -Entry $entry
    }

    if (-not [string]::IsNullOrWhiteSpace($SummaryLine)) {
        $lines += $SummaryLine
    }

    return $lines
}

# --- Liste des modules a executer ---
$modules = @(
    @{ Name = 'Config-Power';         File = 'Config-Power.ps1' },
    @{ Name = 'Config-Decimal';       File = 'Config-Decimal.ps1' },
    @{ Name = 'Config-TaskbarLeft';   File = 'Config-TaskbarLeft.ps1' },
    @{ Name = 'Config-Language';      File = 'Config-Language.ps1' },
    @{ Name = 'Config-Applications';  File = 'Config-Applications.ps1' },
    @{ Name = 'Config-DeviceManager'; File = 'Config-DeviceManager.ps1' }
)

$stepLabels = Get-WcdTechnicalStepLabels -Config $script:WcdConfig
$moduleStepPlan = Get-WcdModuleProgressPlan -ExecutionOptions $executionOptions -Config $script:WcdConfig
$allResults = @()
$moduleStatus = @()

foreach ($mod in $modules) {
    $modPath = Join-Path $scriptDir $mod.File
    $modName = $mod.Name

    # Verification que le fichier module existe
    if (-not (Test-Path -LiteralPath $modPath)) {
        $msg = ($T.ModuleNotFound -f $modPath)
        Write-Host "  [ERREUR] $msg" -ForegroundColor Red
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message $msg
        $moduleStatus += [pscustomobject]@{
            Module         = $modName
            Status         = $T.StatusError
            Etapes         = 0
            Echecs         = 1
            Avertissements = 0
            Detail         = $msg
        }
        continue
    }

    # Chargement du module (dot-source)
    try {
        . $modPath
    } catch {
        $msg = ($T.ModuleLoadFail -f $modName, $_.Exception.Message)
        Write-Host "  [ERREUR] $msg" -ForegroundColor Red
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message $msg
        $moduleStatus += [pscustomobject]@{
            Module         = $modName
            Status         = $T.StatusError
            Etapes         = 0
            Echecs         = 1
            Avertissements = 0
            Detail         = $msg
        }
        continue
    }

    # Execution du module
    $modResults = @()
    $modError = $null
    $startTime = Get-Date
    $progressState = New-WcdProgressState -ModuleName $modName -StepKeys $moduleStepPlan[$modName] -StepLabels $stepLabels
    $progressCallback = {
        param($eventData)

        Update-WcdProgressState -State $progressState -StepKey $eventData.Step -Event $eventData.Event -Kind $eventData.Kind
    }

    try {
        switch ($modName) {
            'Config-Power' {
                $modResults = @(Set-WcdPowerConfiguration -FormFactor $executionOptions.FormFactor -LogPath $resolvedLogPath -ProgressCallback $progressCallback)
            }
            'Config-Decimal' {
                $modResults = @(Set-WcdDecimalConfiguration -LogPath $resolvedLogPath -ProgressCallback $progressCallback)
            }
            'Config-TaskbarLeft' {
                $modResults = @(Set-WcdTaskbarLeft -LogPath $resolvedLogPath -ProgressCallback $progressCallback)
            }
            'Config-Language' {
                $modResults = @(Set-WcdLanguageConfiguration -Culture $executionOptions.Language -LogPath $resolvedLogPath -ProgressCallback $progressCallback)
            }
            'Config-Applications' {
                $targets = @(Get-WcdApplicationTarget -Config $script:WcdConfig `
                    -Environment $executionOptions.Environment `
                    -FormFactor $executionOptions.FormFactor `
                    -OptionalTools $executionOptions.OptionalTools)
                $modResults = @(Set-WcdApplicationsConfiguration -Targets $targets -OpenApps $executionOptions.OpenApps -LogPath $resolvedLogPath -ProgressCallback $progressCallback)
            }
            'Config-DeviceManager' {
                $modResults = @(Set-WcdDeviceManagerStatus -LogPath $resolvedLogPath -ProgressCallback $progressCallback)
            }
        }
    } catch {
        $modError = $_.Exception.Message
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ("Module ${modName} crashed: {0}" -f $modError)
    }

    $duration = (Get-Date) - $startTime

    # Comptage des resultats
    $totalSteps = $modResults.Count
    $failedSteps = @($modResults | Where-Object { (Get-WcdResultSeverity -Result $_) -eq 'ERROR' }).Count
    $warningSteps = @($modResults | Where-Object { (Get-WcdResultSeverity -Result $_) -eq 'WARNING' }).Count

    if ($modError) {
        $statusLabel = $T.StatusCrash
        $detail = $modError
    } elseif ($failedSteps -gt 0) {
        $statusLabel = $T.StatusPartial
        $failedNames = ($modResults | Where-Object { (Get-WcdResultSeverity -Result $_) -eq 'ERROR' } | ForEach-Object { $_.Step }) -join ', '
        $detail = ($T.FailDetails -f $failedNames)
    } elseif ($warningSteps -gt 0) {
        $statusLabel = $T.StatusWarning
        $warningNames = ($modResults | Where-Object { (Get-WcdResultSeverity -Result $_) -eq 'WARNING' } | ForEach-Object { $_.Step }) -join ', '
        $detail = ($T.WarningDetails -f $warningNames)
    } else {
        $statusLabel = $T.StatusOk
        $detail = ''
    }

    $resultLine = ($T.ModuleResult -f $statusLabel, $totalSteps, $failedSteps, $warningSteps, $duration.TotalMilliseconds)
    $resultColor = switch ($statusLabel) { { $_ -eq $T.StatusOk } { 'Green' } { $_ -eq $T.StatusWarning } { 'Yellow' } default { 'Red' } }

    if ($progressState.RenderMode -eq 'InPlace') {
        Write-Host ("`r" + $resultLine.PadRight(70)) -ForegroundColor $resultColor
    } else {
        Write-Host $resultLine -ForegroundColor $resultColor
    }

    $allResults += $modResults
    $moduleStatus += [pscustomobject]@{
        Module         = $modName
        Status         = $statusLabel
        Etapes         = $totalSteps
        Echecs         = $failedSteps
        Avertissements = $warningSteps
        Detail         = $detail
    }
}

$diagnosticResults = @($allResults)
$checklistEntries = Get-WcdFinalChecklistEntries -AllResults $diagnosticResults -ExecutionOptions $executionOptions -StepLabels $stepLabels -Config $script:WcdConfig
$checklistSuccessCount = @($checklistEntries | Where-Object { $_.Kind -eq 'success' }).Count
$checklistWarningCount = @($checklistEntries | Where-Object { $_.Kind -eq 'warning' }).Count
$checklistErrorCount = @($checklistEntries | Where-Object { $_.Kind -eq 'error' }).Count
$checklistManualCount = @($checklistEntries | Where-Object { $_.Kind -eq 'manual' }).Count
$checklistNaCount = @($checklistEntries | Where-Object { $_.Kind -eq 'na' }).Count
$summaryLine = $T.SummaryLine -f $checklistSuccessCount, $checklistWarningCount, $checklistErrorCount, $checklistManualCount, $checklistNaCount

Write-WcdSectionHeader -Title $T.SectionByModule
foreach ($ms in $moduleStatus) {
    $moduleKind = Get-WcdModuleStatusKind -Status $ms.Status
    $moduleColor = (Get-WcdDiagnosticStyle -Kind $moduleKind).Color
    Write-Host (Format-WcdModuleLine -ModuleStatus $ms) -ForegroundColor $moduleColor
}

Write-WcdSectionHeader -Title $T.SectionByStep
foreach ($entry in $checklistEntries) {
    $entryColor = (Get-WcdDiagnosticStyle -Kind $entry.Kind).Color
    Write-Host (Format-WcdChecklistLine -Entry $entry) -ForegroundColor $entryColor
}

$summaryColor = if ($checklistErrorCount -gt 0) {
    'Red'
} elseif ($checklistWarningCount -gt 0) {
    'DarkYellow'
} else {
    'Green'
}

Write-Host $summaryLine -ForegroundColor $summaryColor

$finalDiagnosticLines = Get-WcdFinalDiagnosticLines -ModuleStatus $moduleStatus -ChecklistEntries $checklistEntries -SummaryLine $summaryLine

Write-Host ''
Write-Host ($T.LogOutput -f $resolvedLogPath) -ForegroundColor Gray
Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ($T.LogEndSummary -f $checklistSuccessCount, $checklistWarningCount, $checklistErrorCount, $checklistManualCount, $checklistNaCount)

$finalizationExitCode = 0
Write-Host ''

if (-not [string]::IsNullOrWhiteSpace($HistoryLogPath)) {
    if ($NonInteractive) {
        Write-Host ($T.AutoExportLog -f $HistoryLogPath) -ForegroundColor Cyan
    } else {
        Wait-WcdForEnter -Message $T.WaitEnterExport
    }

    try {
        Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('Preparing history export to: {0}' -f $HistoryLogPath)
        Export-WcdHistoryLog -LocalLogPath $resolvedLogPath -HistoryLogPath $HistoryLogPath -DiagnosticLines $finalDiagnosticLines | Out-Null
        Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('History exported to: {0}' -f $HistoryLogPath)
        Write-Host ($T.HistoryExported -f $HistoryLogPath) -ForegroundColor Green
    } catch {
        $finalizationExitCode = 2
        $historyError = $_.Exception.Message
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ('History export failed: {0}' -f $historyError)
        Write-Host ($T.HistoryExportFailed -f $historyError) -ForegroundColor Yellow
    }
} elseif (-not $NonInteractive) {
    Wait-WcdForEnter -Message $T.WaitEnterFinish
}

exit $finalizationExitCode
