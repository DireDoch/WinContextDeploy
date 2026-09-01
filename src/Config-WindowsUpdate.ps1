# Config-WindowsUpdate.ps1 - failed updates, and a restart Windows is waiting for.
# Entry point: Set-WcdWindowsUpdateStatus. Requires WcdHelpers.ps1.
#
# Report only, and local only. Both Steps read state that is already on the
# machine: no network call, no timeout path, nothing that can hang a run.
#
# Deliberately absent: "are updates pending". That search asks Microsoft over
# the network, takes anywhere from 30 seconds to several minutes, can hang, and
# a freshly imaged machine always has updates pending because the image is
# weeks old - a warning on every run is the one technicians learn to scroll
# past. "An update tried and failed" is the actionable signal.

# A machine re-imaged over an older install carries history that is not about
# this deployment, so only recent history counts.
$script:WcdUpdateHistoryLimit = 50
$script:WcdUpdateHistoryDays = 30

function Get-WcdWindowsUpdateHistory {
    <#
    .SYNOPSIS
        Returns the machine's most recent Windows Update history entries.

    .DESCRIPTION
        Reads the local history through the Windows Update Agent COM object.
        Nothing here searches for updates, so there is no network call and
        nothing to time out.

        The agent is absent or disabled on some managed and stripped images, so
        creating the COM object is wrapped: that reports Available = $false,
        which the Step turns into a note rather than a crash. Availability is
        carried as a property rather than by returning $null, because an empty
        history and an unavailable agent are different answers.

    .PARAMETER Limit
        How many entries to read, most recent first. Defaults to 50.

    .OUTPUTS
        [pscustomobject] with Available and Entries.

    .EXAMPLE
        (Get-WcdWindowsUpdateHistory).Entries | Where-Object { $_.ResultCode -ne 2 }
    #>
    [CmdletBinding()]
    param(
        [int]$Limit = $script:WcdUpdateHistoryLimit
    )

    try {
        $session = New-Object -ComObject 'Microsoft.Update.Session' -ErrorAction Stop
    } catch {
        return [pscustomobject]@{ Available = $false; Entries = @() }
    }

    $searcher = $session.CreateUpdateSearcher()
    $total = [int]$searcher.GetTotalHistoryCount()
    if ($total -le 0) {
        return [pscustomobject]@{ Available = $true; Entries = @() }
    }

    # QueryHistory returns the most recent first, and refuses a count larger
    # than the history actually holds.
    $count = [Math]::Min($Limit, $total)
    return [pscustomobject]@{ Available = $true; Entries = @($searcher.QueryHistory(0, $count)) }
}

function Test-WcdWindowsUpdateRebootPending {
    <#
    .SYNOPSIS
        Reports whether Windows Update is waiting on a restart.

    .DESCRIPTION
        Windows Update writes the RebootRequired key when an installed update
        needs a restart to finish, and removes it once the machine has
        restarted. Reading it needs no elevation and no network.

    .OUTPUTS
        [bool] $true when the RebootRequired key exists.

    .EXAMPLE
        if (Test-WcdWindowsUpdateRebootPending) { 'restart before handover' }
    #>
    [CmdletBinding()]
    param()

    $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    return (Test-Path -LiteralPath $key)
}

function Format-WcdFailedUpdateSummary {
    <#
    .SYNOPSIS
        Renders failed update history entries into one readable sentence.

    .DESCRIPTION
        Names the first few and counts the rest, the same way the Device Manager
        summary does - a checklist row naming twelve updates is a row nobody
        reads. The KB number is already part of the update title Windows
        records, so the title carries it.

    .PARAMETER Updates
        Failed history entries.

    .PARAMETER Limit
        How many to name before counting the rest. Defaults to 3.

    .OUTPUTS
        [string] The summary.

    .EXAMPLE
        Format-WcdFailedUpdateSummary -Updates $failed
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Updates,

        [int]$Limit = 3
    )

    $preview = @($Updates | Select-Object -First $Limit | ForEach-Object {
        $title = [string]$_.Title
        if ([string]::IsNullOrWhiteSpace($title)) { $title = 'Unnamed update' }

        '{0} (HRESULT 0x{1:X8})' -f $title, ([int]$_.HResult)
    })

    $summary = $preview -join ', '
    if (@($Updates).Count -gt $Limit) {
        $summary = '{0}, +{1} more' -f $summary, (@($Updates).Count - $Limit)
    }

    return $summary
}

function Set-WcdWindowsUpdateStatus {
    <#
    .SYNOPSIS
        Reports failed Windows updates and a restart waiting to be applied.

    .DESCRIPTION
        A machine that failed an update during imaging, or that is sitting on an
        unapplied reboot, looks perfectly fine at handover and is not. Two Steps,
        both reading local state only.

        WindowsUpdateHistory reads the recent history and warns about any entry
        that did not succeed, naming the update and its HRESULT. Only the last
        50 entries, and only the last 30 days, count: a machine re-imaged over an
        older install carries history that is not about this deployment.

        WindowsUpdateReboot reads the RebootRequired key. The tool never
        restarts the machine itself - a reboot mid-run would destroy the
        checklist, the history log and the JSON report - so it says so and lets
        the technician do it.

        Report only, and neither Step needs Administrator.

    .PARAMETER LogPath
        Full path to the log file. Resolved automatically when omitted.

    .PARAMETER ProgressCallback
        Scriptblock invoked at the start and end of each step for progress display.

    .OUTPUTS
        [pscustomobject[]] with Step, Success, Severity, Error and optionally
        RemedyKey and RemedyArgs, for WindowsUpdateHistory and
        WindowsUpdateReboot. The reboot Result also carries RebootPending, which
        the checklist uses to fold it into the single restart row.

    .EXAMPLE
        Set-WcdWindowsUpdateStatus -LogPath 'C:\temp\log.txt'
    #>
    [CmdletBinding()]
    param(
        [string]$LogPath,
        [scriptblock]$ProgressCallback
    )

    $resolvedLogPath = Resolve-WcdLogPath -CandidatePath $LogPath
    $moduleName = 'Config-WindowsUpdate'
    $results = @()

    # --- Recent update history -----------------------------------------------
    Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'WindowsUpdateHistory' -Event 'Start'

    try {
        $history = Get-WcdWindowsUpdateHistory -Limit $script:WcdUpdateHistoryLimit

        if (-not $history.Available) {
            $message = 'The Windows Update Agent is not available on this image; the update history could not be read.'
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('Windows Update: {0}' -f $message)
            $results += [pscustomobject]@{
                Step     = 'WindowsUpdateHistory'
                Success  = $true
                Severity = 'INFO'
                Error    = $message
            }
        } else {
            $cutoff = [DateTime]::UtcNow.AddDays(-$script:WcdUpdateHistoryDays)
            # ResultCode 2 is Succeeded. Anything else in recent history is an
            # update that tried and did not get there.
            $failed = @($history.Entries | Where-Object {
                $null -ne $_ -and [int]$_.ResultCode -ne 2 -and ([DateTime]$_.Date) -ge $cutoff
            })

            if ($failed.Count -gt 0) {
                $summary = Format-WcdFailedUpdateSummary -Updates $failed
                $message = 'Windows updates that did not succeed ({0}): {1}' -f $failed.Count, $summary
                Write-WcdLog -Path $resolvedLogPath -Level 'WARNING' -Message ('Windows Update: {0}' -f $message)
                $results += [pscustomobject]@{
                    Step       = 'WindowsUpdateHistory'
                    Success    = $true
                    Severity   = 'WARNING'
                    Error      = $message
                    RemedyKey  = 'WindowsUpdateFailed'
                    RemedyArgs = @()
                }
            } else {
                $message = 'No failed update in the last {0} entries ({1} days).' -f $script:WcdUpdateHistoryLimit, $script:WcdUpdateHistoryDays
                Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('Windows Update: {0}' -f $message)
                $results += [pscustomobject]@{
                    Step     = 'WindowsUpdateHistory'
                    Success  = $true
                    Severity = 'INFO'
                    Error    = $message
                }
            }
        }
    } catch {
        $message = 'The Windows update history could not be read: {0}' -f $_.Exception.Message
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message $message
        $results += [pscustomobject]@{
            Step     = 'WindowsUpdateHistory'
            Success  = $false
            Severity = 'ERROR'
            Error    = $message
        }
    }

    Complete-WcdProgressStep -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'WindowsUpdateHistory' -Results $results

    # --- A restart Windows is waiting for ------------------------------------
    Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'WindowsUpdateReboot' -Event 'Start'

    try {
        if (Test-WcdWindowsUpdateRebootPending) {
            $message = 'An installed update is waiting on a restart.'
            Write-WcdLog -Path $resolvedLogPath -Level 'WARNING' -Message ('Windows Update: {0}' -f $message)
            $results += [pscustomobject]@{
                Step          = 'WindowsUpdateReboot'
                Success       = $true
                Severity      = 'WARNING'
                Error         = $message
                RemedyKey     = 'RebootPending'
                # Read by the checklist, which folds this into the one restart
                # row rather than asking for a second restart of its own.
                RebootPending = $true
            }
        } else {
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'Windows Update: no restart pending.'
            $results += [pscustomobject]@{
                Step          = 'WindowsUpdateReboot'
                Success       = $true
                Severity      = 'INFO'
                Error         = 'No restart pending.'
                RebootPending = $false
            }
        }
    } catch {
        $message = 'The pending-restart state could not be read: {0}' -f $_.Exception.Message
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message $message
        $results += [pscustomobject]@{
            Step     = 'WindowsUpdateReboot'
            Success  = $false
            Severity = 'ERROR'
            Error    = $message
        }
    }

    Complete-WcdProgressStep -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'WindowsUpdateReboot' -Results $results

    return $results
}
