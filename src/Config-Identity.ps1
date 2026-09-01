# Config-Identity.ps1 - the computer name, and domain membership.
# Entry point: Set-WcdMachineIdentity. Requires WcdHelpers.ps1.
#
# Nothing here restarts the machine. A reboot mid-run would destroy the
# checklist, the history log and the JSON report, which are the entire point of
# the tool; the technician restarts once they have read the diagnostic.
#
# No credential is ever logged, reported, or written anywhere. It exists only as
# the PSCredential the technician typed, for the length of one call.

function Invoke-WcdRenameComputer {
    <#
    .SYNOPSIS
        Renames the machine, without restarting it.

    .DESCRIPTION
        Thin wrapper over Rename-Computer, so the tests have a seam to mock and
        never rename the machine running them. -Restart is deliberately never
        passed: see the file header.

    .PARAMETER NewName
        The new computer name, already validated by Test-WcdComputerName.

    .OUTPUTS
        None. Throws when the rename fails.

    .EXAMPLE
        Invoke-WcdRenameComputer -NewName 'POSTE-01'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$NewName
    )

    Rename-Computer -NewName $NewName -Force -ErrorAction Stop
}

function Invoke-WcdAddComputer {
    <#
    .SYNOPSIS
        Joins the machine to a domain, optionally renaming it in the same call.

    .DESCRIPTION
        Thin wrapper over Add-Computer, so the tests have a seam to mock and
        never join the machine running them.

        Add-Computer takes -NewName, so renaming and joining is one call and one
        restart rather than two of each. -Restart is deliberately never passed:
        see the file header.

    .PARAMETER DomainName
        The domain to join, from the manifest.

    .PARAMETER Credential
        The technician's own domain account, from Get-WcdJoinCredential. Never
        logged or stored.

    .PARAMETER NewName
        New computer name to apply in the same call. Omit to keep the current one.

    .PARAMETER OUPath
        Organisational unit to create the account in. Omit for the domain default.

    .OUTPUTS
        None. Throws when the join fails.

    .EXAMPLE
        Invoke-WcdAddComputer -DomainName 'corp.example.com' -Credential $credential -NewName 'POSTE-01'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DomainName,

        [Parameter(Mandatory)]
        [pscredential]$Credential,

        [string]$NewName,

        [string]$OUPath
    )

    $arguments = @{
        DomainName  = $DomainName
        Credential  = $Credential
        Force       = $true
        ErrorAction = 'Stop'
    }
    if (-not [string]::IsNullOrWhiteSpace($NewName)) { $arguments['NewName'] = $NewName }
    if (-not [string]::IsNullOrWhiteSpace($OUPath))  { $arguments['OUPath'] = $OUPath }

    Add-Computer @arguments
}

function Get-WcdJoinCredential {
    <#
    .SYNOPSIS
        Asks the technician for the domain account to join with.

    .DESCRIPTION
        Thin wrapper over Get-Credential, so the tests have a seam to mock and no
        dialog opens during a test run.

        The credential is prompted for at the moment of joining and never comes
        from the manifest: the manifest is committed, shared, and frequently
        lives on a USB key, so a plaintext join account in it is a domain-wide
        problem rather than a local one.

    .PARAMETER Message
        Text shown in the credential dialog, from the caller's $T table.

    .OUTPUTS
        [pscredential], or $null when the technician cancels the dialog.

    .EXAMPLE
        $credential = Get-WcdJoinCredential -Message 'Domain account to join corp.example.com'
    #>
    [CmdletBinding()]
    param(
        [string]$Message = ''
    )

    return (Get-Credential -Message $Message)
}

function Set-WcdMachineIdentity {
    <#
    .SYNOPSIS
        Applies the chosen computer name and domain membership.

    .DESCRIPTION
        Naming the machine and joining it to the domain are the two steps whose
        omission is most obvious to the user and least obvious to the technician
        who has moved on. Both are applied here, and neither takes effect until
        the machine restarts - which this never does.

        Asking for both is one Add-Computer call, not a rename followed by a
        join, so it is one operation and one restart. Both Steps then report the
        outcome of that single call.

        Nothing is attempted that was not asked for: a run that chose neither
        produces no Result at all, and the checklist reports both as Manual Steps.

        Both cmdlets need Administrator. Unelevated, nothing is attempted and no
        credential is asked for - the Steps report as needing elevation rather
        than as failures, matching the power Steps.

    .PARAMETER NewComputerName
        The new name, or empty to leave the machine's name alone.

    .PARAMETER JoinDomain
        Whether to join the domain. Defaults to $false.

    .PARAMETER DomainName
        The domain to join, from the manifest's Domain.Name.

    .PARAMETER OUPath
        Organisational unit for the machine account, from the manifest's
        Domain.OUPath. Optional.

    .PARAMETER Elevated
        Whether the run holds Administrator rights. Both cmdlets need them, so
        when $false nothing is attempted and both Steps report as needing
        elevation. Defaults to $true.

    .PARAMETER CurrentName
        The machine's current name, used to recognise a rename that would change
        nothing. Defaults to %COMPUTERNAME%.

    .PARAMETER PromptMessage
        Text shown in the credential dialog, from the caller's $T table.

    .PARAMETER LogPath
        Full path to the log file. Resolved automatically when omitted.

    .PARAMETER ProgressCallback
        Scriptblock invoked at the start and end of each step for progress display.

    .OUTPUTS
        [pscustomobject[]] with Step, Success, Severity, Error and optionally
        RemedyKey, RemedyArgs and Applied, for ComputerName and DomainJoin - each
        present only when it was asked for. Applied marks a Step that actually
        changed the machine, and so needs a restart to take effect.

    .EXAMPLE
        Set-WcdMachineIdentity -NewComputerName 'POSTE-01' -LogPath 'C:\temp\log.txt'

    .EXAMPLE
        # One call, one restart
        Set-WcdMachineIdentity -NewComputerName 'POSTE-01' -JoinDomain $true -DomainName 'corp.example.com'
    #>
    [CmdletBinding()]
    param(
        [string]$NewComputerName,

        [bool]$JoinDomain = $false,

        [string]$DomainName,

        [string]$OUPath,

        [bool]$Elevated = $true,

        [string]$CurrentName = $env:COMPUTERNAME,

        [string]$PromptMessage = '',

        [string]$LogPath,

        [scriptblock]$ProgressCallback
    )

    $resolvedLogPath = Resolve-WcdLogPath -CandidatePath $LogPath
    $moduleName = 'Config-Identity'
    $results = @()

    $wantsRename = -not [string]::IsNullOrWhiteSpace($NewComputerName)
    $wantsJoin = $JoinDomain -and -not [string]::IsNullOrWhiteSpace($DomainName)
    if (-not $wantsRename -and -not $wantsJoin) { return $results }

    # Both cmdlets need Administrator. Unelevated, attempt nothing and ask for no
    # credential: a raw access-denied from Add-Computer tells the technician far
    # less than the row saying to relaunch elevated.
    if (-not $Elevated) {
        $requested = @()
        if ($wantsRename) { $requested += @{ Step = 'ComputerName'; Cmdlet = 'Rename-Computer' } }
        if ($wantsJoin)   { $requested += @{ Step = 'DomainJoin';   Cmdlet = 'Add-Computer' } }

        foreach ($entry in $requested) {
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey $entry.Step -Event 'Start'
            $message = '{0} requires Administrator.' -f $entry.Cmdlet
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('Identity: {0}' -f $message)
            $results += [pscustomobject]@{
                Step      = [string]$entry.Step
                Success   = $true
                Severity  = 'WARNING'
                Error     = $message
                RemedyKey = 'RequiresAdmin'
            }
            Complete-WcdProgressStep -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey ([string]$entry.Step) -Results $results
        }

        return $results
    }

    # --- The name, checked before anything is called -------------------------
    if ($wantsRename) {
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'ComputerName' -Event 'Start'

        $reason = Test-WcdComputerName -Name $NewComputerName -CurrentName $CurrentName

        if ($reason -eq 'Unchanged') {
            # Not a fault, and not worth a call: the machine already has the name
            # the technician typed. Say so and carry on to the join.
            $wantsRename = $false
            $message = 'Already named {0}; nothing to change.' -f $CurrentName
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('Identity: {0}' -f $message)
            $results += [pscustomobject]@{
                Step     = 'ComputerName'
                Success  = $true
                Severity = 'INFO'
                Error    = $message
            }
            Complete-WcdProgressStep -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'ComputerName' -Results $results
        } elseif ($reason -ne '') {
            $wantsRename = $false
            $message = 'The computer name "{0}" was refused: {1}.' -f $NewComputerName, $reason
            Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ('Identity: {0}' -f $message)
            $results += [pscustomobject]@{
                Step       = 'ComputerName'
                Success    = $false
                Severity   = 'ERROR'
                Error      = $message
                RemedyKey  = 'ComputerNameInvalid'
                RemedyArgs = @($NewComputerName)
            }
            Complete-WcdProgressStep -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'ComputerName' -Results $results
        }
    }

    # --- The credential, asked for only when there is a join to make ---------
    $credential = $null
    if ($wantsJoin) {
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'DomainJoin' -Event 'Start'

        $credential = Get-WcdJoinCredential -Message $PromptMessage
        if ($null -eq $credential) {
            # Cancelling the dialog cancels the join, not the rename: a name the
            # technician asked for must not vanish with it.
            $wantsJoin = $false
            $message = 'The credential dialog was cancelled, so the domain join was not attempted.'
            Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ('Identity: {0}' -f $message)
            $results += [pscustomobject]@{
                Step      = 'DomainJoin'
                Success   = $false
                Severity  = 'ERROR'
                Error     = $message
                RemedyKey = 'JoinCancelled'
            }
            Complete-WcdProgressStep -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'DomainJoin' -Results $results
        }
    }

    if (-not $wantsRename -and -not $wantsJoin) { return $results }

    # --- One call, one restart -----------------------------------------------
    # Add-Computer takes -NewName, so choosing both is a single operation. The
    # steps that were asked for all report the outcome of that one call.
    $appliedSteps = @()
    if ($wantsRename) { $appliedSteps += 'ComputerName' }
    if ($wantsJoin)   { $appliedSteps += 'DomainJoin' }

    try {
        if ($wantsJoin) {
            # Invoke-WcdAddComputer drops an empty NewName or OUPath, so the
            # rename-or-not branch is one argument, not a second hashtable.
            $nameArgument = if ($wantsRename) { $NewComputerName } else { '' }
            Invoke-WcdAddComputer -DomainName $DomainName -Credential $credential `
                -NewName $nameArgument -OUPath $OUPath

            $message = if ($wantsRename) {
                'Joined {0} and renamed to {1}. Both take effect after a restart.' -f $DomainName, $NewComputerName
            } else {
                'Joined {0}. Takes effect after a restart.' -f $DomainName
            }
        } else {
            Invoke-WcdRenameComputer -NewName $NewComputerName
            $message = 'Renamed to {0}. Takes effect after a restart.' -f $NewComputerName
        }

        Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('Identity: {0}' -f $message)
        foreach ($step in $appliedSteps) {
            $results += [pscustomobject]@{
                Step     = $step
                Success  = $true
                Severity = 'INFO'
                Error    = $message
                # Only these earn the checklist's restart row: a no-op rename
                # succeeded without changing anything to restart for.
                Applied  = $true
            }
        }
    } catch {
        # The exception text is the machine's, never the credential's: nothing
        # here echoes what the technician typed.
        $message = $_.Exception.Message
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ('Identity: {0}' -f $message)
        foreach ($step in $appliedSteps) {
            $results += [pscustomobject]@{
                Step      = $step
                Success   = $false
                Severity  = 'ERROR'
                Error     = $message
                RemedyKey = if ($step -eq 'DomainJoin') { 'DomainJoinFailed' } else { 'ComputerNameFailed' }
            }
        }
    }

    foreach ($step in $appliedSteps) {
        Complete-WcdProgressStep -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey $step -Results $results
    }

    return $results
}
