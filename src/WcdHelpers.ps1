# WcdHelpers.ps1 - shared helpers for every configuration Module.
# Dot-source this file before any other module in the project:
#   . (Join-Path $PSScriptRoot 'WcdHelpers.ps1')
#
# Groups: logging, elevation, ASCII progress, registry, system utilities,
# manifest queries, and the final Diagnostic. Per-function documentation lives
# on the functions themselves - Get-Help <name> for any of them.

function Resolve-WcdLogPath {
    <#
    .SYNOPSIS
        Returns the log file path to use for this run.

    .DESCRIPTION
        Returns CandidatePath unchanged when the caller supplied one. Otherwise
        falls back to log.txt beside this script, so every module writes to the
        same file whether or not -LogPath was passed down.

    .PARAMETER CandidatePath
        Path supplied by the caller. Empty or whitespace means "decide for me".

    .OUTPUTS
        [string] Full path to the log file.

    .EXAMPLE
        $log = Resolve-WcdLogPath -CandidatePath $LogPath
    #>
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
    <#
    .SYNOPSIS
        Truncates the run log so each run starts from an empty file.

    .DESCRIPTION
        Creates the parent directory when missing and writes an empty UTF-8
        file (no byte order mark) at Path. The history log, if any, is appended
        to separately and is never touched here.

    .PARAMETER Path
        Full path to the run log file.

    .OUTPUTS
        None.

    .EXAMPLE
        Initialize-WcdLog -Path 'C:\temp\log.txt'
    #>
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
    <#
    .SYNOPSIS
        Appends one timestamped line to the run log.

    .DESCRIPTION
        Creates the file and its parent directory when missing, then appends
        "<timestamp> [<level>] <message>". The log keeps the raw exception text
        of a failure; the remediation sentence is what goes on screen.

    .PARAMETER Message
        Text to log.

    .PARAMETER Level
        'INFO', 'WARNING' or 'ERROR'. Defaults to 'INFO'.

    .PARAMETER Path
        Full path to the log file.

    .OUTPUTS
        None.

    .EXAMPLE
        Write-WcdLog -Path $log -Level 'ERROR' -Message 'powercfg returned 1.'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO', 'WARNING', 'ERROR')]
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

function Test-WcdElevated {
    <#
    .SYNOPSIS
        Reports whether the current process holds Administrator rights.

    .DESCRIPTION
        Only the power steps need elevation. A run without it still completes;
        those steps report as actionable warnings instead of failures.
        Returns $false on any platform where the Windows principal cannot be
        read, which is the safe answer: nothing is attempted that needs admin.

    .OUTPUTS
        [bool] $true when the run is elevated.

    .EXAMPLE
        if (-not (Test-WcdElevated)) { 'Relaunch as Administrator to apply power settings.' }
    #>
    [CmdletBinding()]
    param()

    try {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Test-WcdUncPath {
    <#
    .SYNOPSIS
        Reports whether a path points at a UNC network share.

    .DESCRIPTION
        UAC starts the elevated process in a different logon session, which
        drops mapped network drives. A history log on \\server\share therefore
        stops being writable after elevation, and the technician is warned
        before the relaunch. USB drive letters are physical and do survive.

    .PARAMETER Path
        Path to inspect. Empty or whitespace returns $false.

    .OUTPUTS
        [bool] $true for \\server\share and for a mapped drive letter whose
        target is a network share.

    .EXAMPLE
        Test-WcdUncPath -Path '\\fileserver\logs\history.txt'   # True
    #>
    [CmdletBinding()]
    param(
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if ($Path -match '^(\\\\|//)') { return $true }

    # A mapped drive letter is the other way a UNC target hides in a path.
    if ($Path -match '^([A-Za-z]):') {
        $drive = Get-PSDrive -Name $Matches[1] -PSProvider FileSystem -ErrorAction SilentlyContinue
        if ($null -ne $drive -and -not [string]::IsNullOrWhiteSpace([string]$drive.DisplayRoot)) {
            return ([string]$drive.DisplayRoot -match '^(\\\\|//)')
        }
    }

    return $false
}

function Get-WcdRelaunchArgument {
    <#
    .SYNOPSIS
        Builds the powershell.exe argument list used to relaunch the run elevated.

    .DESCRIPTION
        An elevated process starts in C:\Windows\System32, so every path is
        re-serialized as absolute before the relaunch or the second run cannot
        find its own files. The internal -Elevated switch is always appended so
        a failed elevation can never spawn a third process.

    .PARAMETER ScriptPath
        Path to Invoke-WcdConfiguration.ps1, made absolute.

    .PARAMETER BoundParameters
        The entry point's $PSBoundParameters. Switches are emitted bare, path
        parameters are made absolute, everything else is passed through.

    .PARAMETER WorkingDirectory
        Directory relative paths are resolved against. Defaults to the current
        location.

    .OUTPUTS
        [string[]] Arguments for powershell.exe, starting with -NoProfile.

    .EXAMPLE
        $argv = Get-WcdRelaunchArgument -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
        Start-Process powershell.exe -Verb RunAs -ArgumentList $argv
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath,

        [System.Collections.IDictionary]$BoundParameters = @{},

        [string]$WorkingDirectory
    )

    if ([string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $WorkingDirectory = (Get-Location).Path
    }

    # Parameters whose value is a filesystem path and must survive the jump to
    # System32 as an absolute path.
    $pathParameters = @('LogPath', 'ConfigPath', 'HistoryLogPath', 'LocalProjectRoot', 'UsbSourceRoot', 'ReportPath')

    $resolveAbsolute = {
        param([string]$Candidate)

        if ([string]::IsNullOrWhiteSpace($Candidate)) { return $Candidate }
        if ([System.IO.Path]::IsPathRooted($Candidate)) {
            return [System.IO.Path]::GetFullPath($Candidate)
        }
        return [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($WorkingDirectory, $Candidate))
    }

    $arguments = @(
        '-NoProfile'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        (& $resolveAbsolute $ScriptPath)
    )

    foreach ($name in @($BoundParameters.Keys | Sort-Object)) {
        if ($name -eq 'Elevated') { continue }
        $value = $BoundParameters[$name]

        if ($value -is [System.Management.Automation.SwitchParameter]) {
            if ($value.IsPresent) { $arguments += ('-{0}' -f $name) }
            continue
        }

        if ($value -is [bool]) {
            if ($value) { $arguments += ('-{0}' -f $name) }
            continue
        }

        if ($null -eq $value) { continue }

        $text = [string]$value
        if ($pathParameters -contains $name) {
            $text = & $resolveAbsolute $text
        }

        $arguments += ('-{0}' -f $name)
        $arguments += $text
    }

    # Guard switch: the elevated run must never try to elevate again.
    $arguments += '-Elevated'

    return $arguments
}

function Get-WcdResultSeverity {
    <#
    .SYNOPSIS
        Returns the severity of a Step Result.

    .DESCRIPTION
        Reads the Result's Severity property when present. Older results carry
        only Success, so a $false Success is read as 'ERROR' and anything else
        as 'INFO'.

    .PARAMETER Result
        A Step Result object.

    .OUTPUTS
        [string] 'ERROR', 'WARNING' or 'INFO'.

    .EXAMPLE
        Get-WcdResultSeverity -Result ([pscustomobject]@{ Step = 'X'; Success = $false })   # ERROR
    #>
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

function Get-WcdPrinterStepKey {
    <#
    .SYNOPSIS
        Returns the stable Step key for one printer queue.

    .DESCRIPTION
        Printers come from the manifest and have no hand-written Step ids, so
        the key is derived from the queue name. The progress plan, the step
        labels and Config-Printer all call this, which is what keeps them
        agreeing on one key per printer.

    .PARAMETER Name
        Printer queue name from the manifest's Printers array.

    .OUTPUTS
        [string] e.g. 'PrinterFloor4Colour'.

    .EXAMPLE
        Get-WcdPrinterStepKey -Name 'Floor-4-Colour'   # PrinterFloor4Colour
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Name
    )

    $safe = ($Name -replace '[^A-Za-z0-9]', '')
    if ([string]::IsNullOrWhiteSpace($safe)) { $safe = 'Queue' }
    return ('Printer{0}' -f $safe)
}

function Get-WcdTechnicalStepLabels {
    <#
    .SYNOPSIS
        Maps every Step key to the label shown in the diagnostic.

    .DESCRIPTION
        OS steps carry built-in labels. Application and printer steps name
        themselves from the manifest, so a target added there appears correctly
        everywhere without touching this file.

    .PARAMETER Config
        The imported manifest. Optional - omitting it returns the built-in
        labels only.

    .OUTPUTS
        [hashtable] Step key -> label.

    .EXAMPLE
        $labels = Get-WcdTechnicalStepLabels -Config $config
        $labels['DisplayLanguage']   # Display language
    #>
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
        'NetworkPing8888'        = 'Connectivity test'
        'RefreshNetworkPlaces'   = 'Refresh network places'
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

    foreach ($printer in @(Get-WcdPrinterTarget -Config $Config)) {
        $labels[(Get-WcdPrinterStepKey -Name ([string]$printer.Name))] = [string]$printer.Name
    }

    return $labels
}

function Get-WcdModuleProgressPlan {
    <#
    .SYNOPSIS
        Lists the Step keys each Module will run, in order.

    .DESCRIPTION
        The progress bar needs to know how many steps a Module will produce
        before it runs. Steps filtered out by the chosen Form Factor or
        Environment are left out so the bar cannot overshoot.

    .PARAMETER ExecutionOptions
        Resolved run options: FormFactor, Environment, OpenApps, OptionalTools.

    .PARAMETER Config
        The imported manifest, used for the application and printer steps.

    .OUTPUTS
        [hashtable] Module name -> Step key array.

    .EXAMPLE
        $plan = Get-WcdModuleProgressPlan -ExecutionOptions $options -Config $config
        $plan['Config-Power']   # ScreenTimeoutAc, SetActiveSchemeCurrent
    #>
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

    $printerSteps = @(Get-WcdPrinterTarget -Config $Config |
        ForEach-Object { Get-WcdPrinterStepKey -Name ([string]$_.Name) })

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
        'Config-Network' = @('NetworkAdapterStatus', 'NetworkPing8888', 'RefreshNetworkPlaces')
        'Config-Printer' = $printerSteps
    }
}

function Get-WcdDiagnosticStyle {
    <#
    .SYNOPSIS
        Returns the icon, colour and status word for one diagnostic kind.

    .DESCRIPTION
        Single source of truth for how a kind is rendered, so the progress
        display, the per-module table and the checklist stay consistent. The
        status word is localized through the caller's $T table when one exists.

    .PARAMETER Kind
        'running', 'success', 'warning', 'error', 'manual' or 'na'.

    .OUTPUTS
        [pscustomobject] with Icon, Color and Status.

    .EXAMPLE
        (Get-WcdDiagnosticStyle -Kind 'warning').Icon   # [!]
    #>
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
    <#
    .SYNOPSIS
        Formats the time elapsed since a starting point, in milliseconds.

    .PARAMETER StartedAt
        When the measurement started.

    .OUTPUTS
        [string] e.g. '1,204ms'.

    .EXAMPLE
        Format-WcdElapsedMilliseconds -StartedAt $state.StartedAt
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [datetime]$StartedAt
    )

    $elapsed = (Get-Date) - $StartedAt
    return ('{0:N0}ms' -f $elapsed.TotalMilliseconds)
}

function Format-WcdAsciiProgressBar {
    <#
    .SYNOPSIS
        Renders an ASCII progress bar with a percentage.

    .DESCRIPTION
        ASCII only, so the bar renders identically in every console the tool is
        started from, including a legacy conhost with no Unicode font.

    .PARAMETER CompletedSteps
        Steps finished so far. Clamped into range.

    .PARAMETER TotalSteps
        Steps expected in total. Treated as at least 1.

    .PARAMETER Width
        Bar width in characters. Defaults to 10.

    .OUTPUTS
        [string] e.g. '[###-------] 30%'.

    .EXAMPLE
        Format-WcdAsciiProgressBar -CompletedSteps 3 -TotalSteps 10
    #>
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
    <#
    .SYNOPSIS
        Reports whether the host exposes RawUI.

    .DESCRIPTION
        Without RawUI the progress line cannot be redrawn in place, so the
        display falls back to one line per update.

    .OUTPUTS
        [bool] $true when $Host.UI.RawUI is readable.

    .EXAMPLE
        $mode = if (Test-WcdRawUiAvailability) { 'InPlace' } else { 'Plain' }
    #>
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
    <#
    .SYNOPSIS
        Creates the state object backing one Module's progress display.

    .PARAMETER ModuleName
        Module the bar is being drawn for.

    .PARAMETER StepKeys
        Step keys the Module is expected to run, from Get-WcdModuleProgressPlan.

    .PARAMETER StepLabels
        Step key -> label, from Get-WcdTechnicalStepLabels.

    .OUTPUTS
        [System.Collections.Specialized.OrderedDictionary] progress state.

    .EXAMPLE
        $state = New-WcdProgressState -ModuleName 'Config-Power' -StepKeys $plan['Config-Power'] -StepLabels $labels
    #>
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
    <#
    .SYNOPSIS
        Draws the current progress line for a Module.

    .DESCRIPTION
        Redraws in place with a carriage return when the host has RawUI, and
        writes one line per update otherwise.

    .PARAMETER State
        Progress state from New-WcdProgressState. Everything the line shows -
        the module name, the bar and the elapsed time - comes from it.

    .OUTPUTS
        None. Writes to the host.

    .EXAMPLE
        Write-WcdProgressSnapshot -State $state
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$State
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
    <#
    .SYNOPSIS
        Advances a Module's progress state and redraws the bar.

    .DESCRIPTION
        On 'Finish' the completed count moves to that Step's position in the
        plan, so a Step skipped as Not Applicable cannot leave the bar behind.
        A Step absent from the plan simply advances by one.

    .PARAMETER State
        Progress state from New-WcdProgressState.

    .PARAMETER StepKey
        Step key being started or finished.

    .PARAMETER Event
        'Start' or 'Finish'.

    .OUTPUTS
        None. Mutates State and writes to the host.

    .EXAMPLE
        Update-WcdProgressState -State $state -StepKey 'ScreenTimeoutAc' -Event 'Finish'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$State,

        [Parameter(Mandatory)]
        [string]$StepKey,

        [Parameter(Mandatory)]
        [ValidateSet('Start', 'Finish')]
        [string]$Event
    )

    $State.CurrentStepKey = $StepKey

    if ($Event -eq 'Finish') {
        if ($State.StepLookup.ContainsKey($StepKey)) {
            $State.CompletedSteps = [Math]::Max($State.CompletedSteps, [int]$State.StepLookup[$StepKey])
        } else {
            $State.CompletedSteps = [Math]::Min($State.CompletedSteps + 1, $State.TotalSteps)
        }

        Write-WcdProgressSnapshot -State $State
        return
    }

    Write-WcdProgressSnapshot -State $State
}

function Invoke-WcdProgressCallback {
    <#
    .SYNOPSIS
        Notifies the orchestrator that a Step started or finished.

    .DESCRIPTION
        Modules never touch the progress display directly: they raise an event
        through this callback, which is what lets them be tested with no host
        at all. A $null callback is a no-op.

    .PARAMETER ProgressCallback
        Scriptblock supplied by the orchestrator, or $null.

    .PARAMETER ModuleName
        Module raising the event.

    .PARAMETER StepKey
        Step being started or finished.

    .PARAMETER Event
        'Start' or 'Finish'.

    .PARAMETER Kind
        Outcome of a finished Step: 'success', 'warning' or 'error'.

    .OUTPUTS
        None.

    .EXAMPLE
        Invoke-WcdProgressCallback -ProgressCallback $cb -ModuleName 'Config-Power' -StepKey 'ScreenTimeoutAc' -Event 'Start'
    #>
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
    <#
    .SYNOPSIS
        Builds the machine-identified block appended to the history log.

    .DESCRIPTION
        Prefixes the run log and the final Diagnostic with the machine name,
        serial number, model and user, so one history file can hold a readable
        record of every machine configured from the same USB key.

    .PARAMETER LocalLogPath
        Path to this run's log file.

    .PARAMETER DiagnosticLines
        Rendered Diagnostic lines to append after the log section.

    .OUTPUTS
        [string] The block, newline-joined.

    .EXAMPLE
        Get-WcdHistoryBlock -LocalLogPath $log -DiagnosticLines $lines
    #>
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
    <#
    .SYNOPSIS
        Appends this run's history block to the cumulative history log.

    .DESCRIPTION
        Creates the target directory when missing and appends, never
        overwrites, so a USB key keeps one running record across every machine
        it is used on.

    .PARAMETER LocalLogPath
        Path to this run's log file.

    .PARAMETER HistoryLogPath
        Cumulative history file to append to.

    .PARAMETER DiagnosticLines
        Rendered Diagnostic lines to include in the block.

    .OUTPUTS
        [string] The history log path written to.

    .EXAMPLE
        Export-WcdHistoryLog -LocalLogPath $log -HistoryLogPath 'E:\log.txt' -DiagnosticLines $lines
    #>
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

function New-WcdRunReport {
    <#
    .SYNOPSIS
        Builds the machine-readable run summary written by -ReportPath.

    .DESCRIPTION
        Built from the Diagnostic entries the technician already sees, not
        recomputed, so the JSON and the console can never disagree. Convert it
        with ConvertTo-Json -Depth 5 or deeper: the default depth of 2 silently
        flattens the steps array into type names.

        schemaVersion is present from the first release so a fleet collector
        can version against it.

    .PARAMETER ChecklistEntries
        Entries from Get-WcdFinalChecklistEntries: Step, Label, Kind, Detail.

    .PARAMETER ExecutionOptions
        Resolved run options: Language, FormFactor, Environment.

    .PARAMETER Elevated
        Whether the run held Administrator rights.

    .OUTPUTS
        [hashtable] ready for ConvertTo-Json -Depth 5.

    .EXAMPLE
        $report = New-WcdRunReport -ChecklistEntries $entries -ExecutionOptions $options -Elevated $false
        $report | ConvertTo-Json -Depth 5 | Set-Content -Path 'C:\temp\run.json'
    #>
    [CmdletBinding()]
    param(
        [object[]]$ChecklistEntries = @(),

        [Parameter(Mandatory)]
        [pscustomobject]$ExecutionOptions,

        [bool]$Elevated = $false
    )

    $entries = @($ChecklistEntries)
    $countOf = { param($kind) @($entries | Where-Object { $_.Kind -eq $kind }).Count }

    return @{
        schemaVersion = 1
        timestamp     = [DateTimeOffset]::Now.ToString('o')
        computerName  = $env:COMPUTERNAME
        context       = @{
            formFactor  = [string]$ExecutionOptions.FormFactor
            environment = [string]$ExecutionOptions.Environment
            elevated    = $Elevated
            language    = [string]$ExecutionOptions.Language
        }
        summary       = @{
            ok            = (& $countOf 'success')
            warning       = (& $countOf 'warning')
            error         = (& $countOf 'error')
            manual        = (& $countOf 'manual')
            notApplicable = (& $countOf 'na')
        }
        steps         = @($entries | ForEach-Object {
            @{
                step   = [string]$_.Step
                name   = [string]$_.Label
                kind   = [string]$_.Kind
                detail = [string]$_.Detail
            }
        })
    }
}

function Invoke-WcdPowerCfg {
    <#
    .SYNOPSIS
        Runs powercfg.exe and throws on a non-zero exit code.

    .DESCRIPTION
        powercfg reports failure through its exit code rather than a
        PowerShell error, so this wrapper turns it into a catchable exception.
        Most powercfg writes need Administrator; the caller checks that first
        and reports an actionable warning instead of calling this.

    .PARAMETER Arguments
        Arguments passed straight through to powercfg.exe.

    .OUTPUTS
        None. Throws on failure.

    .EXAMPLE
        Invoke-WcdPowerCfg '/change' 'monitor-timeout-ac' 15
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments)]
        [string[]]$Arguments
    )

    & powercfg @Arguments | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "powercfg exited with code $LASTEXITCODE."
    }
}

function Open-WcdUrl {
    <#
    .SYNOPSIS
        Opens a URL in the machine's default browser.

    .PARAMETER Url
        The URL to open.

    .OUTPUTS
        None. Throws when no handler is registered.

    .EXAMPLE
        Open-WcdUrl -Url 'https://example.service-now.com/sp'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url
    )

    # Start-Process on a URL hands it to the machine's default browser.
    Start-Process $Url -ErrorAction Stop
}

function Get-WcdApplicationTarget {
    <#
    .SYNOPSIS
        Returns the Application Targets that apply to this machine's context.

    .DESCRIPTION
        Filters the manifest's Applications by Environment and Form Factor, and
        keeps a Prompt entry only when the technician selected it. Manifest
        order is preserved: it is the order the technician sees.

    .PARAMETER Config
        The imported manifest.

    .PARAMETER Environment
        'Workstation' or 'Vdi'. Defaults to 'Workstation'.

    .PARAMETER FormFactor
        'Laptop' or 'Desktop'. Defaults to 'Laptop'.

    .PARAMETER OptionalTools
        Names of Prompt entries the technician selected. Prompt entries not
        named here are left out entirely.

    .OUTPUTS
        [object[]] Matching manifest entries, in manifest order.

    .EXAMPLE
        Get-WcdApplicationTarget -Config $config -Environment 'Vdi' -FormFactor 'Laptop'

    .EXAMPLE
        # Include one optional tool the technician picked from the menu
        Get-WcdApplicationTarget -Config $config -OptionalTools @('NVIDIA App')
    #>
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
    <#
    .SYNOPSIS
        Returns the Optional Tools the technician should be offered.

    .DESCRIPTION
        Optional Tools are Application Targets carrying Prompt = $true: they
        never run automatically, and the optional-tools menu is built from
        this list. An empty result means the menu is skipped entirely.

    .PARAMETER Config
        The imported manifest.

    .PARAMETER Environment
        'Workstation' or 'Vdi'. Defaults to 'Workstation'. An entry restricted
        to the other Environment is not offered.

    .OUTPUTS
        [object[]] Prompt entries, in manifest order.

    .EXAMPLE
        $candidates = Get-WcdPromptedApplicationTarget -Config $config
        if ($candidates.Count -gt 0) { Read-WcdOptionalToolChoice -Candidates $candidates }
    #>
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

function Get-WcdPrinterTarget {
    <#
    .SYNOPSIS
        Returns the shared print queues declared in the manifest.

    .DESCRIPTION
        Only entries carrying both a Name and a Connection are returned, so a
        half-filled example left in the manifest is ignored rather than turned
        into a failing Step. An empty result means the printer Module is
        skipped and printers stay a Manual Step.

    .PARAMETER Config
        The imported manifest.

    .OUTPUTS
        [object[]] Printer entries with Name and Connection.

    .EXAMPLE
        Get-WcdPrinterTarget -Config $config | ForEach-Object { $_.Connection }
    #>
    [CmdletBinding()]
    param(
        [hashtable]$Config
    )

    if ($null -eq $Config -or $null -eq $Config.Printers) { return @() }

    return @($Config.Printers | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_.Name) -and
        -not [string]::IsNullOrWhiteSpace([string]$_.Connection)
    })
}

function Get-WcdChoiceLabel {
    <#
    .SYNOPSIS
        Translates a canonical choice value into what the technician sees.

    .DESCRIPTION
        Choice values are canonical English so the code and the logs read the
        same in every language; only the display is localized. A value with no
        translation is returned unchanged.

    .PARAMETER Value
        Canonical value, e.g. 'Laptop' or 'Vdi'.

    .PARAMETER Labels
        Localized label table, e.g. $T.Labels. Optional.

    .OUTPUTS
        [string] The localized label, or Value unchanged.

    .EXAMPLE
        Get-WcdChoiceLabel -Value 'Laptop' -Labels @{ Laptop = 'Portable' }   # Portable
    #>
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
    <#
    .SYNOPSIS
        Loads the manifest, WinContextDeploy.psd1.

    .DESCRIPTION
        Uses ConfigPath when given. Otherwise searches the project root, the
        script folder and the current directory, so the tool finds its manifest
        whether it is started from the repo, from a USB key or from a copy
        under %TEMP%.

    .PARAMETER ConfigPath
        Explicit manifest path. Optional.

    .OUTPUTS
        [hashtable] The imported manifest.

    .EXAMPLE
        $config = Import-WcdConfig
        $config.Applications.Count
    #>
    [CmdletBinding()]
    param(
        [string]$ConfigPath
    )

    if (-not [string]::IsNullOrWhiteSpace($ConfigPath) -and (Test-Path -LiteralPath $ConfigPath)) {
        return Import-PowerShellDataFile -Path $ConfigPath
    }

    # Automatic search: the script's parent folder is the project root.
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

    throw 'WinContextDeploy.psd1 not found. Supply its path with -ConfigPath.'
}

function Resolve-WcdDynamicPath {
    <#
    .SYNOPSIS
        Finds an executable inside a versioned installation folder.

    .DESCRIPTION
        Some vendors install into a folder whose name carries the version. The
        highest-sorting folder matching Pattern is taken, which is the newest
        version for the usual naming schemes.

    .PARAMETER BasePath
        Folder to search in.

    .PARAMETER Pattern
        Wildcard matching the version folder, e.g. 'Acme *'.

    .PARAMETER ExeName
        Executable expected inside that folder.

    .OUTPUTS
        [string] Full path to the executable, or $null when not found.

    .EXAMPLE
        Resolve-WcdDynamicPath -BasePath 'C:\Program Files\Acme' -Pattern 'Viewer *' -ExeName 'viewer.exe'
    #>
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
    <#
    .SYNOPSIS
        Creates or updates one registry value, creating its key when missing.

    .DESCRIPTION
        Every registry write in the project goes through here. All of them
        target HKCU and work unelevated; a key locked by Group Policy throws,
        and the caller turns that into an actionable warning.

    .PARAMETER Path
        Registry key path, e.g. 'HKCU:\Control Panel\International'.

    .PARAMETER Name
        Value name to write.

    .PARAMETER Value
        Value to write.

    .PARAMETER PropertyType
        'String' or 'DWord'. Defaults to 'String'. Used only when the value is
        being created.

    .OUTPUTS
        None. Throws when the key or value cannot be written.

    .EXAMPLE
        Set-WcdRegistryValue -Path 'HKCU:\Control Panel\International' -Name 'sDecimal' -Value '.'

    .EXAMPLE
        Set-WcdRegistryValue -Path $explorerAdvanced -Name 'TaskbarAl' -Value 0 -PropertyType DWord
    #>
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
