# Config-Applications.ps1 - verifies and opens the Application Targets.
# Entry point: Set-WcdApplicationsConfiguration. Requires WcdHelpers.ps1.
#
# Adding, removing or reordering an application is a manifest edit; nothing in
# this file needs to change for it.

$script:WcdApplicationActions = @('Launch', 'OpenFolder', 'OpenUrl', 'CheckProcess', 'CheckPath', 'CheckWinget')

function Test-WcdWingetAvailable {
    <#
    .SYNOPSIS
        Reports whether winget.exe exists on this machine.

    .DESCRIPTION
        App Installer is absent from LTSC and stripped images, so a CheckWinget
        target cannot be verified there at all. Probed once per run rather than
        once per target, so a missing App Installer reads as one cause instead of
        N identical failures.

    .OUTPUTS
        [bool] $true when winget.exe can be resolved.

    .EXAMPLE
        if (-not (Test-WcdWingetAvailable)) { 'verify by hand' }
    #>
    [CmdletBinding()]
    param()

    return ($null -ne (Get-Command -Name 'winget.exe' -ErrorAction SilentlyContinue))
}

function Test-WcdWingetPackageInstalled {
    <#
    .SYNOPSIS
        Reports whether winget lists a package id as installed.

    .DESCRIPTION
        Verify only: this never installs or upgrades anything. The agreement and
        interactivity flags are required, not polish - a winget that has never
        run otherwise blocks on a source-agreement prompt, and nothing in a
        one-shot run may stop for input. Without --exact a bare name matches
        several packages and the check means nothing.

        Exit code 0 means installed. The 'no applications found' code means
        absent. Any other code means winget itself failed, which throws rather
        than being reported as an absent package.

    .PARAMETER Id
        Exact winget package id, for example 'Microsoft.PowerToys'.

    .OUTPUTS
        [bool] $true when the package is installed.

    .EXAMPLE
        Test-WcdWingetPackageInstalled -Id 'Microsoft.PowerToys'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Id
    )

    $output = & winget.exe list --id $Id --exact --accept-source-agreements --disable-interactivity 2>&1
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) { return $true }
    # APPINSTALLER_CLI_ERROR_NO_APPLICATIONS_FOUND (0x8a150014): not installed.
    if ($exitCode -eq -1978335212) { return $false }

    throw ('winget list failed for {0} (exit {1}): {2}' -f $Id, $exitCode, ((($output | Where-Object { $_ -match '\S' }) -join ' ').Trim()))
}

function Test-WcdTargetPresent {
    <#
    .SYNOPSIS
        Reports whether an Application Target's Target can be found up front.

    .DESCRIPTION
        Only targets that look like filesystem paths are checked here. A bare
        command such as 'ms-teams.exe' is resolved by the shell, and OpenUrl and
        CheckProcess targets are not paths at all, so all three are reported
        present and left for Invoke-WcdApplicationTarget to attempt. A
        CheckWinget target is a package id, so it is asked of winget instead.

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
    # A package id is not a path: winget is the only thing that can answer.
    if ($Entry.Action -eq 'CheckWinget') { return (Test-WcdWingetPackageInstalled -Id ([string]$Entry.Target)) }
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
        'CheckWinget'{ }   # ditto - and this Action never installs anything
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

        CheckWinget targets need winget itself, which some images do not have.
        It is probed once before the loop: absent, that is one warning and every
        CheckWinget entry becomes a Manual Step rather than a failure.

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

    # winget is absent from LTSC and stripped images. Probe once, before the
    # loop: one honest cause and N actionable rows beats N identical failures
    # all pointing back at the same missing App Installer.
    $wingetAvailable = $true
    if (@($Targets | Where-Object { $_.Action -eq 'CheckWinget' }).Count -gt 0) {
        $wingetAvailable = Test-WcdWingetAvailable
        if (-not $wingetAvailable) {
            $wingetDetail = 'winget unavailable - App Installer not provisioned on this image'
            Write-WcdLog -Path $resolvedLogPath -Level 'WARNING' -Message $wingetDetail
            $results += [pscustomobject]@{
                Step       = 'WingetUnavailable'
                Success    = $true
                Error      = $wingetDetail
                Severity   = 'WARNING'
                RemedyKey  = 'WingetMissing'
                RemedyArgs = @()
            }
        }
    }

    foreach ($entry in @($Targets)) {
        $step = [string]$entry.Step
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey $step -Event 'Start'

        if ($entry.Action -eq 'CheckWinget' -and -not $wingetAvailable) {
            # The cause is reported once above; each package is then a Manual
            # Step rather than a package that is genuinely missing. The
            # checklist row names it, so the detail does not repeat the name.
            $detail = 'winget unavailable - verify by hand.'

            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('{0}: {1}' -f $entry.Name, $detail)
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey $step -Event 'Finish' -Kind 'warning'
            $results += [pscustomobject]@{ Step = $step; Success = $true; Error = $detail; Severity = 'MANUAL' }
            continue
        }

        try {
            if (-not (Test-WcdTargetPresent -Entry $entry)) {
                # Absent and declared Optional is a normal outcome on many
                # machines; absent and required is worth a warning.
                $severity = if ($entry.Optional) { 'INFO' } else { 'WARNING' }
                $kind     = if ($entry.Optional) { 'success' } else { 'warning' }
                $detail   = if ($entry.Action -eq 'CheckWinget') {
                    'winget does not list {0} as installed ({1})' -f $entry.Name, $entry.Target
                } else {
                    '{0} not found at {1}' -f $entry.Name, $entry.Target
                }

                Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message $detail
                Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey $step -Event 'Finish' -Kind $kind
                $results += [pscustomobject]@{
                    Step       = $step
                    Success    = $true
                    Error      = $detail
                    Severity   = $severity
                    # An Optional target that is simply absent is a normal
                    # outcome, so it gets a note but no call to action.
                    RemedyKey  = if ($entry.Optional) { '' }
                                 elseif ($entry.Action -eq 'CheckWinget') { 'WingetPackageMissing' }
                                 else { 'TargetMissing' }
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
            } elseif ($entry.Action -eq 'CheckWinget') {
                # Reaching here means winget ran and failed, not that the
                # package is absent - that is handled as a missing target.
                $remedyKey  = 'WingetCheckFailed'
                $remedyArgs = @([string]$entry.Name, [string]$entry.Target)
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
