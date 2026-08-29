<#
.SYNOPSIS
    Fonctions utilitaires partagees par tous les modules de configuration.
    A charger via dot-source avant tout autre module du projet.

.DESCRIPTION
    Fournit les primitives communes:
    - Journalisation     : Resolve-WcdLogPath, Initialize-WcdLog, Write-WcdLog
    - Progression ASCII  : New-WcdProgressState, Update-WcdProgressState,
                           Write-WcdProgressSnapshot, Invoke-WcdProgressCallback
    - Registre Windows   : Set-WcdRegistryValue
    - Utilitaires systeme: Invoke-WcdPowerCfg, Import-WcdConfig,
                           Resolve-WcdDynamicPath
    - Diagnostic final   : Get-WcdHistoryBlock, Export-WcdHistoryLog

.NOTES
    Chargement: . (Join-Path $PSScriptRoot 'WcdHelpers.ps1')
    Aucun parametre d'entree — ce fichier expose uniquement des fonctions.
#>

function Resolve-WcdLogPath {
    [CmdletBinding()]
    param(
        [string]$CandidatePath
    )

    if (-not [string]::IsNullOrWhiteSpace($CandidatePath)) {
        return $CandidatePath
    }

    $basePath = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($basePath)) {
        $scriptPath = $MyInvocation.MyCommand.Path
        if (-not [string]::IsNullOrWhiteSpace($scriptPath)) {
            $basePath = Split-Path -Path $scriptPath -Parent
        }
    }

    if ([string]::IsNullOrWhiteSpace($basePath)) {
        $basePath = (Get-Location).Path
    }

    return (Join-Path $basePath 'log.txt')
}

function Initialize-WcdLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $parent = Split-Path -Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -Path $parent -ItemType Directory -Force | Out-Null
    }

    $utf8Encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, [string]::Empty, $utf8Encoding)
}

function Write-WcdLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO', 'ERROR')]
        [string]$Level = 'INFO',

        [Parameter(Mandatory)]
        [string]$Path
    )

    $parent = Split-Path -Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -Path $parent -ItemType Directory -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType File -Force | Out-Null
    }

    $line = '{0} [{1}] {2}' -f ([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss')), $Level, $Message
    Add-Content -Path $Path -Value $line -Encoding UTF8
}

function Get-WcdResultSeverity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Result
    )

    $severityProperty = $Result.PSObject.Properties['Severity']
    if ($null -ne $severityProperty -and -not [string]::IsNullOrWhiteSpace([string]$severityProperty.Value)) {
        return ([string]$severityProperty.Value).ToUpperInvariant()
    }

    if ($null -ne $Result.PSObject.Properties['Success'] -and -not $Result.Success) {
        return 'ERROR'
    }

    return 'INFO'
}

function Get-WcdTechnicalStepLabels {
    [CmdletBinding()]
    param(
        [hashtable]$Config
    )

    $labels = @{
        'ScreenTimeoutBattery'   = 'Screen timeout on battery'
        'ScreenTimeoutAc'        = 'Screen timeout on AC'
        'LidActionBatteryNone'   = 'Lid close on battery: do nothing'
        'LidActionAcNone'        = 'Lid close on AC: do nothing'
        'SetActiveSchemeCurrent' = 'Active power scheme'
        'DecimalAndCurrency'     = 'Decimal and currency'
        'TaskbarAlignLeft'       = 'Taskbar aligned left'
        'DisableTaskView'        = 'Task view disabled'
        'DisplayLanguage'        = 'Display language'
        'KeyboardLayout'         = 'Keyboard layout'
        'ApplicationsSkip'       = 'Applications skipped'
        'DeviceManagerStatus'    = 'Device Manager'
        'NetworkAdapterStatus'   = 'Network adapters'
        'PrinterAdd'             = 'Printers'
        'PrinterSkip'            = 'Printers skipped'
    }

    # Application step labels come from the manifest, so a target added there
    # names itself everywhere without touching this file.
    if ($null -ne $Config -and $null -ne $Config.Applications) {
        foreach ($entry in @($Config.Applications)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$entry.Step)) {
                $labels[[string]$entry.Step] = [string]$entry.Name
            }
        }
    }

    return $labels
}

function Get-WcdModuleProgressPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$ExecutionOptions,

        [hashtable]$Config
    )

    $applicationSteps = if ($ExecutionOptions.OpenApps) {
        @(Get-WcdApplicationTarget -Config $Config `
            -Environment $ExecutionOptions.Environment `
            -FormFactor $ExecutionOptions.FormFactor `
            -OptionalTools $ExecutionOptions.OptionalTools |
            ForEach-Object { [string]$_.Step })
    } else {
        @('ApplicationsSkip')
    }
    if ($applicationSteps.Count -eq 0) { $applicationSteps = @('ApplicationsSkip') }

    return @{
        'Config-Power' = if ($ExecutionOptions.FormFactor -eq 'Laptop') {
            @(
                'ScreenTimeoutBattery',
                'ScreenTimeoutAc',
                'LidActionAcNone',
                'LidActionBatteryNone',
                'SetActiveSchemeCurrent'
            )
        } else {
            @(
                'ScreenTimeoutAc',
                'SetActiveSchemeCurrent'
            )
        }
        'Config-Decimal' = @('DecimalAndCurrency')
        'Config-TaskbarLeft' = @('TaskbarAlignLeft', 'DisableTaskView')
        'Config-Language' = @('DisplayLanguage', 'KeyboardLayout')
        'Config-Applications' = $applicationSteps
        'Config-DeviceManager' = @('DeviceManagerStatus')
    }
}

function Get-WcdDiagnosticStyle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('running', 'success', 'warning', 'error', 'manual', 'na')]
        [string]$Kind
    )

    $tbl = if (Get-Variable -Name 'T' -Scope Script -ErrorAction SilentlyContinue) { $script:T } else { $null }
    switch ($Kind) {
        'running' {
            return [pscustomobject]@{ Icon = '[>]'; Color = 'Cyan'; Status = if ($null -ne $tbl) { $tbl.DiagStyleInProgress } else { 'EN COURS' } }
        }
        'success' {
            return [pscustomobject]@{ Icon = '[x]'; Color = 'Green'; Status = if ($null -ne $tbl) { $tbl.DiagStyleOk } else { 'OK' } }
        }
        'warning' {
            return [pscustomobject]@{ Icon = '[!]'; Color = 'DarkYellow'; Status = if ($null -ne $tbl) { $tbl.DiagStyleWarning } else { 'WARNING' } }
        }
        'error' {
            return [pscustomobject]@{ Icon = '[!]'; Color = 'Red'; Status = if ($null -ne $tbl) { $tbl.DiagStyleError } else { 'ERREUR' } }
        }
        'manual' {
            return [pscustomobject]@{ Icon = '[-]'; Color = 'DarkYellow'; Status = if ($null -ne $tbl) { $tbl.DiagStyleManual } else { 'MANUEL' } }
        }
        default {
            return [pscustomobject]@{ Icon = '[-]'; Color = 'Yellow'; Status = if ($null -ne $tbl) { $tbl.DiagStyleNA } else { 'N/A' } }
        }
    }
}

function Format-WcdElapsedMilliseconds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [datetime]$StartedAt
    )

    $elapsed = (Get-Date) - $StartedAt
    return ('{0:N0}ms' -f $elapsed.TotalMilliseconds)
}

function Format-WcdAsciiProgressBar {
    [CmdletBinding()]
    param(
        [int]$CompletedSteps,
        [int]$TotalSteps,
        [int]$Width = 10
    )

    $safeTotal = [Math]::Max(1, $TotalSteps)
    $safeCompleted = [Math]::Min([Math]::Max(0, $CompletedSteps), $safeTotal)
    $filled = [Math]::Round(($safeCompleted / $safeTotal) * $Width)
    $filled = [Math]::Min([Math]::Max(0, $filled), $Width)
    $empty = $Width - $filled
    $percent = [Math]::Round(($safeCompleted / $safeTotal) * 100)

    return ('[{0}{1}] {2}%' -f ('#' * $filled), ('-' * $empty), $percent)
}

function Test-WcdRawUiAvailability {
    [CmdletBinding()]
    param()

    try {
        $null = $Host.UI.RawUI
        return $true
    } catch {
        return $false
    }
}

function New-WcdProgressState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName,

        [string[]]$StepKeys = @(),

        [hashtable]$StepLabels
    )

    $stepLookup = @{}
    for ($index = 0; $index -lt @($StepKeys).Count; $index++) {
        $stepLookup[$StepKeys[$index]] = $index + 1
    }

    $state = [ordered]@{
        ModuleName     = $ModuleName
        StepKeys       = @($StepKeys)
        StepLookup     = $stepLookup
        StepLabels     = if ($null -ne $StepLabels) { $StepLabels } else { @{} }
        TotalSteps     = [Math]::Max(1, @($StepKeys).Count)
        CompletedSteps = 0
        StartedAt      = Get-Date
        CurrentStepKey = ''
        RenderMode     = if (Test-WcdRawUiAvailability) { 'InPlace' } else { 'Plain' }
    }

    return $state
}

function Write-WcdProgressSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$State,

        [Parameter(Mandatory)]
        [string]$CurrentStepLabel,

        [Parameter(Mandatory)]
        [string]$PhaseText,

        [ValidateSet('running', 'success', 'warning', 'error')]
        [string]$Kind = 'running'
    )

    $bar = Format-WcdAsciiProgressBar -CompletedSteps $State.CompletedSteps -TotalSteps $State.TotalSteps
    $elapsed = Format-WcdElapsedMilliseconds -StartedAt $State.StartedAt
    $line = '{0} : {1}  {2}' -f $State.ModuleName, $bar, $elapsed

    if ($State.RenderMode -eq 'InPlace') {
        Write-Host ("`r" + $line.PadRight(70)) -NoNewline -ForegroundColor Cyan
        return
    }

    Write-Host $line -ForegroundColor Cyan
}

function Update-WcdProgressState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$State,

        [Parameter(Mandatory)]
        [string]$StepKey,

        [Parameter(Mandatory)]
        [ValidateSet('Start', 'Finish')]
        [string]$Event,

        [ValidateSet('success', 'warning', 'error')]
        [string]$Kind = 'success'
    )

    $currentStepLabel = if ($State.StepLabels.ContainsKey($StepKey)) { $State.StepLabels[$StepKey] } else { $StepKey }
    $State.CurrentStepKey = $StepKey

    if ($Event -eq 'Finish') {
        if ($State.StepLookup.ContainsKey($StepKey)) {
            $State.CompletedSteps = [Math]::Max($State.CompletedSteps, [int]$State.StepLookup[$StepKey])
        } else {
            $State.CompletedSteps = [Math]::Min($State.CompletedSteps + 1, $State.TotalSteps)
        }

        $phaseText = switch ($Kind) {
            'warning' { 'Etape terminee avec avertissement' }
            'error' { 'Etape terminee en erreur' }
            default { 'Etape terminee' }
        }

        Write-WcdProgressSnapshot -State $State -CurrentStepLabel $currentStepLabel -PhaseText $phaseText -Kind $Kind
        return
    }

    Write-WcdProgressSnapshot -State $State -CurrentStepLabel $currentStepLabel -PhaseText 'Execution en cours' -Kind 'running'
}

function Invoke-WcdProgressCallback {
    [CmdletBinding()]
    param(
        [scriptblock]$ProgressCallback,

        [Parameter(Mandatory)]
        [string]$ModuleName,

        [Parameter(Mandatory)]
        [string]$StepKey,

        [Parameter(Mandatory)]
        [ValidateSet('Start', 'Finish')]
        [string]$Event,

        [ValidateSet('success', 'warning', 'error')]
        [string]$Kind = 'success'
    )

    if ($null -eq $ProgressCallback) {
        return
    }

    & $ProgressCallback ([pscustomobject]@{
        Module = $ModuleName
        Step   = $StepKey
        Event  = $Event
        Kind   = $Kind
    })
}

function Get-WcdHistoryBlock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LocalLogPath,

        [string[]]$DiagnosticLines = @()
    )

    $pcName = $env:COMPUTERNAME
    $serialNumber = 'Inconnu'
    $computerModel = 'Inconnu'
    try {
        $osInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        if ($null -ne $osInfo -and -not [string]::IsNullOrWhiteSpace($osInfo.CSName)) {
            $pcName = $osInfo.CSName
        }
    } catch {
    }

    try {
        $biosInfo = Get-CimInstance Win32_Bios -ErrorAction Stop
        if ($null -ne $biosInfo -and -not [string]::IsNullOrWhiteSpace($biosInfo.SerialNumber)) {
            $serialNumber = $biosInfo.SerialNumber.Trim()
        }
    } catch {
    }

    try {
        $computerInfo = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        if ($null -ne $computerInfo -and -not [string]::IsNullOrWhiteSpace($computerInfo.Model)) {
            $computerModel = $computerInfo.Model.Trim()
        }
    } catch {
    }

    $userName = $env:USERNAME
    $userFullName = if (-not [string]::IsNullOrWhiteSpace($env:USERDOMAIN)) {
        '{0}\{1}' -f $env:USERDOMAIN, $env:USERNAME
    } else {
        $env:USERNAME
    }

    $logContent = ''
    if (Test-Path -LiteralPath $LocalLogPath) {
        $logContent = Get-Content -Path $LocalLogPath -Raw -ErrorAction SilentlyContinue
    }

    $dateTimeText = [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss')

    $lines = @(
        '+============================================================+'
        ('| PCname       : {0}' -f $pcName)
        ('| SerialNumber : {0}' -f $serialNumber)
        ('| Model        : {0}' -f $computerModel)
        ('| User         : {0}' -f $userFullName)
        ('| Username     : {0}' -f $userName)
        ('| DateTime     : {0}' -f $dateTimeText)
        '+------------------------------------------------------------+'
        '| SECTION LOG                                               |'
        '+------------------------------------------------------------+'
    )

    if ([string]::IsNullOrWhiteSpace($logContent)) {
        $lines += '| Aucun contenu de log local.'
    } else {
        $lines += @($logContent.TrimEnd("`r", "`n") -split "`r?`n") | ForEach-Object { '| ' + $_ }
    }

    if (@($DiagnosticLines).Count -gt 0) {
        $lines += '+------------------------------------------------------------+'
        $lines += '| SECTION DIAGNOSTIC FINAL                                  |'
        $lines += '+------------------------------------------------------------+'
        $lines += @($DiagnosticLines | ForEach-Object { '| ' + $_ })
    }

    $lines += '+============================================================+'
    return ($lines -join [Environment]::NewLine)
}

function Export-WcdHistoryLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LocalLogPath,

        [Parameter(Mandatory)]
        [string]$HistoryLogPath,

        [string[]]$DiagnosticLines = @()
    )

    $parent = Split-Path -Path $HistoryLogPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -Path $parent -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    $utf8Encoding = New-Object System.Text.UTF8Encoding($false)
    $block = Get-WcdHistoryBlock -LocalLogPath $LocalLogPath -DiagnosticLines $DiagnosticLines
    $prefix = if (Test-Path -LiteralPath $HistoryLogPath) { [Environment]::NewLine } else { [string]::Empty }
    $contentToAppend = '{0}{1}{2}' -f $prefix, $block, [Environment]::NewLine

    [System.IO.File]::AppendAllText($HistoryLogPath, $contentToAppend, $utf8Encoding)
    return $HistoryLogPath
}

function Invoke-WcdPowerCfg {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments)]
        [string[]]$Arguments
    )

    & powercfg @Arguments | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "powercfg a retourne le code $LASTEXITCODE."
    }
}

function Open-WcdUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url
    )

    # Start-Process on a URL hands it to the machine's default browser.
    Start-Process $Url -ErrorAction Stop
}

function Get-WcdApplicationTarget {
    [CmdletBinding()]
    param(
        [hashtable]$Config,

        [string]$Environment = 'Workstation',

        [string]$FormFactor = 'Laptop',

        # Names of Prompt entries the technician selected. Prompt entries not
        # named here are left out entirely.
        [string[]]$OptionalTools = @()
    )

    if ($null -eq $Config -or $null -eq $Config.Applications) { return @() }

    return @($Config.Applications | Where-Object {
        $envOk    = [string]::IsNullOrWhiteSpace([string]$_.Environment) -or $_.Environment -eq $Environment
        $formOk   = [string]::IsNullOrWhiteSpace([string]$_.FormFactor)  -or $_.FormFactor  -eq $FormFactor
        $promptOk = -not $_.Prompt -or (@($OptionalTools) -contains [string]$_.Name)
        $envOk -and $formOk -and $promptOk
    })
}

function Get-WcdPromptedApplicationTarget {
    [CmdletBinding()]
    param(
        [hashtable]$Config,

        [string]$Environment = 'Workstation'
    )

    if ($null -eq $Config -or $null -eq $Config.Applications) { return @() }

    return @($Config.Applications | Where-Object {
        $_.Prompt -and ([string]::IsNullOrWhiteSpace([string]$_.Environment) -or $_.Environment -eq $Environment)
    })
}

function Get-WcdChoiceLabel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Value,

        [hashtable]$Labels
    )

    # Choice values are canonical English so the code reads the same in every
    # language; only what the technician sees is localized.
    if ($null -ne $Labels -and $Labels.ContainsKey($Value)) { return $Labels[$Value] }
    return $Value
}

function Import-WcdConfig {
    [CmdletBinding()]
    param(
        [string]$ConfigPath
    )

    if (-not [string]::IsNullOrWhiteSpace($ConfigPath) -and (Test-Path -LiteralPath $ConfigPath)) {
        return Import-PowerShellDataFile -Path $ConfigPath
    }

    # Recherche automatique: dossier parent du script (racine du projet)
    $searchBases = @()
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        $searchBases += Split-Path -Path $PSScriptRoot -Parent
        $searchBases += $PSScriptRoot
    }
    $scriptPath = $MyInvocation.MyCommand.Path
    if (-not [string]::IsNullOrWhiteSpace($scriptPath)) {
        $searchBases += Split-Path -Path (Split-Path -Path $scriptPath -Parent) -Parent
    }
    $searchBases += (Get-Location).Path

    foreach ($base in $searchBases) {
        if ([string]::IsNullOrWhiteSpace($base)) { continue }
        $candidate = Join-Path $base 'WinContextDeploy.psd1'
        if (Test-Path -LiteralPath $candidate) {
            return Import-PowerShellDataFile -Path $candidate
        }
    }

    throw 'WinContextDeploy.psd1 introuvable. Fournir le chemin via -ConfigPath.'
}

function Resolve-WcdDynamicPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BasePath,

        [Parameter(Mandatory)]
        [string]$Pattern,

        [Parameter(Mandatory)]
        [string]$ExeName
    )

    if (-not (Test-Path -LiteralPath $BasePath)) {
        return $null
    }

    $folder = Get-ChildItem -Path $BasePath -Directory -Filter $Pattern -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        Select-Object -First 1

    if ($null -eq $folder) {
        return $null
    }

    $exePath = Join-Path $folder.FullName $ExeName
    if (Test-Path -LiteralPath $exePath) {
        return $exePath
    }

    return $null
}

function Set-WcdRegistryValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [AllowNull()]
        $Value,

        [ValidateSet('String', 'DWord')]
        [string]$PropertyType = 'String'
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
    }

    $existing = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $existing) {
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $PropertyType -Force -ErrorAction Stop | Out-Null
        return
    }

    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Force -ErrorAction Stop
}
