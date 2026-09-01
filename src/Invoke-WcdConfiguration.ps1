<#
.SYNOPSIS
    WinContextDeploy entry point: runs every configuration Module and prints the
    final Diagnostic.

.DESCRIPTION
    Loads the shared helpers and the manifest, asks the technician for the
    machine context, runs each Module in order, then prints the Diagnostic
    twice - grouped by Module, and as a flat technician's checklist.

    Only the power Modules need Administrator. When the run is not elevated the
    technician is offered the standard Windows UAC prompt; declining is fine,
    and the power steps then report as actionable warnings rather than as
    failures.

.PARAMETER Language
    Windows display language to apply: 'fr-CA' or 'en-US'. Prompted when omitted.

.PARAMETER FormFactor
    Machine form factor: 'Laptop' or 'Desktop'. Selects the power profile.
    Prompted when omitted.

.PARAMETER Environment
    'Workstation' for a full local machine, 'Vdi' for a thin endpoint whose
    applications live in a remote session. Prompted when omitted.

.PARAMETER LogPath
    Full path to this run's log file. Defaults to log.txt beside the script.

.PARAMETER ConfigPath
    Path to WinContextDeploy.psd1. Found automatically when omitted.

.PARAMETER OpenApps
    Open the Application Targets without asking. Prompted when omitted.

.PARAMETER OptionalTools
    Comma-separated names of Optional Tools to run, skipping their menu.

.PARAMETER HistoryLogPath
    Second file this run's summary block is appended to - one running record
    across every machine configured from the same USB key.

.PARAMETER LocalProjectRoot
    Project root when the tool runs from a copy, e.g. under %TEMP%.

.PARAMETER UsbSourceRoot
    Original location the copy was taken from, for the -Usb launcher flow.

.PARAMETER ReportPath
    When given, a machine-readable JSON run summary is also written there.
    Console output and the text log are unchanged. A report that cannot be
    written warns without failing the run.

.PARAMETER NonInteractive
    Ask nothing: use the supplied parameters and their defaults. Also suppresses
    the UAC prompt, since an unattended run has nobody to answer it; start the
    process elevated if the power steps have to be applied.

.PARAMETER ScriptUI
    Language of the prompts and the Diagnostic: 'FR' or 'EN'. Defaults from the
    system locale.

.PARAMETER Elevated
    Internal guard. Set on the relaunched process so a failed elevation can
    never spawn another one. Do not pass it by hand.

.OUTPUTS
    None. Writes to the host, the log, and optionally the JSON report.
    Exit code 0 on success, 2 when the history export failed.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\src\Invoke-WcdConfiguration.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\src\Invoke-WcdConfiguration.ps1 `
        -Language en-US -FormFactor Desktop -Environment Vdi -NonInteractive

.EXAMPLE
    # Collect a machine-readable summary across a fleet
    powershell -ExecutionPolicy Bypass -File .\src\Invoke-WcdConfiguration.ps1 `
        -NonInteractive -ReportPath \\fileserver\wcd\$env:COMPUTERNAME.json
#>

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

    [string]$ReportPath,

    [switch]$NonInteractive,

    [ValidateSet('FR', 'EN')]
    [string]$ScriptUI,

    # Internal guard: set on the elevated relaunch so it can only happen once.
    [switch]$Elevated
)

# UI language defaults from the system locale, so one launcher serves both.
if ([string]::IsNullOrWhiteSpace($ScriptUI)) {
    $ScriptUI = if ((Get-UICulture).TwoLetterISOLanguageName -eq 'fr') { 'FR' } else { 'EN' }
}

# --- Translation table ---
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
            Network        = 'Network adapters'
            DiskHealth     = 'Disk health'
            DiskFreeSpace  = 'Free space'
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
        PromptFormFactor        = 'Machine form factor'
        PromptFormFactorDesc1   = '  Laptop = has a battery and a lid  |  Desktop = neither'
        PromptFormFactorDesc2   = '  Selects the power profile: battery and lid-close settings.'
        PromptEnvironment       = 'Machine environment'
        PromptUsageDesc1        = '  Workstation = full local machine  -> checks the locally installed applications'
        PromptUsageDesc2        = '  Citrix / VDI = thin endpoint      -> its applications live in the remote session'
        PromptOpenApps          = 'Open {0} configuration applications?'
        PromptOpenAppsDesc1     = '  Opens the Application Targets declared in WinContextDeploy.psd1.'
        PromptOpenAppsDesc2     = '  Answer Yes unless applications were already opened manually.'
        PromptEngineer          = 'Engineering workstation? (offers the optional tools)'
        PromptEngineerDesc1     = '  Offers the extras declared Prompt in WinContextDeploy.psd1.'
        PromptEngineerDesc2     = '  Answer No for a standard device.'
        MissingModuleData       = 'No data returned by the module.'
        MissingStepTech         = 'Missing technical step: {0}'
        ApplicationManualDetail = 'Launch skipped (answered No). Manual verification required.'
        StandardManualDetail    = 'Must be done manually.'
        SecondaryNA             = 'Not applicable to the chosen Form Factor or Environment.'
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
        ElevationRequest        = 'The power settings need Administrator. Requesting elevation...'
        ElevationDeclined       = 'Continuing without Administrator. The power steps will report as needing elevation.'
        ElevationUncWarning     = '[WARNING] -HistoryLogPath points at a network share ({0}). Elevation opens a new logon session, which drops mapped drives, so the history export may fail after the relaunch.'
        ReportWritten           = 'JSON report written to: {0}'
        ReportFailed            = '[WARNING] JSON report could not be written to {0}. Detail: {1}'
        # Remediation: what the technician should do next. The raw exception
        # stays in the log; this is what goes on screen.
        Remedy                  = @{
            TargetMissing       = "Not found at {0}. Update Applications['{1}'].Target in WinContextDeploy.psd1, or remove the entry."
            TargetLaunchFailed  = "Could not start {0}. Check Applications['{1}'].Target and Action in WinContextDeploy.psd1."
            ProcessNotRunning   = 'Confirm {0} is installed and started, or mark the entry Optional in WinContextDeploy.psd1.'
            UnknownAction       = "Unknown Action '{0}' for step '{1}'. Valid: {2}."
            RequiresAdmin       = 'Requires Administrator. Relaunch elevated to apply.'
            PowerCfgFailed      = 'powercfg refused the change. Check that no Group Policy pins the power plan.'
            RegistryGpo         = "This machine's policy prevents the change; it must be applied by Group Policy instead."
            RegistryWriteFailed = 'The registry value could not be written. Check that the key is not held by another process.'
            PrinterUnreachable  = "Print server {0} is unreachable. Check the connection, or remove Printers['{1}'] from WinContextDeploy.psd1."
            DiskUnhealthy       = 'Replace {0} before handover.'
            DiskLowFreeSpace    = 'Free up space before handover, or raise Disk.MinFreeGB in WinContextDeploy.psd1 if that threshold is wrong for this fleet.'
        }
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
            Network        = 'Adaptateurs reseau'
            DiskHealth     = 'Sante du disque'
            DiskFreeSpace  = 'Espace libre'
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
        PromptFormFactor        = 'Type de poste (Portable ou Bureau ?)'
        PromptFormFactorDesc1   = '  Portable = laptop avec batterie  |  Bureau = ordinateur fixe sans batterie'
        PromptFormFactorDesc2   = "  Affecte les parametres de veille et de gestion d energie."
        PromptEnvironment       = 'Usage du poste (Principal = local | Secondaire = Citrix ?)'
        PromptUsageDesc1        = '  Principal = poste physique local  -> ouvre les fichiers de SAP Front End et MicroFocus'
        PromptUsageDesc2        = '  Secondaire = poste Citrix         -> ouvre la page de telechargement Citrix Workspace'
        PromptOpenApps          = 'Ouvrir les applications de configuration {0} ?'
        PromptOpenAppsDesc1     = '  Ouvre les applications declarees dans WinContextDeploy.psd1.'
        PromptOpenAppsDesc2     = '  Repondre Oui sauf si les applications ont deja ete ouvertes manuellement.'
        PromptEngineer          = "Poste d ingenieur ? (propose les outils optionnels)"
        PromptEngineerDesc1     = '  Propose les extras declares Prompt dans WinContextDeploy.psd1.'
        PromptEngineerDesc2     = '  Repondre Non pour un poste standard.'
        MissingModuleData       = 'Aucune donnee retournee par le module.'
        MissingStepTech         = 'Etape technique manquante: {0}'
        ApplicationManualDetail = 'Ouverture ignoree (repondu Non). Verification manuelle requise.'
        StandardManualDetail    = 'A faire manuellement.'
        SecondaryNA             = 'Non applicable au type de poste ou a l usage choisi.'
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
        ElevationRequest        = 'Les options d alimentation exigent les droits Administrateur. Demande d elevation...'
        ElevationDeclined       = 'Poursuite sans droits Administrateur. Les etapes d alimentation seront signalees comme exigeant une elevation.'
        ElevationUncWarning     = '[AVERTISSEMENT] -HistoryLogPath pointe vers un partage reseau ({0}). L elevation ouvre une nouvelle session d ouverture, qui perd les lecteurs mappes: l export historique peut echouer apres le relancement.'
        ReportWritten           = 'Rapport JSON ecrit dans: {0}'
        ReportFailed            = '[AVERTISSEMENT] Rapport JSON impossible a ecrire dans {0}. Detail: {1}'
        # Remediation: la prochaine action concrete pour le technicien.
        # L exception brute reste dans le log; ceci va a l ecran.
        Remedy                  = @{
            TargetMissing       = "Introuvable a {0}. Corriger Applications['{1}'].Target dans WinContextDeploy.psd1, ou retirer l entree."
            TargetLaunchFailed  = "Impossible de demarrer {0}. Verifier Applications['{1}'].Target et Action dans WinContextDeploy.psd1."
            ProcessNotRunning   = 'Confirmer que {0} est installe et demarre, ou marquer l entree Optional dans WinContextDeploy.psd1.'
            UnknownAction       = "Action '{0}' inconnue pour l etape '{1}'. Valides: {2}."
            RequiresAdmin       = 'Exige les droits Administrateur. Relancer en tant qu administrateur pour appliquer.'
            PowerCfgFailed      = 'powercfg a refuse la modification. Verifier qu aucune GPO ne fige le mode de gestion d alimentation.'
            RegistryGpo         = 'La politique de ce poste empeche la modification; elle doit passer par une GPO.'
            RegistryWriteFailed = 'La valeur de registre n a pas pu etre ecrite. Verifier que la cle n est pas detenue par un autre processus.'
            PrinterUnreachable  = "Serveur d impression {0} injoignable. Verifier la connexion, ou retirer Printers['{1}'] de WinContextDeploy.psd1."
            DiskUnhealthy       = 'Remplacer {0} avant la remise du poste.'
            DiskLowFreeSpace    = 'Liberer de l espace avant la remise du poste, ou augmenter Disk.MinFreeGB dans WinContextDeploy.psd1 si ce seuil ne convient pas au parc.'
        }
    }
}

# --- Script folder resolution ---
$scriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptDir)) {
    $scriptDir = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
}
if ([string]::IsNullOrWhiteSpace($scriptDir)) {
    $scriptDir = (Get-Location).Path
}

# --- Shared helpers ---
$helpersPath = Join-Path $scriptDir 'WcdHelpers.ps1'
if (-not (Test-Path -LiteralPath $helpersPath)) {
    Write-Host ($T.FatalHelpersMissing -f $scriptDir) -ForegroundColor Red
    exit 1
}
. $helpersPath

# --- Manifest ---
try {
    $script:WcdConfig = Import-WcdConfig -ConfigPath $ConfigPath
} catch {
    Write-Host ($T.FatalConfig -f $_.Exception.Message) -ForegroundColor Red
    exit 1
}

function Show-WcdBanner {
    <#
    .SYNOPSIS
        Prints the startup banner.

    .DESCRIPTION
        Reads banner.txt from the project root. Art wider than the console, or a
        missing file, falls back to a plain title rather than a wrapped mess.

    .OUTPUTS
        None. Writes to the host.

    .EXAMPLE
        Show-WcdBanner
    #>
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
    <#
    .SYNOPSIS
        Asks the technician to pick one option, with arrow keys.

    .DESCRIPTION
        Redraws the option line in place with a carriage return, never with
        absolute cursor coordinates, so the prompt stays readable anywhere in the
        buffer including after scrolling. When the input is redirected or the host
        has no RawUI it falls back to a plain typed prompt.

    .PARAMETER Prompt
        The question to ask.

    .PARAMETER Choices
        Ordered dictionary of shortcut key -> canonical value.

    .PARAMETER DefaultKey
        Key selected when the prompt opens, and returned on a bare Enter.

    .PARAMETER Description
        Explanatory lines shown under the question.

    .OUTPUTS
        The canonical value behind the chosen key.

    .EXAMPLE
        Read-WcdChoice -Prompt 'Form factor' -Choices ([ordered]@{ L = 'Laptop'; D = 'Desktop' }) -DefaultKey 'L'
    #>
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

    # Internal fallback: used ONLY when interactive key reading is
    # unavailable (redirected input, or a host with no RawUI).
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

    # Only redirected input or a host without RawUI forces the text fallback.
    # Buffer geometry plays no part, so every question stays as interactive as
    # the first one, however far the console has scrolled.
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

    # Static part, written once: the question, its description and the hint.
    Write-Host $Prompt -ForegroundColor Cyan
    foreach ($desc in $Description) { Write-Host $desc -ForegroundColor DarkGray }
    Write-Host $T.NavHint -ForegroundColor DarkGray

    # The option line is redrawn in place with a carriage return. No absolute
    # coordinates are used, so the rendering stays correct anywhere in the
    # buffer, including at the very bottom after scrolling.
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
            37 { $selectedIndex = ($selectedIndex - 1 + $entries.Count) % $entries.Count }  # Left
            38 { $selectedIndex = ($selectedIndex - 1 + $entries.Count) % $entries.Count }  # Up
            39 { $selectedIndex = ($selectedIndex + 1) % $entries.Count }                   # Right
            40 { $selectedIndex = ($selectedIndex + 1) % $entries.Count }                   # Down
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
    <#
    .SYNOPSIS
        Parses a combined optional-tools answer such as "12" into its digits.

    .DESCRIPTION
        The menu lets the technician type several numbers at once. Duplicates are
        collapsed and the result is sorted, so "21", "12" and "122" all mean the
        same two tools. Any character outside the valid keys rejects the whole
        answer rather than silently running a subset.

    .PARAMETER RawInput
        What the technician typed.

    .PARAMETER ValidKeys
        The keys currently on the menu.

    .OUTPUTS
        [string[]] The selected keys, or an empty array when the input is invalid.

    .EXAMPLE
        ConvertTo-WcdOptionalToolSelection -RawInput '21' -ValidKeys @('1','2','3')   # 1, 2
    #>
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
    <#
    .SYNOPSIS
        Shows the Optional Tools menu and returns what the technician picked.

    .PARAMETER Candidates
        Prompt entries from the manifest, from Get-WcdPromptedApplicationTarget.

    .OUTPUTS
        [string[]] Names of the selected Application Targets.

    .EXAMPLE
        Read-WcdOptionalToolChoice -Candidates (Get-WcdPromptedApplicationTarget -Config $config)
    #>
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
    <#
    .SYNOPSIS
        Waits for Enter before finishing the run.

    .DESCRIPTION
        The tool is usually double-clicked, so the window would close on the final
        Diagnostic without this. Falls back to Read-Host when the host has no RawUI.

    .PARAMETER Message
        Prompt shown while waiting.

    .OUTPUTS
        None.

    .EXAMPLE
        Wait-WcdForEnter -Message 'Press Enter to finish the script.'
    #>
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
    <#
    .SYNOPSIS
        Resolves the machine context, prompting for whatever was not supplied.

    .DESCRIPTION
        A parameter given on the command line is never asked about again, which is
        what makes -NonInteractive and the interactive run the same code path. The
        Optional Tools menu is only offered when the manifest declares at least one
        Prompt entry.

    .PARAMETER SelectedLanguage
        Windows display language, or empty to prompt.

    .PARAMETER SelectedFormFactor
        'Laptop' or 'Desktop', or empty to prompt.

    .PARAMETER SelectedEnvironment
        'Workstation' or 'Vdi', or empty to prompt.

    .PARAMETER SelectedOpenApps
        'Yes' or empty to prompt.

    .PARAMETER SelectedOptionalTools
        Comma-separated Optional Tool names, or empty to prompt.

    .PARAMETER OptionalToolCandidates
        Prompt entries available to offer.

    .PARAMETER DisablePrompt
        Ask nothing: use what was supplied, and the defaults for the rest.

    .OUTPUTS
        [pscustomobject] with Language, FormFactor, Environment, OpenApps and
        OptionalTools.

    .EXAMPLE
        Resolve-WcdExecutionOptions -SelectedFormFactor 'Desktop' -DisablePrompt
    #>
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
            $deviceResult = Read-WcdChoice -Prompt $T.PromptFormFactor -Choices ([ordered]@{ $T.KeyLaptop = 'Laptop'; $T.KeyDesktop = 'Desktop' }) -DefaultKey $T.KeyLaptop `
                -Description @($T.PromptFormFactorDesc1, $T.PromptFormFactorDesc2)
        }

        if (-not $usageResult) {
            Write-Host ''
            $usageResult = Read-WcdChoice -Prompt $T.PromptEnvironment -Choices ([ordered]@{ $T.KeyWorkstation = 'Workstation'; $T.KeyVdi = 'Vdi' }) -DefaultKey $T.KeyWorkstation `
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

# --- Run options and log ---
Show-WcdBanner

# --- Elevation ---------------------------------------------------------------
# Only the power steps need Administrator. Offer the standard UAC prompt once;
# if the technician declines, or has no rights to give, the run carries on and
# the power steps report as actionable warnings instead of failures.
#
# An unattended run is never prompted: a modal UAC dialog with nobody there to
# click it is a hang, not a prompt. It degrades to the unelevated report instead.
$isElevated = Test-WcdElevated
if (-not $isElevated -and -not $Elevated -and -not $NonInteractive) {
    if (Test-WcdUncPath -Path $HistoryLogPath) {
        # UAC opens a different logon session, which drops mapped drives. A USB
        # drive letter is physical and survives; a UNC path does not.
        Write-Host ($T.ElevationUncWarning -f $HistoryLogPath) -ForegroundColor Yellow
    }

    Write-Host $T.ElevationRequest -ForegroundColor Cyan
    try {
        $relaunchArguments = Get-WcdRelaunchArgument `
            -ScriptPath $PSCommandPath `
            -BoundParameters $PSBoundParameters `
            -WorkingDirectory (Get-Location).Path
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $relaunchArguments -ErrorAction Stop
        exit 0
    } catch {
        # Declining UAC throws here, and so does having no admin rights at all.
        Write-Host $T.ElevationDeclined -ForegroundColor Yellow
    }
}


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
Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message '=== WinContextDeploy run started ==='
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
    <#
    .SYNOPSIS
        Ranks a severity so the worst outcome can be found.

    .PARAMETER Severity
        'ERROR', 'WARNING' or anything else.

    .OUTPUTS
        [int] 3 for ERROR, 2 for WARNING, 1 otherwise.

    .EXAMPLE
        Get-WcdSeverityRank -Severity 'WARNING'   # 2
    #>
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
    <#
    .SYNOPSIS
        Collects the Results belonging to a set of Step keys.

    .PARAMETER ResultLookup
        Step key -> Results, built from the run.

    .PARAMETER StepKeys
        Step keys to collect, in order.

    .OUTPUTS
        [object[]] The matching Results. Empty when the Module did not run.

    .EXAMPLE
        Get-WcdResultsForSteps -ResultLookup $lookup -StepKeys @('ScreenTimeoutAc')
    #>
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
    <#
    .SYNOPSIS
        Returns the worst Result in a set.

    .DESCRIPTION
        A checklist row covering several Steps takes the colour of its worst one:
        one failed power step must not be hidden by four that worked.

    .PARAMETER Results
        Results to compare.

    .OUTPUTS
        The worst Result, or $null when they are all informational.

    .EXAMPLE
        Get-WcdStrongestResult -Results $powerResults
    #>
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

function Format-WcdRemedy {
    <#
    .SYNOPSIS
        Renders the remediation sentence carried by a Step Result.

    .DESCRIPTION
        Modules name a remedy by key, never by sentence, so the text lives in
        the $T tables and is localized like everything else the technician
        reads. A Result with no RemedyKey renders nothing.

    .PARAMETER Result
        A Step Result, optionally carrying RemedyKey and RemedyArgs.

    .OUTPUTS
        [string] The remediation sentence, or an empty string.

    .EXAMPLE
        Format-WcdRemedy -Result ([pscustomobject]@{ RemedyKey = 'RequiresAdmin' })
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Result
    )

    if ($null -eq $Result) { return '' }

    $keyProperty = $Result.PSObject.Properties['RemedyKey']
    if ($null -eq $keyProperty -or [string]::IsNullOrWhiteSpace([string]$keyProperty.Value)) { return '' }

    $key = [string]$keyProperty.Value
    if (-not $T.Remedy.ContainsKey($key)) { return '' }

    $template = [string]$T.Remedy[$key]
    $argsProperty = $Result.PSObject.Properties['RemedyArgs']
    $remedyArgs = if ($null -ne $argsProperty) { @($argsProperty.Value) } else { @() }
    if ($remedyArgs.Count -eq 0) { return $template }

    try {
        return ($template -f $remedyArgs)
    } catch {
        # A template and its arguments out of step must never break the report.
        return $template
    }
}

function Get-WcdAggregateDetail {
    <#
    .SYNOPSIS
        Builds the detail text for a checklist row covering several Steps.

    .DESCRIPTION
        Names each Step that has something to say, followed by its remediation
        where there is one. Purely informational Results with nothing to report are
        left out so a healthy row stays quiet.

    .PARAMETER Results
        Results behind the row.

    .PARAMETER StepLabels
        Step key -> label.

    .OUTPUTS
        [string] The joined detail text.

    .EXAMPLE
        Get-WcdAggregateDetail -Results $results -StepLabels $labels
    #>
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
        # What failed, then what to do about it. The raw exception stays in the
        # log; the remediation is what the technician needs on screen.
        $remedy = Format-WcdRemedy -Result $result
        $text = if ([string]::IsNullOrWhiteSpace($result.Error)) { $stepLabel } else { '{0}: {1}' -f $stepLabel, $result.Error }
        if (-not [string]::IsNullOrWhiteSpace($remedy)) {
            $text = '{0} -> {1}' -f $text, $remedy
        }
        $details += $text
    }

    return ($details -join ' | ')
}

function New-WcdDiagnosticEntry {
    <#
    .SYNOPSIS
        Builds one row of the technician's checklist.

    .PARAMETER Label
        What the technician sees.

    .PARAMETER Kind
        'success', 'warning', 'error', 'manual' or 'na'.

    .PARAMETER Detail
        Extra text shown after the status, including any remediation.

    .PARAMETER Step
        Step key(s) behind the row, comma-joined when a row covers several.
        Empty for a Manual Step, which has no Step behind it. Carried so the
        JSON report can name the step a consumer should key on.

    .OUTPUTS
        [pscustomobject] with Step, Label, Kind and Detail.

    .EXAMPLE
        New-WcdDiagnosticEntry -Label 'Wi-Fi' -Kind 'manual' -Detail 'Must be done manually.'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Label,

        [Parameter(Mandatory)]
        [ValidateSet('success', 'warning', 'error', 'manual', 'na')]
        [string]$Kind,

        [string]$Detail = '',

        [string]$Step = ''
    )

    return [pscustomobject]@{
        Step   = $Step
        Label  = $Label
        Kind   = $Kind
        Detail = $Detail
    }
}

function Resolve-WcdAutomaticEntry {
    <#
    .SYNOPSIS
        Turns the Results of one or more Steps into a checklist row.

    .DESCRIPTION
        The row takes the worst severity found. A Step the Module never reported is
        a warning naming the missing step, not a silent success - a Module that
        half-ran must not read as green.

    .PARAMETER Label
        What the technician sees.

    .PARAMETER ResultLookup
        Step key -> Results.

    .PARAMETER StepKeys
        Step keys behind this row.

    .PARAMETER StepLabels
        Step key -> label.

    .PARAMETER MissingKind
        Kind used when no Result at all was produced: 'warning', 'manual' or 'na'.

    .PARAMETER MissingDetail
        Detail used in that case.

    .OUTPUTS
        [pscustomobject] one checklist entry.

    .EXAMPLE
        Resolve-WcdAutomaticEntry -Label 'Power options' -ResultLookup $lookup `
            -StepKeys @('ScreenTimeoutAc') -StepLabels $labels
    #>
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

    $stepId = (@($StepKeys) -join ',')
    $results = @(Get-WcdResultsForSteps -ResultLookup $ResultLookup -StepKeys $StepKeys)
    if ($results.Count -eq 0) {
        return New-WcdDiagnosticEntry -Label $Label -Kind $MissingKind -Detail $MissingDetail -Step $stepId
    }

    $missingStepKeys = @($StepKeys | Where-Object { -not $ResultLookup.ContainsKey($_) })
    $strongest = Get-WcdStrongestResult -Results $results
    $severity = Get-WcdResultSeverity -Result $strongest

    if ($severity -eq 'ERROR') {
        return New-WcdDiagnosticEntry -Label $Label -Kind 'error' -Detail (Get-WcdAggregateDetail -Results $results -StepLabels $StepLabels) -Step $stepId
    }

    if ($severity -eq 'WARNING') {
        return New-WcdDiagnosticEntry -Label $Label -Kind 'warning' -Detail (Get-WcdAggregateDetail -Results $results -StepLabels $StepLabels) -Step $stepId
    }

    if ($missingStepKeys.Count -gt 0) {
        $missingLabels = @($missingStepKeys | ForEach-Object {
            if ($StepLabels.ContainsKey($_)) { $StepLabels[$_] } else { $_ }
        })
        return New-WcdDiagnosticEntry -Label $Label -Kind 'warning' -Detail ($T.MissingStepTech -f ($missingLabels -join ', ')) -Step $stepId
    }

    # A Step can succeed and still have something to say - an Optional target
    # that is simply absent is a note, not a warning, and the technician still
    # needs to see it.
    return New-WcdDiagnosticEntry -Label $Label -Kind 'success' -Step $stepId `
        -Detail (Get-WcdAggregateDetail -Results $results -StepLabels $StepLabels)
}

function Get-WcdModuleStatusKind {
    <#
    .SYNOPSIS
        Maps a Module's status word to a diagnostic kind.

    .PARAMETER Status
        The localized status word from the per-module table.

    .OUTPUTS
        [string] 'success', 'warning' or 'error'.

    .EXAMPLE
        Get-WcdModuleStatusKind -Status 'OK'   # success
    #>
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
    <#
    .SYNOPSIS
        Renders one row of the per-Module diagnostic.

    .PARAMETER ModuleStatus
        A module status object: Module, Status, Etapes, Detail.

    .OUTPUTS
        [string] The rendered line.

    .EXAMPLE
        Format-WcdModuleLine -ModuleStatus $moduleStatus[0]
    #>
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
    <#
    .SYNOPSIS
        Renders one row of the technician's checklist.

    .PARAMETER Entry
        A checklist entry: Label, Kind, Detail.

    .OUTPUTS
        [string] The rendered line.

    .EXAMPLE
        Format-WcdChecklistLine -Entry $entry
    #>
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
    <#
    .SYNOPSIS
        Prints a boxed section header.

    .PARAMETER Title
        The section title.

    .OUTPUTS
        None. Writes to the host.

    .EXAMPLE
        Write-WcdSectionHeader -Title 'FINAL DIAGNOSTIC - BY STEP'
    #>
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
    <#
    .SYNOPSIS
        Builds the technician's checklist: every Step, in the order it was run.

    .DESCRIPTION
        The one place the run is turned into what the technician reads, and the
        source the JSON report is built from, so the two can never disagree.

        An Application Target filtered out by the current Environment or Form
        Factor is reported Not Applicable rather than omitted, so it is visible
        that it was considered. Targets skipped because the technician declined the
        prompt become Manual Steps. Printers are automatic when the manifest
        declares queues and a Manual Step when it does not.

    .PARAMETER AllResults
        Every Result produced by the run.

    .PARAMETER ExecutionOptions
        Resolved run options, used to pick the Steps that apply.

    .PARAMETER StepLabels
        Step key -> label.

    .PARAMETER Config
        The imported manifest.

    .OUTPUTS
        [pscustomobject[]] with Step, Label, Kind and Detail.

    .EXAMPLE
        Get-WcdFinalChecklistEntries -AllResults $results -ExecutionOptions $options `
            -StepLabels $labels -Config $config
    #>
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
    $entries += Resolve-WcdAutomaticEntry -Label $T.Checklist.DiskHealth -ResultLookup $lookup `
        -StepKeys @('DiskHealth') -StepLabels $StepLabels
    $entries += Resolve-WcdAutomaticEntry -Label $T.Checklist.DiskFreeSpace -ResultLookup $lookup `
        -StepKeys @('DiskFreeSpace') -StepLabels $StepLabels
    $entries += Resolve-WcdAutomaticEntry -Label $T.Checklist.Network -ResultLookup $lookup `
        -StepKeys @('NetworkAdapterStatus', 'NetworkPing8888', 'RefreshNetworkPlaces') -StepLabels $StepLabels

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
            $entries += New-WcdDiagnosticEntry -Label $name -Kind 'na' -Detail $T.SecondaryNA -Step $step
            continue
        }

        if ($applicationsSkipped) {
            $entries += New-WcdDiagnosticEntry -Label $name -Kind 'manual' -Detail $T.ApplicationManualDetail -Step $step
            continue
        }

        $entries += Resolve-WcdAutomaticEntry -Label $name -ResultLookup $lookup `
            -StepKeys @($step) -StepLabels $StepLabels
    }

    # --- Printers ------------------------------------------------------------
    # Declared in the manifest: the Module connects them and reports per queue.
    # None declared: they stay a Manual Step, as they were before.
    $printerTargets = @(Get-WcdPrinterTarget -Config $Config)
    if ($printerTargets.Count -gt 0) {
        $entries += Resolve-WcdAutomaticEntry -Label $T.Checklist.Printers -ResultLookup $lookup `
            -StepKeys @($printerTargets | ForEach-Object { Get-WcdPrinterStepKey -Name ([string]$_.Name) }) `
            -StepLabels $StepLabels
    }

    # --- Deliberately manual: WinContextDeploy does not automate these --------
    $manualLabels = @(
        $T.Checklist.Signature,
        $T.Checklist.Wifi,
        $T.Checklist.NetworkDrives,
        $T.Checklist.Sync,
        $T.Checklist.Desktop,
        $T.Checklist.Favorites
    )
    if ($printerTargets.Count -eq 0) { $manualLabels += $T.Checklist.Printers }

    foreach ($manualLabel in $manualLabels) {
        $entries += New-WcdDiagnosticEntry -Label $manualLabel -Kind 'manual' -Detail $T.StandardManualDetail
    }

    return $entries
}

function Get-WcdFinalDiagnosticLines {
    <#
    .SYNOPSIS
        Renders the whole final Diagnostic as plain text lines.

    .DESCRIPTION
        Same content as the console output, without colour, for the history log.

    .PARAMETER ModuleStatus
        Per-Module rollup rows.

    .PARAMETER ChecklistEntries
        The technician's checklist entries.

    .PARAMETER SummaryLine
        The one-line count summary.

    .OUTPUTS
        [string[]] The rendered Diagnostic.

    .EXAMPLE
        Get-WcdFinalDiagnosticLines -ModuleStatus $moduleStatus -ChecklistEntries $entries -SummaryLine $summary
    #>
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

# --- Modules to run, in order ---
$modules = @(
    @{ Name = 'Config-Power';         File = 'Config-Power.ps1' },
    @{ Name = 'Config-Decimal';       File = 'Config-Decimal.ps1' },
    @{ Name = 'Config-TaskbarLeft';   File = 'Config-TaskbarLeft.ps1' },
    @{ Name = 'Config-Language';      File = 'Config-Language.ps1' },
    @{ Name = 'Config-Applications';  File = 'Config-Applications.ps1' },
    @{ Name = 'Config-DeviceManager'; File = 'Config-DeviceManager.ps1' },
    @{ Name = 'Config-Disk';          File = 'Config-Disk.ps1' },
    @{ Name = 'Config-Network';       File = 'Config-Network.ps1' },
    @{ Name = 'Config-Printer';       File = 'Config-Printer.ps1' }
)

$stepLabels = Get-WcdTechnicalStepLabels -Config $script:WcdConfig
$moduleStepPlan = Get-WcdModuleProgressPlan -ExecutionOptions $executionOptions -Config $script:WcdConfig
$allResults = @()
$moduleStatus = @()

foreach ($mod in $modules) {
    $modPath = Join-Path $scriptDir $mod.File
    $modName = $mod.Name

    # Nothing planned means nothing declared in the manifest: skip the Module
    # entirely rather than report an empty run of it.
    if ($moduleStepPlan.ContainsKey($modName) -and @($moduleStepPlan[$modName]).Count -eq 0) {
        continue
    }

    # The module file must exist
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

    # Load the module (dot-source)
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

    # Run the module
    $modResults = @()
    $modError = $null
    $startTime = Get-Date
    $progressState = New-WcdProgressState -ModuleName $modName -StepKeys $moduleStepPlan[$modName] -StepLabels $stepLabels
    $progressCallback = {
        param($eventData)

        Update-WcdProgressState -State $progressState -StepKey $eventData.Step -Event $eventData.Event
    }

    try {
        switch ($modName) {
            'Config-Power' {
                $modResults = @(Set-WcdPowerConfiguration -FormFactor $executionOptions.FormFactor -Elevated $isElevated -LogPath $resolvedLogPath -ProgressCallback $progressCallback)
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
            'Config-Disk' {
                $modResults = @(Set-WcdDiskStatus -Config $script:WcdConfig -LogPath $resolvedLogPath -ProgressCallback $progressCallback)
            }
            'Config-Network' {
                $modResults = @(Set-WcdNetworkDiagnostics -Config $script:WcdConfig -LogPath $resolvedLogPath -ProgressCallback $progressCallback)
            }
            'Config-Printer' {
                $modResults = @(Set-WcdPrinterConfiguration -Config $script:WcdConfig -LogPath $resolvedLogPath -ProgressCallback $progressCallback)
            }
        }
    } catch {
        $modError = $_.Exception.Message
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ("Module ${modName} crashed: {0}" -f $modError)
    }

    $duration = (Get-Date) - $startTime

    # Count the results
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

# --- Machine-readable run summary -------------------------------------------
# Built from the entries the technician just saw, so the JSON and the console
# can never disagree. Failing to write it warns and carries on, like the
# history export: a fleet collector is not worth losing a run over.
if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
    try {
        $reportParent = Split-Path -Path $ReportPath -Parent
        if (-not [string]::IsNullOrWhiteSpace($reportParent) -and -not (Test-Path -LiteralPath $reportParent)) {
            New-Item -Path $reportParent -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }

        $report = New-WcdRunReport -ChecklistEntries $checklistEntries -ExecutionOptions $executionOptions -Elevated $isElevated
        # Depth 5: the default of 2 silently flattens steps into type names.
        $report | ConvertTo-Json -Depth 5 | Set-Content -Path $ReportPath -Encoding UTF8 -ErrorAction Stop

        Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('JSON report written to: {0}' -f $ReportPath)
        Write-Host ($T.ReportWritten -f $ReportPath) -ForegroundColor Gray
    } catch {
        $reportError = $_.Exception.Message
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ('JSON report failed: {0}' -f $reportError)
        Write-Host ($T.ReportFailed -f $ReportPath, $reportError) -ForegroundColor Yellow
    }
}

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
