# Diagnostic: the end-of-run report.
#
# Split out of Invoke-WcdConfiguration.ps1 so the rules CONTEXT.md pins down -
# Manual Step vs Not Applicable vs failure - can be reached from Pester without
# running a whole configuration pass. Reads $T from script scope, like the
# orchestrator does; the test file sets $script:T before dot-sourcing.

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

    # A Step the Module could not run, and deliberately handed back to the
    # technician, is a Manual Step rather than a failure.
    if ($severity -eq 'MANUAL') {
        return New-WcdDiagnosticEntry -Label $Label -Kind 'manual' -Detail (Get-WcdAggregateDetail -Results $results -StepLabels $StepLabels) -Step $stepId
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

    # --- Machine identity -----------------------------------------------------
    # Declining is a choice, not a filter, so both rows are Manual Steps rather
    # than Not Applicable - which also lets a fleet-wide report show which
    # machines are still unnamed.
    $entries += Resolve-WcdAutomaticEntry -Label $T.Checklist.ComputerName -ResultLookup $lookup `
        -StepKeys @('ComputerName') -StepLabels $StepLabels `
        -MissingKind 'manual' -MissingDetail $T.IdentityManualDetail
    $entries += Resolve-WcdAutomaticEntry -Label $T.Checklist.DomainJoin -ResultLookup $lookup `
        -StepKeys @('DomainJoin') -StepLabels $StepLabels `
        -MissingKind 'manual' -MissingDetail $T.IdentityManualDetail

    # The tool never restarts the machine: a reboot mid-run would destroy the
    # checklist, the history log and the JSON report. So it says so instead,
    # but only when there is actually something waiting on a restart.
    # Applied, not merely successful: renaming a machine to the name it already
    # has succeeds without changing anything a restart would take effect for.
    $identityApplied = @(Get-WcdResultsForSteps -ResultLookup $lookup -StepKeys @('ComputerName', 'DomainJoin') |
        Where-Object { $_.Applied })
    # An update waiting on a restart needs the same restart the rename does, so
    # the row is raised once and names whichever causes apply. Two restart rows
    # would read as two restarts.
    $updateRebootPending = @(Get-WcdResultsForSteps -ResultLookup $lookup -StepKeys @('WindowsUpdateReboot') |
        Where-Object { $_.RebootPending })
    if ($identityApplied.Count -gt 0 -or $updateRebootPending.Count -gt 0) {
        $restartDetail = if ($identityApplied.Count -gt 0 -and $updateRebootPending.Count -gt 0) {
            $T.RestartBothManualDetail
        } elseif ($updateRebootPending.Count -gt 0) {
            $T.RestartUpdateManualDetail
        } else {
            $T.RestartManualDetail
        }

        $entries += New-WcdDiagnosticEntry -Label $T.Checklist.RestartNeeded -Kind 'manual' -Detail $restartDetail
    }

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
    $entries += Resolve-WcdAutomaticEntry -Label $T.Checklist.Tpm -ResultLookup $lookup `
        -StepKeys @('TpmReadiness') -StepLabels $StepLabels
    $entries += Resolve-WcdAutomaticEntry -Label $T.Checklist.BitLocker -ResultLookup $lookup `
        -StepKeys @('BitLockerStatus') -StepLabels $StepLabels
    # One row for both update Steps: a failed update and a pending restart are
    # the same conversation with the technician, and the restart itself is asked
    # for once, in the restart row above.
    $entries += Resolve-WcdAutomaticEntry -Label $T.Checklist.WindowsUpdate -ResultLookup $lookup `
        -StepKeys @('WindowsUpdateHistory', 'WindowsUpdateReboot') -StepLabels $StepLabels
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

    # Config-Applications reports the winget probe once, and only when the
    # manifest has CheckWinget entries at all.
    if ($lookup.ContainsKey('WingetUnavailable')) {
        $entries += Resolve-WcdAutomaticEntry -Label $T.Checklist.Winget -ResultLookup $lookup `
            -StepKeys @('WingetUnavailable') -StepLabels $StepLabels
    }

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
