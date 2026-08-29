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

    [string]$EngineerType,

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
        PrimaryNA               = 'Not applicable on primary device.'
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
        OptionalSoftwareTitle   = '   OPTIONAL SOFTWARE NOT INSTALLED'
        OptionalSoftwareDesc    = '   These programs are not present on this device.'
        OptionalSoftwareNote    = 'Not installed on this device (normal depending on profile).'
        AutoExportLog           = 'Automatic log export to: {0}'
        HistoryExported         = 'History added to: {0}'
        HistoryExportFailed     = '[WARNING] History export failed. Local copy preserved. Detail: {0}'
        FatalHelpersMissing     = '[FATAL ERROR] WcdHelpers.ps1 not found in: {0}'
        FatalConfig             = '[FATAL ERROR] {0}'
        FatalLogConflict        = '[FATAL ERROR] -LogPath and -HistoryLogPath must be different.'
        AS400Warning            = 'Warning: your primary device does not have AS400.'
        AS400PathNote           = ' Checked path: {0}'
        AutovueWarning          = 'AutoVue not installed on this device.'
        AutovuePendingConfig    = 'AutoVue opened. Remaining configuration must be completed manually.'
        AutovueOpenFailed       = 'AutoVue launch failed. Remaining configuration must be completed manually.'
        AutovuePathNote         = ' Checked path: {0}'
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
        PrimaryNA               = 'Non applicable sur poste principal.'
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
        OptionalSoftwareTitle   = '   LOGICIELS OPTIONNELS NON INSTALLES'
        OptionalSoftwareDesc    = '   Ces logiciels ne sont pas presents sur ce poste.'
        OptionalSoftwareNote    = 'Non installe sur ce poste (normal selon le profil).'
        AutoExportLog           = 'Export automatique des logs vers: {0}'
        HistoryExported         = 'Historique ajoute dans: {0}'
        HistoryExportFailed     = '[AVERTISSEMENT] Export historique impossible. La copie locale est conservee. Detail: {0}'
        FatalHelpersMissing     = '[ERREUR FATALE] WcdHelpers.ps1 introuvable dans: {0}'
        FatalConfig             = '[ERREUR FATALE] {0}'
        FatalLogConflict        = '[ERREUR FATALE] -LogPath et -HistoryLogPath doivent etre differents.'
        AS400Warning            = "Warning: votre poste principal n a pas AS400."
        AS400PathNote           = ' Chemin verifie: {0}'
        AutovueWarning          = 'AutoVue non installe sur ce poste.'
        AutovuePendingConfig    = 'AutoVue ouvert. La configuration restante doit etre faite manuellement.'
        AutovueOpenFailed       = 'Echec ouverture AutoVue. La configuration restante doit etre faite manuellement.'
        AutovuePathNote         = ' Chemin verifie: {0}'
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

function ConvertTo-WcdEngineerSelections {
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

function Read-WcdEngineerChoice {
    [CmdletBinding()]
    param()

    $options = [ordered]@{
        '1' = 'Nvidia'
        '2' = 'GPS'
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

        $parsed = ConvertTo-WcdEngineerSelections -RawInput $answer -ValidKeys @($options.Keys)
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
        [string]$SelectedEngineerType,
        [switch]$DisablePrompt
    )

    $languageResult = $SelectedLanguage
    $deviceResult = $SelectedFormFactor
    $usageResult = $SelectedEnvironment
    $openAppsResult = $SelectedOpenApps
    $engineerResult = $SelectedEngineerType

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

        if (-not $engineerResult) {
            Write-Host ''
            $engineerYesNo = Read-WcdChoice -Prompt $T.PromptEngineer -Choices ([ordered]@{ $T.KeyYes = 'Yes'; $T.KeyNo = 'No' }) -DefaultKey $T.KeyNo `
                -Description @($T.PromptEngineerDesc1, $T.PromptEngineerDesc2)
            if ($engineerYesNo -eq 'Yes') {
                $engineerTypes = Read-WcdEngineerChoice
            } else {
                $engineerTypes = @('None')
            }
        }
    }

    # Traitement du parametre CLI -EngineerType (valeurs separees par virgule)
    if ($engineerTypes.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($engineerResult)) {
        if ($engineerResult -eq 'None') {
            $engineerTypes = @('None')
        } else {
            $engineerTypes = @($engineerResult -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        }
    }

    if (-not $languageResult)  { $languageResult  = 'fr-CA' }
    if (-not $deviceResult)    { $deviceResult    = 'Laptop' }
    if (-not $usageResult)     { $usageResult     = 'Workstation' }
    if (-not $openAppsResult)  { $openAppsResult  = 'Yes' }
    if ($engineerTypes.Count -eq 0) { $engineerTypes = @('None') }

    return [pscustomobject]@{
        Language      = $languageResult
        FormFactor    = $deviceResult
        Environment   = $usageResult
        OpenApps      = ($openAppsResult -eq 'Yes')
        EngineerTypes = $engineerTypes
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

$executionOptions = Resolve-WcdExecutionOptions `
    -SelectedLanguage $Language `
    -SelectedFormFactor $FormFactor `
    -SelectedEnvironment $Environment `
    -SelectedOpenApps $openAppsValue `
    -SelectedEngineerType $EngineerType `
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
Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ("Language: {0} | FormFactor: {1} | Environment: {2} | OpenApps: {3} | Engineer: {4} | LogPath: {5}" -f $executionOptions.Language, $executionOptions.FormFactor, $executionOptions.Environment, $executionOptions.OpenApps, ($executionOptions.EngineerTypes -join ','), $resolvedLogPath)
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

function Test-WcdEngineerTypeSelected {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$ExecutionOptions,

        [Parameter(Mandatory)]
        [string]$EngineerType
    )

    return (@($ExecutionOptions.EngineerTypes) -contains $EngineerType)
}

function Get-WcdAS400DiagnosticResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$ExecutionOptions,

        [hashtable]$Config
    )

    if ($ExecutionOptions.Environment -ne 'Workstation') {
        return $null
    }

    $principalConfig = $null
    if ($null -ne $Config) {
        $principalConfig = $Config.Principal
    }

    $configuredPath = ''
    if ($null -ne $principalConfig -and -not [string]::IsNullOrWhiteSpace($principalConfig.AS400Path)) {
        $configuredPath = $principalConfig.AS400Path
    }

    $programsPath = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs'
    if ($null -ne $principalConfig -and -not [string]::IsNullOrWhiteSpace($principalConfig.ProgramsPath)) {
        $programsPath = $principalConfig.ProgramsPath
    }

    $detectedPath = ''
    if (-not [string]::IsNullOrWhiteSpace($configuredPath) -and (Test-Path -LiteralPath $configuredPath)) {
        $detectedPath = $configuredPath
    }

    if ([string]::IsNullOrWhiteSpace($detectedPath) -and (Test-Path -LiteralPath $programsPath)) {
        $detectedEntry = Get-ChildItem -LiteralPath $programsPath -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'AS\s?400|IBM i Access|Client Access|iSeries' } |
            Select-Object -First 1

        if ($null -ne $detectedEntry) {
            $detectedPath = $detectedEntry.FullName
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($detectedPath)) {
        return [pscustomobject]@{
            Step     = 'AS400Presence'
            Success  = $true
            Severity = 'INFO'
            Error    = ''
            Path     = $detectedPath
        }
    }

    $detail = $T.AS400Warning
    if (-not [string]::IsNullOrWhiteSpace($configuredPath)) {
        $detail += ($T.AS400PathNote -f $configuredPath)
    }

    return [pscustomobject]@{
        Step     = 'AS400Presence'
        Success  = $true
        Severity = 'WARNING'
        Error    = $detail
        Path     = $configuredPath
    }
}

function Get-WcdAutovueDiagnosticResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$ExecutionOptions,

        [hashtable]$Config
    )

    if ($ExecutionOptions.Environment -ne 'Workstation') {
        return $null
    }

    $configuredPath = ''
    if ($null -ne $Config -and $null -ne $Config.Engineer -and -not [string]::IsNullOrWhiteSpace($Config.Engineer.AutovuePath)) {
        $configuredPath = $Config.Engineer.AutovuePath
    }

    if (-not [string]::IsNullOrWhiteSpace($configuredPath) -and (Test-Path -LiteralPath $configuredPath)) {
        try {
            Start-Process -FilePath $configuredPath -ErrorAction Stop
            $detail = $T.AutovuePendingConfig
        } catch {
            $detail = ($T.AutovueOpenFailed + ' ' + $_.Exception.Message)
        }

        $detail += ($T.AutovuePathNote -f $configuredPath)

        return [pscustomobject]@{
            Step     = 'AutovuePresence'
            Success  = $true
            Severity = 'WARNING'
            Error    = $detail
            Path     = $configuredPath
        }
    }

    $detail = $T.AutovueWarning
    if (-not [string]::IsNullOrWhiteSpace($configuredPath)) {
        $detail += ($T.AutovuePathNote -f $configuredPath)
    }

    return [pscustomobject]@{
        Step     = 'AutovuePresence'
        Success  = $true
        Severity = 'WARNING'
        Error    = $detail
        Path     = $configuredPath
    }
}

function Get-WcdFinalChecklistEntries {
    [CmdletBinding()]
    param(
        [object[]]$AllResults = @(),

        [Parameter(Mandatory)]
        [pscustomobject]$ExecutionOptions,

        [Parameter(Mandatory)]
        [hashtable]$StepLabels
    )

    $lookup = @{}
    foreach ($result in @($AllResults)) {
        if ($null -eq $result -or [string]::IsNullOrWhiteSpace([string]$result.Step)) {
            continue
        }

        if (-not $lookup.ContainsKey($result.Step)) {
            $lookup[$result.Step] = @()
        }
        $lookup[$result.Step] += $result
    }

    $entries = @()
    $applicationsSkipped = $lookup.ContainsKey('ApplicationsSkip')
    $applicationManualDetail = $T.ApplicationManualDetail
    $standardManualDetail = $T.StandardManualDetail
    $powerStepKeys = if ($ExecutionOptions.FormFactor -eq 'Laptop') {
        @(
            'EcranBatterie10min',
            'EcranSecteur15min',
            'CapotSecteurNeRienFaire',
            'CapotBatterieNeRienFaire',
            'SetActiveSchemeCurrent'
        )
    } else {
        @(
            'EcranSecteur15min',
            'SetActiveSchemeCurrent'
        )
    }

    $entries += Resolve-WcdAutomaticEntry -Label 'Taskbar a gauche' -ResultLookup $lookup -StepKeys @('TaskbarAlignementGauche', 'DesactiverVueTaches') -StepLabels $StepLabels

    if ($applicationsSkipped) {
        $entries += New-WcdDiagnosticEntry -Label 'Software center ok' -Kind 'manual' -Detail $applicationManualDetail
    } else {
        $entries += Resolve-WcdAutomaticEntry -Label 'Software center ok' -ResultLookup $lookup -StepKeys @('AppSoftwareCenter') -StepLabels $StepLabels
    }

    $entries += Resolve-WcdAutomaticEntry -Label 'Device manager' -ResultLookup $lookup -StepKeys @('DeviceManagerEtat') -StepLabels $StepLabels

    if ($applicationsSkipped) {
        $entries += New-WcdDiagnosticEntry -Label 'Outlook' -Kind 'manual' -Detail $applicationManualDetail
    } else {
        $entries += Resolve-WcdAutomaticEntry -Label 'Outlook' -ResultLookup $lookup -StepKeys @('AppOutlook') -StepLabels $StepLabels
    }

    $entries += New-WcdDiagnosticEntry -Label 'Signature' -Kind 'manual' -Detail $standardManualDetail

    if ($applicationsSkipped) {
        $entries += New-WcdDiagnosticEntry -Label 'Global protect' -Kind 'manual' -Detail $applicationManualDetail
    } else {
        $entries += Resolve-WcdAutomaticEntry -Label 'Global protect' -ResultLookup $lookup -StepKeys @('AppGlobalProtect') -StepLabels $StepLabels
    }

    $entries += New-WcdDiagnosticEntry -Label 'Wifi' -Kind 'manual' -Detail $standardManualDetail

    if ($applicationsSkipped) {
        $entries += New-WcdDiagnosticEntry -Label 'Snag it/Snipping Tool' -Kind 'manual' -Detail $applicationManualDetail
    } else {
        $entries += Resolve-WcdAutomaticEntry -Label 'Snag it/Snipping Tool' -ResultLookup $lookup -StepKeys @('AppSnipIt') -StepLabels $StepLabels
    }

    if ($ExecutionOptions.Environment -eq 'Workstation') {
        $entries += Resolve-WcdAutomaticEntry -Label 'SAP PP1' -ResultLookup $lookup -StepKeys @('SAPFrontEnd') -StepLabels $StepLabels
    } else {
        $entries += New-WcdDiagnosticEntry -Label 'SAP PP1' -Kind 'na' -Detail $T.SecondaryNA
    }

    $entries += Resolve-WcdAutomaticEntry -Label 'Language ok' -ResultLookup $lookup -StepKeys @('LangueWindows') -StepLabels $StepLabels
    $entries += Resolve-WcdAutomaticEntry -Label 'Clavier ok' -ResultLookup $lookup -StepKeys @('ClavierWindows') -StepLabels $StepLabels
    $entries += Resolve-WcdAutomaticEntry -Label 'Decimal (reg-set)' -ResultLookup $lookup -StepKeys @('DecimalEtMonetaire') -StepLabels $StepLabels
    $entries += Resolve-WcdAutomaticEntry -Label 'Power options' -ResultLookup $lookup -StepKeys $powerStepKeys -StepLabels $StepLabels

    if ($ExecutionOptions.Environment -eq 'Workstation') {
        $entries += Resolve-WcdAutomaticEntry -Label 'AS400' -ResultLookup $lookup -StepKeys @('AS400Presence') -StepLabels $StepLabels
    } else {
        $entries += New-WcdDiagnosticEntry -Label 'AS400' -Kind 'na' -Detail $T.SecondaryNA
    }

    if ($applicationsSkipped) {
        $entries += New-WcdDiagnosticEntry -Label 'Teams' -Kind 'manual' -Detail $applicationManualDetail
    } else {
        $entries += Resolve-WcdAutomaticEntry -Label 'Teams' -ResultLookup $lookup -StepKeys @('AppTeams') -StepLabels $StepLabels
    }

    $entries += New-WcdDiagnosticEntry -Label 'Lecteurs reseau' -Kind 'manual' -Detail $standardManualDetail
    $entries += New-WcdDiagnosticEntry -Label 'Synchronisation' -Kind 'manual' -Detail $standardManualDetail

    if ($ExecutionOptions.Environment -eq 'Vdi') {
        $entries += Resolve-WcdAutomaticEntry -Label 'Citrix' -ResultLookup $lookup -StepKeys @('UsageCitrix') -StepLabels $StepLabels
    } else {
        $entries += New-WcdDiagnosticEntry -Label 'Citrix' -Kind 'na' -Detail $T.PrimaryNA
    }

    if ($ExecutionOptions.Environment -eq 'Workstation') {
        $entries += Resolve-WcdAutomaticEntry -Label 'Autovue' -ResultLookup $lookup -StepKeys @('AutovuePresence') -StepLabels $StepLabels
    } else {
        $entries += New-WcdDiagnosticEntry -Label 'Autovue' -Kind 'na' -Detail $T.SecondaryNA
    }

    $entries += New-WcdDiagnosticEntry -Label 'Imprimantes' -Kind 'manual' -Detail $standardManualDetail
    $entries += New-WcdDiagnosticEntry -Label 'Bureau' -Kind 'manual' -Detail $T.DeskWindowsDetail

    if ($applicationsSkipped) {
        $entries += New-WcdDiagnosticEntry -Label 'My Support' -Kind 'manual' -Detail $applicationManualDetail
    } else {
        $entries += Resolve-WcdAutomaticEntry -Label 'My Support' -ResultLookup $lookup -StepKeys @('AppServiceNow') -StepLabels $StepLabels
    }

    $entries += New-WcdDiagnosticEntry -Label 'Favoris' -Kind 'manual' -Detail $standardManualDetail
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
    @{ Name = 'Config-Usage';         File = 'Config-Usage.ps1' },
    @{ Name = 'Config-Applications';  File = 'Config-Applications.ps1' },
    @{ Name = 'Config-Engineer';      File = 'Config-Engineer.ps1' },
    @{ Name = 'Config-DeviceManager'; File = 'Config-DeviceManager.ps1' }
)

$stepLabels = Get-WcdTechnicalStepLabels
$moduleStepPlan = Get-WcdModuleProgressPlan -ExecutionOptions $executionOptions
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
            'Config-Usage' {
                $modResults = @(Set-WcdUsageConfiguration -Environment $executionOptions.Environment -LogPath $resolvedLogPath -Config $script:WcdConfig -ProgressCallback $progressCallback)
            }
            'Config-Applications' {
                $modResults = @(Set-WcdApplicationsConfiguration -Environment $executionOptions.Environment -OpenApps $executionOptions.OpenApps -LogPath $resolvedLogPath -Config $script:WcdConfig -ProgressCallback $progressCallback)
            }
            'Config-Engineer' {
                $modResults = @(Set-WcdEngineerConfiguration -EngineerTypes $executionOptions.EngineerTypes -LogPath $resolvedLogPath -Config $script:WcdConfig -ProgressCallback $progressCallback)
            }
            'Config-DeviceManager' {
                $modResults = @(Set-WcdDeviceManagerStatus -LogPath $resolvedLogPath -ProgressCallback $progressCallback)
            }
        }
    } catch {
        $modError = $_.Exception.Message
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ("Module ${modName} crash: {0}" -f $modError)
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
$as400Diagnostic = Get-WcdAS400DiagnosticResult -ExecutionOptions $executionOptions -Config $script:WcdConfig
if ($null -ne $as400Diagnostic) {
    $diagnosticResults += $as400Diagnostic

    $as400Severity = Get-WcdResultSeverity -Result $as400Diagnostic
    if ($as400Severity -eq 'WARNING') {
        Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('AS400: {0}' -f $as400Diagnostic.Error)
    } else {
        $detectedAs400Path = ''
        if ($null -ne $as400Diagnostic.PSObject.Properties['Path'] -and -not [string]::IsNullOrWhiteSpace([string]$as400Diagnostic.Path)) {
            $detectedAs400Path = [string]$as400Diagnostic.Path
        }

        if (-not [string]::IsNullOrWhiteSpace($detectedAs400Path)) {
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('AS400: present ({0}).' -f $detectedAs400Path)
        } else {
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'AS400: present.'
        }
    }
}

$autovueDiagnostic = Get-WcdAutovueDiagnosticResult -ExecutionOptions $executionOptions -Config $script:WcdConfig
if ($null -ne $autovueDiagnostic) {
    $diagnosticResults += $autovueDiagnostic

    $autovueSeverity = Get-WcdResultSeverity -Result $autovueDiagnostic
    if ($autovueSeverity -eq 'WARNING') {
        Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('AutoVue: {0}' -f $autovueDiagnostic.Error)
    } else {
        $detectedAutovuePath = ''
        if ($null -ne $autovueDiagnostic.PSObject.Properties['Path'] -and -not [string]::IsNullOrWhiteSpace([string]$autovueDiagnostic.Path)) {
            $detectedAutovuePath = [string]$autovueDiagnostic.Path
        }

        if (-not [string]::IsNullOrWhiteSpace($detectedAutovuePath)) {
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('AutoVue: present ({0}).' -f $detectedAutovuePath)
        } else {
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'AutoVue: present.'
        }
    }
}

$checklistEntries = Get-WcdFinalChecklistEntries -AllResults $diagnosticResults -ExecutionOptions $executionOptions -StepLabels $stepLabels
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

# --- Logiciels optionnels non installes ---
$optionalSoftware = @()

$sapPath = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\SAP Front End'
if ($null -ne $script:WcdConfig -and $null -ne $script:WcdConfig.Principal) {
    $sapPath = $script:WcdConfig.Principal.SAPPath
}
if (-not (Test-Path -LiteralPath $sapPath)) {
    $optionalSoftware += [pscustomobject]@{
        Logiciel = 'SAP Front End'
        Chemin   = $sapPath
        Note     = $T.OptionalSoftwareNote
    }
}

$mfPath = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Micro Focus'
if ($null -ne $script:WcdConfig -and $null -ne $script:WcdConfig.Applications) {
    $mfPath = $script:WcdConfig.Applications.MicroFocus
}
if (-not [string]::IsNullOrWhiteSpace($mfPath) -and -not (Test-Path -LiteralPath $mfPath)) {
    $optionalSoftware += [pscustomobject]@{
        Logiciel = 'Micro Focus'
        Chemin   = $mfPath
        Note     = $T.OptionalSoftwareNote
    }
}

$avPath = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\AutoVue for Windows\AutoVue.lnk'
if ($null -ne $script:WcdConfig -and $null -ne $script:WcdConfig.Engineer) {
    if (-not [string]::IsNullOrWhiteSpace($script:WcdConfig.Engineer.AutovuePath)) {
        $avPath = $script:WcdConfig.Engineer.AutovuePath
    }
}
if (-not [string]::IsNullOrWhiteSpace($avPath) -and -not (Test-Path -LiteralPath $avPath)) {
    $optionalSoftware += [pscustomobject]@{
        Logiciel = 'AutoVue'
        Chemin   = $avPath
        Note     = $T.OptionalSoftwareNote
    }
}

if ($optionalSoftware.Count -gt 0) {
    Write-Host ''
    Write-Host '===============================================' -ForegroundColor DarkGray
    Write-Host $T.OptionalSoftwareTitle -ForegroundColor DarkGray
    Write-Host '===============================================' -ForegroundColor DarkGray
    Write-Host $T.OptionalSoftwareDesc -ForegroundColor DarkGray
    $optionalSoftware | Format-Table -Property Logiciel, Chemin, Note -AutoSize
}

$finalizationExitCode = 0
Write-Host ''

if (-not [string]::IsNullOrWhiteSpace($HistoryLogPath)) {
    if ($NonInteractive) {
        Write-Host ($T.AutoExportLog -f $HistoryLogPath) -ForegroundColor Cyan
    } else {
        Wait-WcdForEnter -Message $T.WaitEnterExport
    }

    try {
        Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('Preparation export historique vers: {0}' -f $HistoryLogPath)
        Export-WcdHistoryLog -LocalLogPath $resolvedLogPath -HistoryLogPath $HistoryLogPath -DiagnosticLines $finalDiagnosticLines | Out-Null
        Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('Historique exporte vers: {0}' -f $HistoryLogPath)
        Write-Host ($T.HistoryExported -f $HistoryLogPath) -ForegroundColor Green
    } catch {
        $finalizationExitCode = 2
        $historyError = $_.Exception.Message
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ('Export historique impossible: {0}' -f $historyError)
        Write-Host ($T.HistoryExportFailed -f $historyError) -ForegroundColor Yellow
    }
} elseif (-not $NonInteractive) {
    Wait-WcdForEnter -Message $T.WaitEnterFinish
}

exit $finalizationExitCode
