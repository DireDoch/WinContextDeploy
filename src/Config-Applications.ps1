# Config-Applications.ps1 - verifies and opens the Application Targets.
# Entry point: Set-WcdApplicationsConfiguration. Requires WcdHelpers.ps1.
#
# Adding, removing or reordering an application is a manifest edit; nothing in
# this file needs to change for it.

$script:WcdApplicationActions = @('Launch', 'OpenFolder', 'OpenUrl', 'CheckProcess', 'CheckPath')

function Test-WcdTargetPresent {
    <#
    .SYNOPSIS
        Reports whether an Application Target's Target can be found up front.

    .DESCRIPTION
        Only targets that look like filesystem paths are checked here. A bare
        command such as 'ms-teams.exe' is resolved by the shell, and OpenUrl and
        CheckProcess targets are not paths at all, so all three are reported
        present and left for Invoke-WcdApplicationTarget to attempt.

    .PARAMETER Entry
        One Application Target entry from the manifest.

    .OUTPUTS
        [bool] $false only when a path-shaped Target does not exist.

    .EXAMPLE
        Test-WcdTargetPresent -Entry @{ Action = 'CheckPath'; Target = 'C:\Program Files\app' }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Entry
    )

    # A bare command such as 'ms-teams.exe' is resolved by the shell, not by
    # us. Only targets that look like filesystem paths are checked up front.
    if ($Entry.Action -eq 'OpenUrl')     { return $true }
    if ($Entry.Action -eq 'CheckProcess'){ return $true }
    if ([string]$Entry.Target -notmatch '[\\/]') { return $true }

    return (Test-Path -LiteralPath ([string]$Entry.Target))
}

function Invoke-WcdApplicationTarget {
    <#
    .SYNOPSIS
        Runs one Application Target according to its Action.

    .DESCRIPTION
        The single place that knows what each Action means. An Action the manifest
        made up throws, and the caller turns that into a remediation naming the
        valid ones - a manifest typo should say so, not fail silently.

    .PARAMETER Entry
        One Application Target entry from the manifest.

    .OUTPUTS
        None. Throws when the target cannot be run, or is not running for
        CheckProcess.

    .EXAMPLE
        Invoke-WcdApplicationTarget -Entry @{ Action = 'OpenUrl'; Target = 'https://example.com' }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Entry
    )

    switch ($Entry.Action) {
        'Launch'     { Start-Process ([string]$Entry.Target) -ErrorAction Stop }
        'OpenFolder' { Start-Process 'explorer.exe' -ArgumentList ([string]$Entry.Target) -ErrorAction Stop }
        'OpenUrl'    { Open-WcdUrl -Url ([string]$Entry.Target) }
        'CheckPath'  { }   # presence already established by Test-WcdTargetPresent
        'CheckProcess' {
            $running = @(Get-Process -Name @($Entry.Target) -ErrorAction SilentlyContinue)
            if ($running.Count -eq 0) {
                throw ('No matching process running ({0}).' -f (@($Entry.Target) -join ', '))
            }
        }
        default { throw ("Unknown Action '{0}' for step '{1}'." -f $Entry.Action, $Entry.Step) }
    }
}

function Set-WcdApplicationsConfiguration {
    <#
    .SYNOPSIS
        Verifies and opens the Application Targets that apply to this machine.

    .DESCRIPTION
        Walks the already-filtered target list in manifest order, running each
        according to its Action. Adding, removing or reordering an application is a
        manifest edit; this Module never needs to change.

        WinContextDeploy does not install software: targets are verified and, where
        useful, opened for the technician to check by eye. An absent target that is
        declared Optional is a note; an absent required target is a warning naming
        the manifest key to fix.

    .PARAMETER Targets
        Application Target entries to run, already filtered for the current
        Environment, Form Factor and selected Optional Tools by
        Get-WcdApplicationTarget.

    .PARAMETER OpenApps
        When $false, every target is skipped and a single ApplicationsSkip result
        is returned, which the checklist renders as Manual Steps. Defaults to $true.

    .PARAMETER LogPath
        Full path to the log file. Resolved automatically when omitted.

    .PARAMETER ProgressCallback
        Scriptblock invoked at the start and end of each step for progress display.

    .OUTPUTS
        [pscustomobject[]] with Step, Success, Error, Severity and, on a failure,
        RemedyKey and RemedyArgs.

    .EXAMPLE
        $targets = Get-WcdApplicationTarget -Config $config -Environment 'Workstation'
        Set-WcdApplicationsConfiguration -Targets $targets -LogPath 'C:\temp\log.txt'
    #>
    [CmdletBinding()]
    param(
        [object[]]$Targets = @(),
        [bool]$OpenApps = $true,
        [string]$LogPath,
        [scriptblock]$ProgressCallback
    )

    $resolvedLogPath = Resolve-WcdLogPath -CandidatePath $LogPath
    $results = @()
    $moduleName = 'Config-Applications'

    if (-not $OpenApps) {
        Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'Applications: opening declined by the technician.'
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'ApplicationsSkip' -Event 'Start'
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'ApplicationsSkip' -Event 'Finish' -Kind 'success'
        return @([pscustomobject]@{ Step = 'ApplicationsSkip'; Success = $true; Error = ''; Severity = 'INFO' })
    }

    foreach ($entry in @($Targets)) {
        $step = [string]$entry.Step
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey $step -Event 'Start'

        try {
            if (-not (Test-WcdTargetPresent -Entry $entry)) {
                # Absent and declared Optional is a normal outcome on many
                # machines; absent and required is worth a warning.
                $severity = if ($entry.Optional) { 'INFO' } else { 'WARNING' }
                $kind     = if ($entry.Optional) { 'success' } else { 'warning' }
                $detail   = '{0} not found at {1}' -f $entry.Name, $entry.Target

                Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message $detail
                Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey $step -Event 'Finish' -Kind $kind
                $results += [pscustomobject]@{
                    Step       = $step
                    Success    = $true
                    Error      = $detail
                    Severity   = $severity
                    # An Optional target that is simply absent is a normal
                    # outcome, so it gets a note but no call to action.
                    RemedyKey  = if ($entry.Optional) { '' } else { 'TargetMissing' }
                    RemedyArgs = @([string]$entry.Target, [string]$entry.Name)
                }
                continue
            }

            Invoke-WcdApplicationTarget -Entry $entry

            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('{0}: {1} ok.' -f $entry.Name, $entry.Action)
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey $step -Event 'Finish' -Kind 'success'
            $results += [pscustomobject]@{ Step = $step; Success = $true; Error = '' }
        } catch {
            $message = $_.Exception.Message
            # CheckProcess failing means "not running", which is information,
            # not a broken step.
            $severity = if ($entry.Action -eq 'CheckProcess') { 'WARNING' } else { 'ERROR' }
            $kind     = if ($entry.Action -eq 'CheckProcess') { 'warning' } else { 'error' }

            # What the technician should do next depends on why it failed, not
            # on the text Windows happened to put in the exception.
            if (@($script:WcdApplicationActions) -notcontains [string]$entry.Action) {
                $remedyKey  = 'UnknownAction'
                $remedyArgs = @([string]$entry.Action, $step, (@($script:WcdApplicationActions) -join ', '))
            } elseif ($entry.Action -eq 'CheckProcess') {
                $remedyKey  = 'ProcessNotRunning'
                $remedyArgs = @([string]$entry.Name)
            } else {
                $remedyKey  = 'TargetLaunchFailed'
                $remedyArgs = @([string]$entry.Target, [string]$entry.Name)
            }

            Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ('{0}: {1}' -f $entry.Name, $message)
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey $step -Event 'Finish' -Kind $kind
            $results += [pscustomobject]@{
                Step       = $step
                Success    = ($severity -ne 'ERROR')
                Error      = $message
                Severity   = $severity
                RemedyKey  = $remedyKey
                RemedyArgs = $remedyArgs
            }
        }
    }

    return $results
}
