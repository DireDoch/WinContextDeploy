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

.PARAMETER NewComputerName
    Rename the machine to this, without asking. Validated the same way a typed
    name is; nothing is applied until the machine restarts.

.PARAMETER JoinDomain
    Join the domain declared in the manifest. Still opens the credential dialog,
    so it does not make an unattended join possible.

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

    [string]$NewComputerName,

    [switch]$JoinDomain,

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
            Winget         = 'App Installer (winget)'
            WindowsUpdate  = 'Windows Update'
            DiskHealth     = 'Disk health'
            DiskFreeSpace  = 'Free space'
            Tpm            = 'TPM readiness'
            BitLocker      = 'Drive encryption'
            ComputerName   = 'Computer name'
            DomainJoin     = 'Domain membership'
            RestartNeeded  = 'Restart required'
        }
        KeyLaptop               = 'L'
        KeyDesktop              = 'D'
        KeyWorkstation          = 'W'
        KeyVdi                  = 'V'
        KeyYes                  = 'Y'
        KeyNo                   = 'N'
        Labels                  = @{
            Laptop       = 'Laptop'
            Desktop      = 'Desktop'
            Workstation  = 'Workstation'
            Vdi          = 'Citrix / VDI'
            Yes          = 'Yes'
            No           = 'No'
            Neither      = 'Neither'
            ComputerName = 'Computer name'
            Domain       = 'Domain'
            Both         = 'Both'
        }
        NoChoicesAvailable      = 'No choices available.'
        DefaultLabel            = '[default]'
        InvalidChoice           = 'Invalid choice. Try again.'
        NavHint                 = 'Use Left/Right to change, then Enter to confirm.'
        FallbackEnterHint       = 'Press Enter to continue'
        OptionalToolBoxTitle    = 'Engineer configuration - multiple choices'
        OptionalToolCombineHint = '  Combine numbers for multiple choices (e.g: 12 = Nvidia + GPS)'
        OptionalToolChoicePrompt = '  Your choice'
        OptionalToolAtLeastOne  = '  Please enter at least one number.'
        OptionalToolInvalidChoice = '  Invalid choice. Valid numbers: {0}'
        OptionalToolSelection   = '  Selection: {0}'
        WaitEnterFinish         = 'Press Enter to finish the script.'
        WaitEnterExport         = 'Press Enter to finish the script and export logs to the removable drive.'
        PromptLanguage          = 'Windows system language'
        PromptLanguageDesc      = '  fr-CA = French Canadian Windows interface  |  en-US = American English'
        PromptFormFactor        = 'Machine form factor'
        PromptFormFactorDesc1   = '  Laptop = has a battery and a lid  |  Desktop = neither'
        PromptFormFactorDesc2   = '  Selects the power profile: battery and lid-close settings.'
        PromptEnvironment       = 'Machine environment'
        PromptEnvironmentDesc1  = '  Workstation = full local machine  -> checks the locally installed applications'
        PromptEnvironmentDesc2  = '  Citrix / VDI = thin endpoint      -> its applications live in the remote session'
        PromptOpenApps          = 'Open {0} configuration applications?'
        PromptOpenAppsDesc1     = '  Opens the Application Targets declared in WinContextDeploy.psd1.'
        PromptOpenAppsDesc2     = '  Answer Yes unless applications were already opened manually.'
        KeyNeither              = 'N'
        KeyComputerName         = 'C'
        KeyDomain               = 'D'
        KeyBoth                 = 'B'
        PromptIdentity          = 'Machine identity'
        PromptIdentitySerial    = '  Serial: {0}   (read-only, from firmware)'
        PromptIdentityDesc1     = '  Change the computer name, or join the domain?'
        PromptIdentityDesc2     = '  Neither is applied until the machine restarts.'
        PromptIdentityDomain    = '  Domain: {0}'
        PromptComputerName      = 'New computer name'
        PromptComputerNameDesc  = '  1-15 characters, letters digits and hyphens, not all digits.'
        ComputerNameRejected    = @{
            Length     = '  Rejected: a computer name is 1 to 15 characters.'
            Characters = '  Rejected: no spaces, and none of \ / : * ? " < > | . , ~ ! @ # $ % ^ & ( ) { } _'
            AllDigits  = '  Rejected: a computer name cannot be all digits.'
            Unchanged  = '  That is already the name of this machine.'
        }
        CredentialPrompt        = 'Domain account allowed to join {0}'
        PromptOptionalTool      = 'Engineering workstation? (offers the optional tools)'
        PromptOptionalToolDesc1 = '  Offers the extras declared Prompt in WinContextDeploy.psd1.'
        PromptOptionalToolDesc2 = '  Answer No for a standard device.'
        MissingModuleData       = 'No data returned by the module.'
        MissingStepTech         = 'Missing technical step: {0}'
        ApplicationManualDetail = 'Launch skipped (answered No). Manual verification required.'
        StandardManualDetail    = 'Must be done manually.'
        IdentityManualDetail    = 'Not requested this run. Must be done manually if the machine needs it.'
        RestartManualDetail     = 'New computer name / domain membership takes effect after a restart.'
        RestartUpdateManualDetail = 'An installed Windows update is waiting on a restart.'
        RestartBothManualDetail = 'One restart covers both: the new computer name / domain membership, and an installed Windows update waiting on it.'
        SecondaryNA             = 'Not applicable to the chosen Form Factor or Environment.'
        DeskWindowsDetail       = 'Must be done manually on the Windows desktop.'
        StepCount               = 'step(s)'
        ModuleResult            = '  Result: {0} ({1} steps, {2} failures, {3} warnings, {4:N0}ms)'
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
        FatalHelpersMissing     = '[FATAL ERROR] {0} not found in: {1}'
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
        ElevationRequest        = 'The power settings, the encryption check and a domain join need Administrator. Requesting elevation...'
        ElevationDeclined       = 'Continuing without Administrator. The power, encryption and machine identity steps will report as needing elevation.'
        ElevationUncWarning     = '[WARNING] -HistoryLogPath points at a network share ({0}). Elevation opens a new logon session, which drops mapped drives, so the history export may fail after the relaunch.'
        ReportWritten           = 'JSON report written to: {0}'
        ReportFailed            = '[WARNING] JSON report could not be written to {0}. Detail: {1}'
        # Remediation: what the technician should do next. The raw exception
        # stays in the log; this is what goes on screen.
        Remedy                  = @{
            TargetMissing       = "Not found at {0}. Update Applications['{1}'].Target in WinContextDeploy.psd1, or remove the entry."
            TargetLaunchFailed  = "Could not start {0}. Check Applications['{1}'].Target and Action in WinContextDeploy.psd1."
            ProcessNotRunning   = 'Confirm {0} is installed and started, or mark the entry Optional in WinContextDeploy.psd1.'
            WingetMissing       = 'App Installer (winget) is not provisioned on this image, so the packages below could not be checked. Verify them by hand, or install App Installer from the Microsoft Store.'
            WingetPackageMissing = "winget does not list {0} as installed. Confirm imaging delivered it, or fix the package id in Applications['{1}'].Target in WinContextDeploy.psd1."
            WingetCheckFailed   = "winget could not check {0}. Run 'winget list --id {1} --exact' by hand to see why."
            WindowsUpdateFailed = 'Run Windows Update by hand and let the failed update through before handover.'
            RebootPending       = 'Restart the machine before handover; the update is not finished until it does.'
            UnknownAction       = "Unknown Action '{0}' for step '{1}'. Valid: {2}."
            RequiresAdmin       = 'Requires Administrator. Relaunch elevated to apply.'
            PowerCfgFailed      = 'powercfg refused the change. Check that no Group Policy pins the power plan.'
            RegistryGpo         = "This machine's policy prevents the change; it must be applied by Group Policy instead."
            RegistryWriteFailed = 'The registry value could not be written. Check that the key is not held by another process.'
            PrinterUnreachable  = "Print server {0} is unreachable. Check the connection, or remove Printers['{1}'] from WinContextDeploy.psd1."
            DiskUnhealthy       = 'Replace {0} before handover.'
            DiskLowFreeSpace    = 'Free up space before handover, or raise Disk.MinFreeGB in WinContextDeploy.psd1 if that threshold is wrong for this fleet.'
            TpmNotReady         = 'Enable the TPM (PTT or fTPM) in the firmware. A TPM that is present but not ready usually needs clearing or initialising from tpm.msc.'
            BitLockerOff        = 'Enable BitLocker on the system drive before handover, or confirm the fleet policy applies it after enrolment.'
            BitLockerInProgress = 'Encryption is still running. Let it finish before handover; the drive is not protected until it does.'
            ComputerNameInvalid = 'The name "{0}" is not a usable computer name. Re-run and type 1 to 15 characters, letters digits and hyphens only.'
            ComputerNameFailed  = 'The rename was refused. Check that the run is elevated and that no policy pins the computer name.'
            DomainJoinFailed    = 'The domain join failed. Check the domain is reachable, the account may join machines, and Domain.OUPath in WinContextDeploy.psd1 exists.'
            JoinCancelled       = 'The credential dialog was cancelled. Re-run and supply a domain account, or join the machine by hand.'
            BitLockerUnavailable = 'This edition does not support BitLocker. Confirm the machine should ship on it, or reimage with an edition that does.'
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
            Winget         = 'App Installer (winget)'
            WindowsUpdate  = 'Windows Update'
            DiskHealth     = 'Sante du disque'
            DiskFreeSpace  = 'Espace libre'
            Tpm            = 'Etat du TPM'
            BitLocker      = 'Chiffrement du disque'
            ComputerName   = 'Nom du poste'
            DomainJoin     = 'Appartenance au domaine'
            RestartNeeded  = 'Redemarrage requis'
        }
        KeyLaptop               = 'P'
        KeyDesktop              = 'B'
        KeyWorkstation          = 'P'
        KeyVdi                  = 'S'
        KeyYes                  = 'O'
        KeyNo                   = 'N'
        Labels                  = @{
            Laptop       = 'Portable'
            Desktop      = 'Bureau'
            Workstation  = 'Principal'
            Vdi          = 'Citrix'
            Yes          = 'Oui'
            No           = 'Non'
            Neither      = 'Aucun'
            ComputerName = 'Nom du poste'
            Domain       = 'Domaine'
            Both         = 'Les deux'
        }
        NoChoicesAvailable      = 'Aucun choix disponible.'
        DefaultLabel            = '[defaut]'
        InvalidChoice           = 'Choix invalide. Reessayer.'
        NavHint                 = 'Utiliser Gauche/Droite pour changer, puis Entree pour confirmer.'
        FallbackEnterHint       = 'Appuyer sur Enter pour continuer'
        OptionalToolBoxTitle    = 'Configuration ingenieur - choix multiples'
        OptionalToolCombineHint = '  Combiner les numeros pour plusieurs choix (ex: 12 = Nvidia + GPS)'
        OptionalToolChoicePrompt = '  Votre choix'
        OptionalToolAtLeastOne  = '  Veuillez entrer au moins un numero.'
        OptionalToolInvalidChoice = '  Choix invalide. Numeros valides: {0}'
        OptionalToolSelection   = '  Selection: {0}'
        WaitEnterFinish         = 'Cliquer sur Enter pour terminer le script.'
        WaitEnterExport         = 'Cliquer sur Enter pour terminer le script et envoyer les logs vers le disque amovible.'
        PromptLanguage          = 'Langue du systeme Windows'
        PromptLanguageDesc      = '  fr-CA = interface Windows en francais canadien  |  en-US = anglais americain'
        PromptFormFactor        = 'Type de poste (Portable ou Bureau ?)'
        PromptFormFactorDesc1   = '  Portable = laptop avec batterie  |  Bureau = ordinateur fixe sans batterie'
        PromptFormFactorDesc2   = "  Affecte les parametres de veille et de gestion d energie."
        PromptEnvironment       = 'Usage du poste (Principal = local | Secondaire = Citrix ?)'
        PromptEnvironmentDesc1  = '  Principal = poste physique local  -> ouvre les fichiers de SAP Front End et MicroFocus'
        PromptEnvironmentDesc2  = '  Secondaire = poste Citrix         -> ouvre la page de telechargement Citrix Workspace'
        PromptOpenApps          = 'Ouvrir les applications de configuration {0} ?'
        PromptOpenAppsDesc1     = '  Ouvre les applications declarees dans WinContextDeploy.psd1.'
        PromptOpenAppsDesc2     = '  Repondre Oui sauf si les applications ont deja ete ouvertes manuellement.'
        KeyNeither              = 'A'
        KeyComputerName         = 'N'
        KeyDomain               = 'D'
        KeyBoth                 = 'L'
        PromptIdentity          = 'Identite du poste'
        PromptIdentitySerial    = '  Numero de serie: {0}   (lecture seule, du micrologiciel)'
        PromptIdentityDesc1     = '  Changer le nom du poste, ou joindre le domaine ?'
        PromptIdentityDesc2     = '  Ni l un ni l autre ne prend effet avant le redemarrage.'
        PromptIdentityDomain    = '  Domaine: {0}'
        PromptComputerName      = 'Nouveau nom du poste'
        PromptComputerNameDesc  = '  1 a 15 caracteres, lettres chiffres et traits d union, pas que des chiffres.'
        ComputerNameRejected    = @{
            Length     = '  Refuse: un nom de poste fait de 1 a 15 caracteres.'
            Characters = '  Refuse: pas d espace, ni aucun de \ / : * ? " < > | . , ~ ! @ # $ % ^ & ( ) { } _'
            AllDigits  = '  Refuse: un nom de poste ne peut pas etre uniquement numerique.'
            Unchanged  = '  Le poste porte deja ce nom.'
        }
        CredentialPrompt        = 'Compte de domaine autorise a joindre {0}'
        PromptOptionalTool      = "Poste d ingenieur ? (propose les outils optionnels)"
        PromptOptionalToolDesc1 = '  Propose les extras declares Prompt dans WinContextDeploy.psd1.'
        PromptOptionalToolDesc2 = '  Repondre Non pour un poste standard.'
        MissingModuleData       = 'Aucune donnee retournee par le module.'
        MissingStepTech         = 'Etape technique manquante: {0}'
        ApplicationManualDetail = 'Ouverture ignoree (repondu Non). Verification manuelle requise.'
        StandardManualDetail    = 'A faire manuellement.'
        IdentityManualDetail    = 'Non demande cette fois. A faire manuellement si le poste en a besoin.'
        RestartManualDetail     = 'Le nouveau nom du poste et l appartenance au domaine prennent effet apres un redemarrage.'
        RestartUpdateManualDetail = 'Une mise a jour Windows installee attend un redemarrage.'
        RestartBothManualDetail = 'Un seul redemarrage suffit: le nouveau nom du poste et l appartenance au domaine, et une mise a jour Windows installee qui l attend.'
        SecondaryNA             = 'Non applicable au type de poste ou a l usage choisi.'
        DeskWindowsDetail       = 'A faire manuellement sur le bureau Windows.'
        StepCount               = 'etape(s)'
        ModuleResult            = '  Resultat: {0} ({1} etapes, {2} echecs, {3} avertissements, {4:N0}ms)'
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
        FatalHelpersMissing     = '[ERREUR FATALE] {0} introuvable dans: {1}'
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
        ElevationRequest        = 'Les options d alimentation, la verification du chiffrement et la jonction au domaine exigent les droits Administrateur. Demande d elevation...'
        ElevationDeclined       = 'Poursuite sans droits Administrateur. Les etapes d alimentation, de chiffrement et d identite du poste seront signalees comme exigeant une elevation.'
        ElevationUncWarning     = '[AVERTISSEMENT] -HistoryLogPath pointe vers un partage reseau ({0}). L elevation ouvre une nouvelle session d ouverture, qui perd les lecteurs mappes: l export historique peut echouer apres le relancement.'
        ReportWritten           = 'Rapport JSON ecrit dans: {0}'
        ReportFailed            = '[AVERTISSEMENT] Rapport JSON impossible a ecrire dans {0}. Detail: {1}'
        # Remediation: la prochaine action concrete pour le technicien.
        # L exception brute reste dans le log; ceci va a l ecran.
        Remedy                  = @{
            TargetMissing       = "Introuvable a {0}. Corriger Applications['{1}'].Target dans WinContextDeploy.psd1, ou retirer l entree."
            TargetLaunchFailed  = "Impossible de demarrer {0}. Verifier Applications['{1}'].Target et Action dans WinContextDeploy.psd1."
            ProcessNotRunning   = 'Confirmer que {0} est installe et demarre, ou marquer l entree Optional dans WinContextDeploy.psd1.'
            WingetMissing       = 'App Installer (winget) n est pas provisionne sur cette image, donc les paquets ci-dessous n ont pas pu etre verifies. Les verifier a la main, ou installer App Installer depuis le Microsoft Store.'
            WingetPackageMissing = "winget ne liste pas {0} comme installe. Confirmer que l imagerie l a livre, ou corriger l identifiant de paquet dans Applications['{1}'].Target dans WinContextDeploy.psd1."
            WingetCheckFailed   = "winget n a pas pu verifier {0}. Lancer 'winget list --id {1} --exact' a la main pour voir pourquoi."
            WindowsUpdateFailed = 'Lancer Windows Update a la main et laisser passer la mise a jour en echec avant la remise du poste.'
            RebootPending       = 'Redemarrer le poste avant la remise; la mise a jour n est pas terminee tant qu il ne l est pas.'
            UnknownAction       = "Action '{0}' inconnue pour l etape '{1}'. Valides: {2}."
            RequiresAdmin       = 'Exige les droits Administrateur. Relancer en tant qu administrateur pour appliquer.'
            PowerCfgFailed      = 'powercfg a refuse la modification. Verifier qu aucune GPO ne fige le mode de gestion d alimentation.'
            RegistryGpo         = 'La politique de ce poste empeche la modification; elle doit passer par une GPO.'
            RegistryWriteFailed = 'La valeur de registre n a pas pu etre ecrite. Verifier que la cle n est pas detenue par un autre processus.'
            PrinterUnreachable  = "Serveur d impression {0} injoignable. Verifier la connexion, ou retirer Printers['{1}'] de WinContextDeploy.psd1."
            DiskUnhealthy       = 'Remplacer {0} avant la remise du poste.'
            DiskLowFreeSpace    = 'Liberer de l espace avant la remise du poste, ou augmenter Disk.MinFreeGB dans WinContextDeploy.psd1 si ce seuil ne convient pas au parc.'
            TpmNotReady         = 'Activer le TPM (PTT ou fTPM) dans le micrologiciel. Un TPM present mais pas pret doit generalement etre efface ou initialise depuis tpm.msc.'
            BitLockerOff        = 'Activer BitLocker sur le disque systeme avant la remise du poste, ou confirmer que la politique du parc l applique apres l inscription.'
            BitLockerInProgress = 'Le chiffrement est encore en cours. Le laisser terminer avant la remise du poste: le disque n est pas protege tant qu il ne l est pas.'
            ComputerNameInvalid = 'Le nom "{0}" n est pas un nom de poste utilisable. Relancer et saisir de 1 a 15 caracteres, lettres chiffres et traits d union seulement.'
            ComputerNameFailed  = 'Le renommage a ete refuse. Verifier que la run est elevee et qu aucune politique ne fige le nom du poste.'
            DomainJoinFailed    = 'La jonction au domaine a echoue. Verifier que le domaine est joignable, que le compte peut joindre des postes, et que Domain.OUPath dans WinContextDeploy.psd1 existe.'
            JoinCancelled       = 'La fenetre d identifiants a ete annulee. Relancer et fournir un compte de domaine, ou joindre le poste a la main.'
            BitLockerUnavailable = 'Cette edition ne prend pas en charge BitLocker. Confirmer que le poste doit etre remis avec cette edition, ou reimager avec une edition qui la prend en charge.'
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
foreach ($sharedFile in @('WcdHelpers.ps1', 'WcdDiagnostic.ps1')) {
    $sharedPath = Join-Path $scriptDir $sharedFile
    if (-not (Test-Path -LiteralPath $sharedPath)) {
        Write-Host ($T.FatalHelpersMissing -f $sharedFile, $scriptDir) -ForegroundColor Red
        exit 1
    }
    . $sharedPath
}

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
    Write-Host (' +{0}+' -f ('-' * ($T.OptionalToolBoxTitle.Length + 2))) -ForegroundColor Cyan
    Write-Host (' |  {0}  |' -f $T.OptionalToolBoxTitle) -ForegroundColor Cyan
    Write-Host (' +{0}+' -f ('-' * ($T.OptionalToolBoxTitle.Length + 2))) -ForegroundColor Cyan
    Write-Host ''
    foreach ($key in $options.Keys) {
        Write-Host ("    {0}. {1}" -f $key, $options[$key]) -ForegroundColor White
    }
    Write-Host ''
    Write-Host $T.OptionalToolCombineHint -ForegroundColor DarkGray

    while ($true) {
        Write-Host ''
        $answer = Read-Host $T.OptionalToolChoicePrompt
        if ([string]::IsNullOrWhiteSpace($answer)) {
            Write-Host $T.OptionalToolAtLeastOne -ForegroundColor Yellow
            continue
        }

        $parsed = ConvertTo-WcdOptionalToolSelection -RawInput $answer -ValidKeys @($options.Keys)
        if ($parsed.Count -eq 0) {
            Write-Host ($T.OptionalToolInvalidChoice -f ($options.Keys -join ', ')) -ForegroundColor Yellow
            continue
        }

        $selectedNames = @($parsed | ForEach-Object { $options[$_] })
        Write-Host ($T.OptionalToolSelection -f ($selectedNames -join ' + ')) -ForegroundColor Green
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

function Read-WcdComputerName {
    <#
    .SYNOPSIS
        Asks for a new computer name, re-asking until it is usable.

    .DESCRIPTION
        The typed name is a trust boundary, so it is checked here and rejected
        with a re-prompt rather than through a Rename-Computer failure at the end
        of the run. A name identical to the current one is not a fault: it is
        reported as nothing to do and the prompt closes.

    .PARAMETER CurrentName
        The machine's current name, so a rename that changes nothing is caught.

    .PARAMETER SerialNumber
        Serial shown beside the prompt - it is what the technician reads off the
        chassis label when deciding the name.

    .OUTPUTS
        [string] The accepted name, or empty when the technician typed nothing or
        typed the name the machine already has.

    .EXAMPLE
        Read-WcdComputerName -CurrentName $env:COMPUTERNAME -SerialNumber '5CG2141ABC'
    #>
    [CmdletBinding()]
    param(
        [string]$CurrentName = $env:COMPUTERNAME,

        [string]$SerialNumber = ''
    )

    if (-not [string]::IsNullOrWhiteSpace($SerialNumber)) {
        Write-Host ($T.PromptIdentitySerial -f $SerialNumber) -ForegroundColor DarkGray
    }
    Write-Host $T.PromptComputerNameDesc -ForegroundColor DarkGray

    while ($true) {
        $typed = (Read-Host $T.PromptComputerName)
        if ($null -eq $typed) { return '' }

        $typed = $typed.Trim()
        if ([string]::IsNullOrWhiteSpace($typed)) { return '' }

        $reason = Test-WcdComputerName -Name $typed -CurrentName $CurrentName

        # Nothing to do is an answer, not a rejection: stop asking.
        if ($reason -eq 'Unchanged') {
            Write-Host $T.ComputerNameRejected.Unchanged -ForegroundColor Yellow
            return ''
        }

        if ($reason -eq '') { return $typed }

        Write-Host $T.ComputerNameRejected[$reason] -ForegroundColor Yellow
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

    .PARAMETER SelectedNewComputerName
        New computer name supplied on the command line, or empty to prompt.

    .PARAMETER SelectedJoinDomain
        Join the manifest's domain without asking whether to.

    .PARAMETER DomainTarget
        The domain from the manifest, from Get-WcdDomainTarget. Nothing there
        means no domain to offer, and the prompt drops the option.

    .PARAMETER DisablePrompt
        Ask nothing: use what was supplied, and the defaults for the rest.

    .OUTPUTS
        [pscustomobject] with Language, FormFactor, Environment, OpenApps,
        OptionalTools, NewComputerName and JoinDomain.

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
        [string]$SelectedNewComputerName,
        [switch]$SelectedJoinDomain,
        [pscustomobject]$DomainTarget,
        [switch]$DisablePrompt
    )

    $languageResult = $SelectedLanguage
    $formFactorResult = $SelectedFormFactor
    $environmentResult = $SelectedEnvironment
    $openAppsResult = $SelectedOpenApps
    $optionalToolResult = $SelectedOptionalTools
    $newNameResult = $SelectedNewComputerName
    $joinResult = [bool]$SelectedJoinDomain

    $optionalToolNames = @()

    if (-not $DisablePrompt) {
        if (-not $languageResult) {
            Write-Host ''
            $languageResult = Read-WcdChoice -Prompt $T.PromptLanguage -Choices ([ordered]@{ FR = 'fr-CA'; EN = 'en-US' }) -DefaultKey 'FR' `
                -Description @($T.PromptLanguageDesc)
        }

        if (-not $formFactorResult) {
            Write-Host ''
            $formFactorResult = Read-WcdChoice -Prompt $T.PromptFormFactor -Choices ([ordered]@{ $T.KeyLaptop = 'Laptop'; $T.KeyDesktop = 'Desktop' }) -DefaultKey $T.KeyLaptop `
                -Description @($T.PromptFormFactorDesc1, $T.PromptFormFactorDesc2)
        }

        if (-not $environmentResult) {
            Write-Host ''
            $environmentResult = Read-WcdChoice -Prompt $T.PromptEnvironment -Choices ([ordered]@{ $T.KeyWorkstation = 'Workstation'; $T.KeyVdi = 'Vdi' }) -DefaultKey $T.KeyWorkstation `
                -Description @($T.PromptEnvironmentDesc1, $T.PromptEnvironmentDesc2)
        }

        $environmentLabel = Get-WcdChoiceLabel -Value $environmentResult -Labels $T.Labels

        if (-not $openAppsResult) {
            Write-Host ''
            $openAppsResult = Read-WcdChoice -Prompt ($T.PromptOpenApps -f $environmentLabel) -Choices ([ordered]@{ $T.KeyYes = 'Yes'; $T.KeyNo = 'No' }) -DefaultKey $T.KeyYes `
                -Description @($T.PromptOpenAppsDesc1, $T.PromptOpenAppsDesc2)
        }

        # Machine identity, offered only when there is something left to offer.
        # -NewComputerName or -JoinDomain on the command line answers it already.
        if (-not $newNameResult -and -not $joinResult) {
            $serialNumber = Get-WcdMachineSerial
            $currentName = $env:COMPUTERNAME

            $identityChoices = [ordered]@{ $T.KeyNeither = 'Neither'; $T.KeyComputerName = 'ComputerName' }
            $identityDescription = @(
                ($T.PromptIdentitySerial -f $serialNumber),
                $T.PromptIdentityDesc1,
                $T.PromptIdentityDesc2
            )
            if ($null -ne $DomainTarget) {
                $identityChoices[$T.KeyDomain] = 'Domain'
                $identityChoices[$T.KeyBoth] = 'Both'
                $identityDescription += ($T.PromptIdentityDomain -f $DomainTarget.Name)
            }

            Write-Host ''
            $identityResult = Read-WcdChoice -Prompt $T.PromptIdentity -Choices $identityChoices -DefaultKey $T.KeyNeither `
                -Description $identityDescription

            if (@('ComputerName', 'Both') -contains $identityResult) {
                $newNameResult = Read-WcdComputerName -CurrentName $currentName -SerialNumber $serialNumber
            }
            if (@('Domain', 'Both') -contains $identityResult) {
                $joinResult = $true
            }
        }

        if (-not $optionalToolResult -and @($OptionalToolCandidates).Count -gt 0) {
            Write-Host ''
            $optionalToolAnswer = Read-WcdChoice -Prompt $T.PromptOptionalTool -Choices ([ordered]@{ $T.KeyYes = 'Yes'; $T.KeyNo = 'No' }) -DefaultKey $T.KeyNo `
                -Description @($T.PromptOptionalToolDesc1, $T.PromptOptionalToolDesc2)
            if ($optionalToolAnswer -eq 'Yes') {
                $optionalToolNames = Read-WcdOptionalToolChoice -Candidates $OptionalToolCandidates
            } else {
                $optionalToolNames = @()
            }
        }
    }

    # -OptionalTools accepts a comma-separated list of Application Target names.
    if ($optionalToolNames.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($optionalToolResult)) {
        $optionalToolNames = @($optionalToolResult -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }

    if (-not $languageResult)  { $languageResult  = 'fr-CA' }
    if (-not $formFactorResult)    { $formFactorResult    = 'Laptop' }
    if (-not $environmentResult)     { $environmentResult     = 'Workstation' }
    if (-not $openAppsResult)  { $openAppsResult  = 'Yes' }


    # A domain the manifest does not declare cannot be joined, whatever was
    # asked for on the command line.
    if ($null -eq $DomainTarget) { $joinResult = $false }

    return [pscustomobject]@{
        Language        = $languageResult
        FormFactor      = $formFactorResult
        Environment     = $environmentResult
        OpenApps        = ($openAppsResult -eq 'Yes')
        OptionalTools   = $optionalToolNames
        NewComputerName = $newNameResult
        JoinDomain      = $joinResult
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

# No Domain.Name in the manifest means no domain option in the prompt.
$domainTarget = Get-WcdDomainTarget -Config $script:WcdConfig

$executionOptions = Resolve-WcdExecutionOptions `
    -SelectedLanguage $Language `
    -SelectedFormFactor $FormFactor `
    -SelectedEnvironment $Environment `
    -SelectedOpenApps $openAppsValue `
    -SelectedOptionalTools $OptionalTools `
    -OptionalToolCandidates $optionalToolCandidates `
    -SelectedNewComputerName $NewComputerName `
    -SelectedJoinDomain:$JoinDomain `
    -DomainTarget $domainTarget `
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

# --- Discover the Modules ----------------------------------------------------
# Every src/Config-*.ps1 declares itself with one descriptor function. Nothing
# about a Module is registered here: not its run order, not its Steps, not its
# checklist rows. Adding a Module is adding a file.
#
# A Module that cannot be loaded is reported and the run continues - the rest of
# the checklist still helps the technician. A Module that loads but does not
# declare itself is a repo bug, not a machine condition, so it stops the run
# loudly rather than vanishing from the checklist.
$descriptors = @()
$moduleStatus = @()

foreach ($moduleFile in @(Get-ChildItem -Path (Join-Path $scriptDir 'Config-*.ps1') | Sort-Object Name)) {
    try {
        . $moduleFile.FullName
    } catch {
        $msg = ($T.ModuleLoadFail -f $moduleFile.BaseName, $_.Exception.Message)
        Write-Host "  [ERREUR] $msg" -ForegroundColor Red
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message $msg
        $moduleStatus += [pscustomobject]@{
            Module         = $moduleFile.BaseName
            Status         = $T.StatusError
            Steps          = 0
            Failures       = 1
            Warnings       = 0
            Detail         = $msg
        }
        continue
    }

    $descriptorFunction = 'Get-Wcd{0}Descriptor' -f ($moduleFile.BaseName -replace '^Config-', '')
    if (-not (Get-Command -Name $descriptorFunction -ErrorAction SilentlyContinue)) {
        throw ('{0} does not define {1}. See Test-WcdModuleDescriptor in WcdHelpers.ps1.' -f $moduleFile.Name, $descriptorFunction)
    }

    $descriptor = & $descriptorFunction -ExecutionOptions $executionOptions -Config $script:WcdConfig -Translations $T
    $problems = @(Test-WcdModuleDescriptor -Descriptor $descriptor -ExpectedName $moduleFile.BaseName)
    if ($problems.Count -gt 0) {
        throw ('{0} returned an invalid descriptor: {1}' -f $descriptorFunction, ($problems -join ' '))
    }

    $descriptors += $descriptor
}

$descriptors = @($descriptors | Sort-Object { [int]$_.Order })

$stepLabels = Get-WcdTechnicalStepLabels -Descriptors $descriptors
$moduleStepPlan = Get-WcdModuleProgressPlan -Descriptors $descriptors
$allResults = @()

# Everything a Module's Invoke block is allowed to need, so no Module reaches
# back into this script's variables.
$moduleContext = [pscustomobject]@{
    ExecutionOptions = $executionOptions
    Config           = $script:WcdConfig
    Translations     = $T
    DomainTarget     = $domainTarget
    Elevated         = $isElevated
    LogPath          = $resolvedLogPath
    ProgressCallback = $null
}

foreach ($descriptor in $descriptors) {
    $modName = [string]$descriptor.Name

    # Nothing planned means nothing to do this run - no printer in the manifest,
    # no identity change asked for. Skip the Module rather than report an empty
    # run of it. Its checklist rows are still emitted.
    if (@($moduleStepPlan[$modName]).Count -eq 0) {
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
    $moduleContext.ProgressCallback = $progressCallback

    try {
        $modResults = @(& $descriptor.Invoke $moduleContext)
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
        Steps          = $totalSteps
        Failures       = $failedSteps
        Warnings       = $warningSteps
        Detail         = $detail
    }
}

$diagnosticResults = @($allResults)
$checklistEntries = Get-WcdFinalChecklistEntries -AllResults $diagnosticResults -Descriptors $descriptors -StepLabels $stepLabels -Config $script:WcdConfig
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
