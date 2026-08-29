<#
.SYNOPSIS
    Verifies and opens the Application Targets declared in the manifest.

.DESCRIPTION
    Walks the Applications list from WinContextDeploy.psd1 in order, running
    each entry according to its Action. Adding, removing or reordering an
    application is a manifest edit; this module never needs to change.

    WinContextDeploy does not install software. Targets are verified and, where
    useful, opened for the technician to check by eye.

    Requires WcdHelpers.ps1 to be dot-sourced first.

.PARAMETER Targets
    Application Target entries to run, already filtered for the current
    Environment and selected optional tools by Get-WcdApplicationTarget.

.PARAMETER OpenApps
    When $false, every target is skipped and a single ApplicationsSkip result
    is returned. Defaults to $true.

.PARAMETER LogPath
    Full path to the log file. Resolved automatically when omitted.

.PARAMETER ProgressCallback
    Scriptblock invoked at the start and end of each step for progress display.

.OUTPUTS
    [pscustomobject[]] with Step, Success, Error and Severity.

.EXAMPLE
    $targets = Get-WcdApplicationTarget -Config $config -Environment 'Workstation'
    Set-WcdApplicationsConfiguration -Targets $targets -LogPath 'C:\temp\log.txt'
#>

function Test-WcdTargetPresent {
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
                $results += [pscustomobject]@{ Step = $step; Success = $true; Error = $detail; Severity = $severity }
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

            Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ('{0}: {1}' -f $entry.Name, $message)
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey $step -Event 'Finish' -Kind $kind
            $results += [pscustomobject]@{
                Step     = $step
                Success  = ($severity -ne 'ERROR')
                Error    = $message
                Severity = $severity
            }
        }
    }

    return $results
}
