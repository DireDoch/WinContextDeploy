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
        A module status object: Module, Status, Steps, Detail.

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
    $line = ('  {0}  {1,-25} {2,-9} {3} {4}' -f $style.Icon, $ModuleStatus.Module, $ModuleStatus.Status, $ModuleStatus.Steps, $T.StepCount)
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

function Resolve-WcdDescriptorRow {
    <#
    .SYNOPSIS
        Turns one descriptor row into a checklist entry.

    .DESCRIPTION
        A row either states a fixed fact - an Application Target the Environment
        filtered out, a Manual Step - or it is backed by Steps and takes its kind
        from their Results.

        A row carrying OmitWhenMissing disappears when its Steps produced
        nothing. That is for a Step a Module reports only when something went
        wrong: Config-Applications raises WingetUnavailable when the probe fails
        and stays silent otherwise, and a silent probe should not leave a row.

    .PARAMETER Row
        One entry from a descriptor's Rows array.

    .PARAMETER ResultLookup
        Step key -> Results.

    .PARAMETER StepLabels
        Step key -> label.

    .OUTPUTS
        [pscustomobject] one checklist entry, or nothing when the row is omitted.

    .EXAMPLE
        Resolve-WcdDescriptorRow -Row $descriptor.Rows[0] -ResultLookup $lookup -StepLabels $labels
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Row,

        [Parameter(Mandatory)]
        [hashtable]$ResultLookup,

        [Parameter(Mandatory)]
        [hashtable]$StepLabels
    )

    if (-not [string]::IsNullOrWhiteSpace([string]$Row.Kind)) {
        return New-WcdDiagnosticEntry -Label ([string]$Row.Label) -Kind ([string]$Row.Kind) `
            -Detail ([string]$Row.Detail) -Step ([string]$Row.Step)
    }

    $stepKeys = @(@($Row.Steps) | ForEach-Object { [string]$_ })

    if ($Row.OmitWhenMissing) {
        $found = @(Get-WcdResultsForSteps -ResultLookup $ResultLookup -StepKeys $stepKeys)
        if ($found.Count -eq 0) { return }
    }

    $arguments = @{
        Label        = [string]$Row.Label
        ResultLookup = $ResultLookup
        StepKeys     = $stepKeys
        StepLabels   = $StepLabels
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Row.MissingKind))   { $arguments['MissingKind'] = [string]$Row.MissingKind }
    if (-not [string]::IsNullOrWhiteSpace([string]$Row.MissingDetail)) { $arguments['MissingDetail'] = [string]$Row.MissingDetail }

    return Resolve-WcdAutomaticEntry @arguments
}

function Resolve-WcdRestartEntry {
    <#
    .SYNOPSIS
        Raises the restart row when, and only when, something is waiting on one.

    .DESCRIPTION
        The tool never restarts the machine: a reboot mid-run would destroy the
        checklist, the history log and the JSON report. So it says so instead.

        The row is raised from Results across two Modules, which is why it
        belongs to no descriptor. An update waiting on a restart needs the same
        restart a rename does, so the row is raised once and names whichever
        causes apply - two restart rows would read as two restarts.

        Applied, not merely successful: renaming a machine to the name it
        already has succeeds without changing anything a restart takes effect
        for.

    .PARAMETER ResultLookup
        Step key -> Results.

    .OUTPUTS
        [pscustomobject] the restart entry, or nothing when no restart is pending.

    .EXAMPLE
        Resolve-WcdRestartEntry -ResultLookup $lookup
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ResultLookup
    )

    $identityApplied = @(Get-WcdResultsForSteps -ResultLookup $ResultLookup -StepKeys @('ComputerName', 'DomainJoin') |
        Where-Object { $_.Applied })
    $updateRebootPending = @(Get-WcdResultsForSteps -ResultLookup $ResultLookup -StepKeys @('WindowsUpdateReboot') |
        Where-Object { $_.RebootPending })

    if ($identityApplied.Count -eq 0 -and $updateRebootPending.Count -eq 0) { return }

    $detail = if ($identityApplied.Count -gt 0 -and $updateRebootPending.Count -gt 0) {
        $T.RestartBothManualDetail
    } elseif ($updateRebootPending.Count -gt 0) {
        $T.RestartUpdateManualDetail
    } else {
        $T.RestartManualDetail
    }

    return New-WcdDiagnosticEntry -Label $T.Checklist.RestartNeeded -Kind 'manual' -Detail $detail
}

function Get-WcdFinalChecklistEntries {
    <#
    .SYNOPSIS
        Builds the technician's checklist from the Modules' descriptors.

    .DESCRIPTION
        The one place the run is turned into what the technician reads, and the
        source the JSON report is built from, so the two can never disagree.

        Every row comes from a descriptor, in RowOrder. Two things do not,
        because they belong to no single Module:

        - the restart row, raised from Results across Config-Identity and
          Config-WindowsUpdate, which sits between the identity rows and the
          rest of the checklist;
        - the trailing Manual Steps, work WinContextDeploy deliberately does not
          automate. Printers join them when the manifest declares no queue,
          which is also when Config-Printer plans nothing and is skipped.

    .PARAMETER AllResults
        Every Result produced by the run.

    .PARAMETER Descriptors
        Every Module descriptor for this run, from Get-Wcd*Descriptor.

    .PARAMETER StepLabels
        Step key -> label.

    .PARAMETER Config
        The imported manifest, for the printers-are-manual rule.

    .OUTPUTS
        [pscustomobject[]] with Step, Label, Kind and Detail.

    .EXAMPLE
        Get-WcdFinalChecklistEntries -AllResults $results -Descriptors $descriptors `
            -StepLabels $labels -Config $config
    #>
    [CmdletBinding()]
    param(
        [object[]]$AllResults = @(),

        [object[]]$Descriptors = @(),

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

    # Rows are emitted for every Module, including one the run skipped: a
    # declined rename still owes the technician a Manual Step saying so.
    $entries = @()
    $restartRowOrder = 15
    $restartRaised = $false

    foreach ($descriptor in @(@($Descriptors) | Sort-Object { [int]$_.RowOrder })) {
        if (-not $restartRaised -and [int]$descriptor.RowOrder -ge $restartRowOrder) {
            $entries += Resolve-WcdRestartEntry -ResultLookup $lookup
            $restartRaised = $true
        }

        foreach ($row in @($descriptor.Rows)) {
            $entries += Resolve-WcdDescriptorRow -Row $row -ResultLookup $lookup -StepLabels $StepLabels
        }
    }

    if (-not $restartRaised) {
        $entries += Resolve-WcdRestartEntry -ResultLookup $lookup
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
    if (@(Get-WcdPrinterTarget -Config $Config).Count -eq 0) { $manualLabels += $T.Checklist.Printers }

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
