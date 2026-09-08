# Config-Power.ps1 - screen timeouts, lid-close action, and the active scheme.
# Entry point: Set-WcdPowerConfiguration. Requires WcdHelpers.ps1.
#
# The only Module that needs Administrator. Unelevated, it reports what would
# have needed it rather than failing.

# A laptop redeployed from stock with a badly worn battery is a return trip six
# weeks later. The wear is measurable at bring-up and invisible on the desktop.
# Below this fraction of its design capacity, the battery is worth naming. A
# constant rather than a manifest key: nothing yet suggests it varies by site.
$script:WcdBatteryWearWarningRatio = 0.80

function Get-WcdBatteryReportHtml {
    <#
    .SYNOPSIS
        Runs powercfg /batteryreport and returns the report it wrote.

    .DESCRIPTION
        /batteryreport has no structured output mode, so the report is HTML and
        this is the only way to get at it.

        Written to a temp path and deleted afterwards, whatever happens. The
        technician has a checklist to read, not a second report to find beside
        the log.

        Needs Administrator, like every other powercfg call in this Module.

    .OUTPUTS
        [string] The report's HTML. Throws when powercfg refuses or the report
        cannot be read.

    .EXAMPLE
        (Get-WcdBatteryReportHtml).Length
    #>
    [CmdletBinding()]
    param()

    $reportPath = Join-Path ([IO.Path]::GetTempPath()) ('wcd-batteryreport-{0}.html' -f [guid]::NewGuid())
    try {
        Invoke-WcdPowerCfg '/batteryreport' '/output' $reportPath
        return [string](Get-Content -LiteralPath $reportPath -Raw -ErrorAction Stop)
    } finally {
        Remove-Item -LiteralPath $reportPath -Force -ErrorAction SilentlyContinue
    }
}

function ConvertFrom-WcdBatteryReport {
    <#
    .SYNOPSIS
        Pulls the design and full-charge capacities out of a battery report.

    .DESCRIPTION
        The parse is the brittle part of this Step and is treated that way.
        /batteryreport emits HTML meant for a human, its field labels are
        localized, and its layout has changed across Windows builds - so nothing
        here matches a label. The installed-battery table prints the design
        capacity and then the full charge capacity, both in mWh, and those are
        the first two mWh figures in the document.

        The numbers are localized too: 52,000 and 52 000 and 52.000 are the same
        battery. Every separator is stripped before the value is read.

        Three outcomes that are not a worn battery, and must not read like one:

        - Not a report at all. powercfg answered with something this cannot
          read; that is its own diagnosable state.
        - A report with no battery in it. The Form Factor is chosen by the
          technician, not detected, so someone will pick Laptop on a
          small-form-factor desktop. Not Applicable.
        - A report whose capacities are zero. A machine straight off the bench
          has no charge cycles for the report to draw on. That is information,
          not a warning.

    .PARAMETER Html
        The report's HTML, from Get-WcdBatteryReportHtml.

    .OUTPUTS
        [hashtable] with Parsed, HasBattery, DesignCapacity and
        FullChargeCapacity.

    .EXAMPLE
        (ConvertFrom-WcdBatteryReport -Html $html).DesignCapacity   # 52000
    #>
    [CmdletBinding()]
    param(
        [string]$Html
    )

    $empty = @{ Parsed = $false; HasBattery = $false; DesignCapacity = 0; FullChargeCapacity = 0 }

    if ([string]::IsNullOrWhiteSpace($Html) -or $Html -notmatch '<html') { return $empty }

    # mWh is a unit rather than a word, so it survives every translation of the
    # labels around it.
    $capacities = @([regex]::Matches($Html, '([\d][\d\s,.]*)\s*mWh') | ForEach-Object {
        [int64]($_.Groups[1].Value -replace '[^\d]', '')
    })

    if ($capacities.Count -lt 2) {
        return @{ Parsed = $true; HasBattery = $false; DesignCapacity = 0; FullChargeCapacity = 0 }
    }

    return @{ Parsed             = $true
              HasBattery         = $true
              DesignCapacity     = $capacities[0]
              FullChargeCapacity = $capacities[1] }
}

function Get-WcdBatteryHealthInfo {
    <#
    .SYNOPSIS
        Turns a parsed battery report into a severity and a label.

    .PARAMETER Report
        A hashtable from ConvertFrom-WcdBatteryReport.

    .PARAMETER WarningRatio
        Full charge as a fraction of design capacity, below which the battery is
        warned about.

    .OUTPUTS
        [hashtable] with Severity, Label and, when there is one, RemedyKey and
        RemedyArgs.

    .EXAMPLE
        Get-WcdBatteryHealthInfo -Report $report -WarningRatio 0.80
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Report,

        [double]$WarningRatio = 0.80
    )

    if (-not $Report.Parsed) {
        return @{ Severity  = 'WARNING'
                  Label     = 'The battery report could not be read, so battery wear was not checked.'
                  RemedyKey = 'BatteryReportUnreadable' }
    }

    if (-not $Report.HasBattery) {
        return @{ Severity = 'NA'
                  Label    = 'The battery report lists no battery. This machine has no battery to wear out, whatever Form Factor was chosen.' }
    }

    if ([int64]$Report.DesignCapacity -le 0 -or [int64]$Report.FullChargeCapacity -le 0) {
        return @{ Severity = 'INFO'
                  Label    = 'The battery report has no usable capacity figures yet; this machine has not been through enough charge cycles.' }
    }

    $ratio = [double]$Report.FullChargeCapacity / [double]$Report.DesignCapacity
    $percent = [math]::Round($ratio * 100)

    if ($ratio -lt $WarningRatio) {
        return @{ Severity   = 'WARNING'
                  Label      = ('The battery holds {0}% of its design capacity ({1} of {2} mWh).' -f $percent, $Report.FullChargeCapacity, $Report.DesignCapacity)
                  RemedyKey  = 'BatteryWorn'
                  RemedyArgs = @($percent) }
    }

    return @{ Severity = 'INFO'
              Label    = ('The battery holds {0}% of its design capacity.' -f $percent) }
}

function Set-WcdPowerConfiguration {
    <#
    .SYNOPSIS
        Applies the screen timeouts, the lid-close action and the active power scheme.

    .DESCRIPTION
        Drives powercfg.exe from a step table. The battery and lid steps apply to a
        Laptop only; on a Desktop they are Not Applicable, not skipped.

        The sleep steps (standby-timeout-*) are deliberately left out - they are
        blocked by Group Policy in the environments this tool was built for. The
        commented rows in the step table are what to restore if that changes.

        powercfg needs Administrator. An unelevated run attempts nothing: every
        step reports as a warning saying to relaunch elevated, which is a far more
        useful diagnostic than five raw exit codes.

    .PARAMETER FormFactor
        'Laptop' or 'Desktop'. Battery and lid steps apply to a Laptop only.
        Defaults to 'Laptop'.

    .PARAMETER Elevated
        Whether the run holds Administrator rights. When $false no powercfg call is
        attempted. Defaults to $true.

    .PARAMETER LogPath
        Full path to the log file. Resolved automatically when omitted.

    .PARAMETER ProgressCallback
        Scriptblock invoked at the start and end of each step for progress display.

    .OUTPUTS
        [pscustomobject[]] with Step, Success, Error and, on a failure, Severity
        and RemedyKey.

    .EXAMPLE
        Set-WcdPowerConfiguration -FormFactor 'Laptop' -LogPath 'C:\temp\log.txt'

    .EXAMPLE
        # Unelevated: reports what would need Administrator instead of failing
        Set-WcdPowerConfiguration -FormFactor 'Desktop' -Elevated $false
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Laptop', 'Desktop')]
        [string]$FormFactor = 'Laptop',

        [bool]$Elevated = $true,

        [string]$LogPath,

        [scriptblock]$ProgressCallback
    )

    $resolvedLogPath = Resolve-WcdLogPath -CandidatePath $LogPath
    $results = @()
    $moduleName = 'Config-Power'
    $laptopOnly = ($FormFactor -eq 'Laptop')
    $requiresElevation = -not $Elevated

    $steps = @(
        @{ Step = 'ScreenTimeoutBattery'; LaptopOnly = $true;  Log = 'Power: screen timeout on battery set to 10 min.'; Fail = 'Screen timeout on battery'
           Arguments = @('/change', 'monitor-timeout-dc', '10') }

        @{ Step = 'ScreenTimeoutAc';      LaptopOnly = $false; Log = 'Power: screen timeout on AC set to 15 min.';      Fail = 'Screen timeout on AC'
           Arguments = @('/change', 'monitor-timeout-ac', '15') }

        # BLOCKED BY GPO: the standby-timeout steps are deliberately disabled.
        # @{ Step = 'SleepAcNever';      LaptopOnly = $false; Log = 'Power: sleep on AC set to never.';      Fail = 'Sleep on AC'
        #    Arguments = @('/change', 'standby-timeout-ac', '0') }
        # @{ Step = 'SleepBatteryNever'; LaptopOnly = $true;  Log = 'Power: sleep on battery set to never.'; Fail = 'Sleep on battery'
        #    Arguments = @('/change', 'standby-timeout-dc', '0') }

        @{ Step = 'LidActionAcNone';      LaptopOnly = $true;  Log = 'Power: lid close on AC set to do nothing.';      Fail = 'Lid close on AC'
           Arguments = @('/setacvalueindex', 'SCHEME_CURRENT', 'SUB_BUTTONS', 'LIDACTION', '0') }

        @{ Step = 'LidActionBatteryNone'; LaptopOnly = $true;  Log = 'Power: lid close on battery set to do nothing.'; Fail = 'Lid close on battery'
           Arguments = @('/setdcvalueindex', 'SCHEME_CURRENT', 'SUB_BUTTONS', 'LIDACTION', '0') }

        @{ Step = 'SetActiveSchemeCurrent'; LaptopOnly = $false; Log = 'Power: active scheme applied.'; Fail = 'Apply active scheme'
           Arguments = @('/setactive', 'SCHEME_CURRENT') }
    )

    foreach ($step in $steps) {
        if ($step.LaptopOnly -and -not $laptopOnly) { continue }

        # L'Action se cree ici et s'execute dans cette portee, donc elle voit
        # ces trois variables. Elles sont reaffectees a chaque tour, ce qui est
        # sans danger: l'Action tourne avant le tour suivant.
        $powerCfgArguments = @($step.Arguments)
        $stepLabel = [string]$step.Fail

        $results += Invoke-WcdStep -Module $moduleName -Key ([string]$step.Step) `
            -LogPath $resolvedLogPath -ProgressCallback $ProgressCallback `
            -SuccessLog ([string]$step.Log) `
            -FailureLabel $stepLabel -FailureRemedy 'PowerCfgFailed' `
            -Action {
                # Unelevated, the Step does not run: it reports what would have
                # needed Administrator, which is a far more useful diagnostic
                # than a raw exit code.
                if ($requiresElevation) {
                    # [ordered]: le fragment fixe l'ordre des proprietes du
                    # Resultat, que le rapport JSON reprend tel quel.
                    return [ordered]@{
                        Severity  = 'WARNING'
                        Error     = 'powercfg requires Administrator.'
                        RemedyKey = 'RequiresAdmin'
                        Log       = '{0}: skipped, powercfg requires Administrator.' -f $stepLabel
                    }
                }

                Invoke-WcdPowerCfg @powerCfgArguments
            }
    }

    # --- Battery wear, which only a Laptop can have --------------------------
    if ($laptopOnly) {
        $wearRatio = $script:WcdBatteryWearWarningRatio
        $results += Invoke-WcdStep -Module $moduleName -Key 'BatteryHealth' `
            -LogPath $resolvedLogPath -ProgressCallback $ProgressCallback `
            -FailureLabel 'Battery health' -FailureRemedy 'BatteryReportUnreadable' `
            -Action {
                if ($requiresElevation) {
                    return @{ Severity  = 'WARNING'
                              Error     = 'powercfg /batteryreport requires Administrator.'
                              RemedyKey = 'RequiresAdmin'
                              Log       = 'Battery health: skipped, powercfg requires Administrator.' }
                }

                # Caught here rather than in -OnFailure: a report that cannot be
                # produced is its own diagnosable state, and Invoke-WcdStep
                # marks anything that threw as a failed Step.
                $html = ''
                try {
                    $html = Get-WcdBatteryReportHtml
                } catch {
                    return @{ Severity  = 'WARNING'
                              Error     = ('The battery report could not be produced: {0}' -f $_.Exception.Message)
                              RemedyKey = 'BatteryReportUnreadable'
                              Log       = 'Battery health: the report could not be produced: {0}' -f $_.Exception.Message }
                }

                $info = Get-WcdBatteryHealthInfo -Report (ConvertFrom-WcdBatteryReport -Html $html) -WarningRatio $wearRatio
                $fragment = @{ Severity = $info.Severity; Error = $info.Label; Log = 'Power: {0}' -f $info.Label }
                if ($info.ContainsKey('RemedyKey'))  { $fragment['RemedyKey'] = $info.RemedyKey }
                if ($info.ContainsKey('RemedyArgs')) { $fragment['RemedyArgs'] = $info.RemedyArgs }
                return $fragment
            }
    }

    return $results
}

function Get-WcdPowerDescriptor {
    <#
    .SYNOPSIS
        Declares what Config-Power contributes to the run.

    .DESCRIPTION
        Six Steps on a Laptop and two on a Desktop. The battery and lid Steps are
        Not Applicable to a Desktop, so they are declared but not planned - the
        label survives for the diagnostic, the progress bar cannot overshoot.

        Battery health gets its own row rather than joining the power options
        row, because it is answered differently: a worn battery is a part to
        replace before deployment, not a setting to reapply. On a Desktop that
        row is stated Not Applicable outright.

        A Module declares itself here instead of in six places across the
        orchestrator and the helpers. See Test-WcdModuleDescriptor in
        WcdHelpers.ps1 for the contract.

    .PARAMETER ExecutionOptions
        Resolved run options: Language, FormFactor, Environment, OpenApps,
        OptionalTools, NewComputerName and JoinDomain.

    .PARAMETER Config
        The imported manifest.

    .PARAMETER Translations
        The active $T table, for the checklist row labels.

    .OUTPUTS
        [pscustomobject] with Name, Order, RowOrder, Steps, Rows and Invoke.

    .EXAMPLE
        Get-WcdPowerDescriptor -ExecutionOptions $options -Config $config -Translations $T
    #>
    # The signature is a contract: the orchestrator calls every descriptor
    # the same way, so each declares all three parameters even when it reads one.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
        Justification = 'Uniform descriptor signature; the orchestrator calls every Module identically.')]
    [CmdletBinding()]
    param(
        [pscustomobject]$ExecutionOptions,

        [hashtable]$Config,

        [hashtable]$Translations
    )

    $laptop = ($ExecutionOptions.FormFactor -eq 'Laptop')

    $steps = @(
        @{ Key = 'ScreenTimeoutBattery';   Label = 'Screen timeout on battery';       Planned = $laptop }
        @{ Key = 'ScreenTimeoutAc';        Label = 'Screen timeout on AC';            Planned = $true }
        @{ Key = 'LidActionAcNone';        Label = 'Lid close on AC: do nothing';     Planned = $laptop }
        @{ Key = 'LidActionBatteryNone';   Label = 'Lid close on battery: do nothing'; Planned = $laptop }
        @{ Key = 'SetActiveSchemeCurrent'; Label = 'Active power scheme';             Planned = $true }
        @{ Key = 'BatteryHealth';          Label = 'Battery health';                  Planned = $laptop }
    )

    # A Desktop has no battery to wear out, so the row states that rather than
    # waiting for a Result that will never come.
    $batteryRow = if ($laptop) {
        @{ Label = $Translations.Checklist.Battery; Steps = @('BatteryHealth') }
    } else {
        @{ Label = $Translations.Checklist.Battery; Kind = 'na'; Detail = $Translations.SecondaryNA; Step = 'BatteryHealth' }
    }

    return [pscustomobject]@{
        Name     = 'Config-Power'
        Order    = 20
        RowOrder = 50
        Steps    = $steps
        Rows     = @(
            @{ Label = $Translations.Checklist.Power
               Steps = @($steps | Where-Object { $_.Planned -and $_.Key -ne 'BatteryHealth' } | ForEach-Object { $_.Key }) }
            $batteryRow
        )
        Invoke   = {
            param($ctx)

            Set-WcdPowerConfiguration -FormFactor $ctx.ExecutionOptions.FormFactor -Elevated $ctx.Elevated `
                -LogPath $ctx.LogPath -ProgressCallback $ctx.ProgressCallback
        }
    }
}