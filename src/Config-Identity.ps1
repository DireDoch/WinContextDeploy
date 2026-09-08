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

# --- The clock, which a domain join depends on -------------------------------
# Kerberos rejects an authentication attempt when the client's clock is more
# than five minutes from the domain controller's - the default MaxTolerance,
# and not generous. A freshly imaged machine with a dead CMOS battery, a wrong
# timezone or a Windows Time service that never found a source joins the domain
# and then fails to authenticate, in a way that looks like anything except a
# clock problem.

# A successful sync older than this is worth mentioning. A machine straight off
# the bench syncs within minutes of first boot; a week of silence means the
# Windows Time service is not reaching anything.
$script:WcdTimeSyncWarningDays = 7

function Get-WcdMachineTimeZone {
    <#
    .SYNOPSIS
        Returns the machine's current timezone.

    .DESCRIPTION
        Thin wrapper over Get-TimeZone, so the Step has a seam the tests can mock.

    .OUTPUTS
        The timezone, with Id and DisplayName. Throws when it cannot be read.

    .EXAMPLE
        (Get-WcdMachineTimeZone).Id   # Eastern Standard Time
    #>
    [CmdletBinding()]
    param()

    return (Get-TimeZone -ErrorAction Stop)
}

function Get-WcdTimeStatusOutput {
    <#
    .SYNOPSIS
        Returns the raw lines of w32tm /query /status.

    .DESCRIPTION
        Thin wrapper over w32tm.exe, so the Step has a seam the tests can mock.
        Querying needs no elevation.

        Deliberately only /query. Running 'w32tm /resync /force' is a fix rather
        than a check, and it fails noisily on a machine with no reachable time
        source - which is precisely the machine this Step exists to find.

    .OUTPUTS
        [string[]] The command's output lines.

    .EXAMPLE
        Get-WcdTimeStatusOutput | Select-Object -First 3
    #>
    [CmdletBinding()]
    param()

    return @(& 'w32tm.exe' '/query' '/status' 2>&1 | ForEach-Object { [string]$_ })
}

function ConvertFrom-WcdTimeStatus {
    <#
    .SYNOPSIS
        Parses w32tm /query /status into the two fields that matter.

    .DESCRIPTION
        The output is plain text and localized: on a French Windows every field
        label is in French. So nothing here matches a label. The output is a
        fixed sequence of "label<separator>value" lines - leap indicator,
        stratum, precision, root delay, root dispersion, reference id, last
        successful sync time, source, poll interval - and the value is taken by
        its position in that sequence.

        Everything after the first colon is the value, which is why the French
        " : " separator and the English ": " both work, and why a value holding
        its own colons - a timestamp, an IP - survives.

        A block that does not parse is its own answer. A machine whose w32tm
        output this cannot read is a machine to look at by hand, not a machine
        with a bad clock, and the two must not print the same sentence.

    .PARAMETER Lines
        The output of Get-WcdTimeStatusOutput.

    .OUTPUTS
        [hashtable] with Parsed, Source, LastSync and NeverSynced.

    .EXAMPLE
        (ConvertFrom-WcdTimeStatus -Lines $lines).Source   # Local CMOS Clock
    #>
    [CmdletBinding()]
    param(
        [string[]]$Lines = @()
    )

    $values = @()
    foreach ($line in @($Lines)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line -split ':\s*', 2
        if ($parts.Count -ne 2) { continue }
        $values += [string]$parts[1].Trim()
    }

    # Position 6 is the last successful sync, 7 the source. Fewer fields than
    # that means the command did not answer with a status block at all.
    if ($values.Count -lt 8) {
        return @{ Parsed = $false; Source = ''; LastSync = $null; NeverSynced = $false }
    }

    $lastSyncText = $values[6]
    $source = $values[7]

    if ([string]::IsNullOrWhiteSpace($source)) {
        return @{ Parsed = $false; Source = ''; LastSync = $null; NeverSynced = $false }
    }

    # w32tm formats the timestamp in the machine's own locale, so the machine's
    # own culture reads it. Invariant is the fallback, not the first try.
    $lastSync = $null
    foreach ($culture in @([cultureinfo]::CurrentCulture, [cultureinfo]::InvariantCulture)) {
        try {
            $lastSync = [datetime]::Parse($lastSyncText, $culture)
            break
        } catch {
        }
    }

    # A block that parsed but reports no timestamp is a machine that has never
    # synced - 'unspecified', or whatever that word is in the machine's language.
    return @{ Parsed      = $true
              Source      = $source
              LastSync    = $lastSync
              NeverSynced = ($null -eq $lastSync) }
}

function Get-WcdTimeZoneInfo {
    <#
    .SYNOPSIS
        Compares the machine's timezone against the manifest's expected one.

    .DESCRIPTION
        With no expected zone declared, the current one is reported and nothing
        is judged: a fleet spanning several timezones must not collect a false
        warning on every machine outside the head office.

    .PARAMETER TimeZone
        What Get-WcdMachineTimeZone returned.

    .PARAMETER Expected
        The manifest's expected zone Id, or empty when it declares none.

    .OUTPUTS
        [hashtable] with Severity, Label and, on a mismatch, RemedyKey.

    .EXAMPLE
        Get-WcdTimeZoneInfo -TimeZone (Get-WcdMachineTimeZone) -Expected 'Eastern Standard Time'
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        $TimeZone,

        [string]$Expected
    )

    if ($null -eq $TimeZone) {
        return @{ Severity = 'WARNING'; Label = 'The machine timezone could not be read.' }
    }

    $id = [string]$TimeZone.Id
    $display = [string]$TimeZone.DisplayName
    $current = if ([string]::IsNullOrWhiteSpace($display)) { $id } else { '{0} ({1})' -f $id, $display }

    if ([string]::IsNullOrWhiteSpace($Expected)) {
        return @{ Severity = 'INFO'; Label = ('Timezone is {0}.' -f $current) }
    }

    if ($id -eq $Expected) {
        return @{ Severity = 'INFO'; Label = ('Timezone is {0}, as the manifest expects.' -f $current) }
    }

    return @{ Severity  = 'WARNING'
              Label     = ('Timezone is {0}; the manifest expects {1}.' -f $current, $Expected)
              RemedyKey = 'TimeZoneMismatch' }
}

function Get-WcdTimeSyncInfo {
    <#
    .SYNOPSIS
        Turns a parsed w32tm status into a severity and a label.

    .DESCRIPTION
        A source of 'Local CMOS Clock' means the Windows Time service never
        found a time source and the machine is running off its own hardware
        clock. On a machine that is domain-joined or about to be, that is the
        clock problem this Step exists to find. On a standalone machine it is
        normal, so it is reported without being judged.

        The source name is localized on a localized Windows, so the match is on
        'CMOS' - an acronym that survives translation - rather than on the whole
        English phrase.

        No offset is measured. 'w32tm /stripchart' gives a real number but needs
        the domain reachable and takes seconds per sample, which turns a
        checklist row into a network test. The source and the last sync answer
        the question that matters at bring-up.

    .PARAMETER Status
        A hashtable from ConvertFrom-WcdTimeStatus.

    .PARAMETER DomainJoined
        Whether the machine is on a domain, or about to be joined this run.

    .PARAMETER WarningDays
        A successful sync older than this many days is warned about.

    .PARAMETER Now
        Taken as the current time, so the age is testable. Defaults to now.

    .OUTPUTS
        [hashtable] with Severity, Label and, when there is one, RemedyKey.

    .EXAMPLE
        Get-WcdTimeSyncInfo -Status $status -DomainJoined $true
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Status,

        [bool]$DomainJoined = $false,

        [int]$WarningDays = 7,

        [datetime]$Now = [datetime]::Now
    )

    if (-not $Status.Parsed) {
        return @{ Severity  = 'WARNING'
                  Label     = 'The Windows Time status could not be parsed, so the clock was not checked.'
                  RemedyKey = 'TimeSyncUnparseable' }
    }

    $source = [string]$Status.Source

    if ($source -match 'CMOS') {
        if ($DomainJoined) {
            return @{ Severity  = 'WARNING'
                      Label     = ('The Windows Time service has no time source; the clock is running off "{0}".' -f $source)
                      RemedyKey = 'TimeSourceCmos' }
        }

        return @{ Severity = 'INFO'
                  Label    = ('The clock is running off "{0}". This machine is not on a domain, so nothing depends on it yet.' -f $source) }
    }

    if ($Status.NeverSynced) {
        return @{ Severity  = 'WARNING'
                  Label     = ('The clock has never synced successfully with "{0}".' -f $source)
                  RemedyKey = 'TimeNeverSynced' }
    }

    $age = $Now - [datetime]$Status.LastSync
    if ($age.TotalDays -gt $WarningDays) {
        return @{ Severity  = 'WARNING'
                  Label     = ('The clock last synced with "{0}" {1:N0} days ago.' -f $source, $age.TotalDays)
                  RemedyKey = 'TimeNeverSynced' }
    }

    return @{ Severity = 'INFO'
              Label    = ('The clock syncs with "{0}", last successful sync {1}.' -f $source, ([datetime]$Status.LastSync).ToString('yyyy-MM-dd HH:mm')) }
}

function Test-WcdDomainJoined {
    <#
    .SYNOPSIS
        Reports whether the machine is currently a domain member.

    .DESCRIPTION
        Thin wrapper over Win32_ComputerSystem, so the Step has a seam the tests
        can mock. A read that fails answers $false rather than throwing: the
        clock check degrades to reporting rather than judging, which is the
        safer half of the answer.

    .OUTPUTS
        [bool] $true when the machine is on a domain.

    .EXAMPLE
        Test-WcdDomainJoined
    #>
    [CmdletBinding()]
    param()

    try {
        return [bool](Get-CimInstance -ClassName 'Win32_ComputerSystem' -ErrorAction Stop).PartOfDomain
    } catch {
        return $false
    }
}

function Set-WcdClockStatus {
    <#
    .SYNOPSIS
        Reports the timezone and the Windows Time sync state.

    .DESCRIPTION
        Two read-only Steps, in the Module that already owns the domain
        conversation, because that is what they exist to protect: the tool
        already asks whether to join the domain, so it should be able to say
        whether the machine's clock can survive it.

        Neither Step needs elevation and neither changes anything - not the
        timezone, and not the time service.

    .PARAMETER ExpectedTimeZone
        The manifest's expected zone Id, or empty when it declares none.

    .PARAMETER JoinDomain
        Whether this run is about to join the domain. Together with current
        membership, this is what makes a CMOS clock source a warning.

    .PARAMETER LogPath
        Full path to the log file. Resolved automatically when omitted.

    .PARAMETER ProgressCallback
        Scriptblock invoked at the start and end of each step for progress display.

    .OUTPUTS
        [pscustomobject[]] with Step, Success, Severity and Error.

    .EXAMPLE
        Set-WcdClockStatus -ExpectedTimeZone 'Eastern Standard Time' -LogPath 'C:\temp\log.txt'
    #>
    [CmdletBinding()]
    param(
        [string]$ExpectedTimeZone,

        [bool]$JoinDomain = $false,

        [string]$LogPath,

        [scriptblock]$ProgressCallback
    )

    $resolvedLogPath = Resolve-WcdLogPath -CandidatePath $LogPath
    $moduleName = 'Config-Identity'
    $expected = $ExpectedTimeZone
    $warningDays = $script:WcdTimeSyncWarningDays
    $wantsJoin = $JoinDomain
    $results = @()

    $results += Invoke-WcdStep -Module $moduleName -Key 'TimeZone' `
        -LogPath $resolvedLogPath -ProgressCallback $ProgressCallback `
        -FailureLabel 'Timezone' -FailureRemedy 'TimeZoneUnreadable' `
        -Action {
            $info = Get-WcdTimeZoneInfo -TimeZone (Get-WcdMachineTimeZone) -Expected $expected
            $fragment = @{ Severity = $info.Severity; Error = $info.Label; Log = 'Identity: {0}' -f $info.Label }
            if ($info.ContainsKey('RemedyKey')) { $fragment['RemedyKey'] = $info.RemedyKey }
            return $fragment
        }

    $results += Invoke-WcdStep -Module $moduleName -Key 'TimeSync' `
        -LogPath $resolvedLogPath -ProgressCallback $ProgressCallback `
        -FailureLabel 'Time sync' -FailureRemedy 'TimeSyncUnparseable' `
        -Action {
            $domainJoined = $wantsJoin -or (Test-WcdDomainJoined)
            $status = ConvertFrom-WcdTimeStatus -Lines (Get-WcdTimeStatusOutput)
            $info = Get-WcdTimeSyncInfo -Status $status -DomainJoined $domainJoined -WarningDays $warningDays

            $fragment = @{ Severity = $info.Severity; Error = $info.Label; Log = 'Identity: {0}' -f $info.Label }
            if ($info.ContainsKey('RemedyKey')) { $fragment['RemedyKey'] = $info.RemedyKey }
            return $fragment
        }

    return $results
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

function Get-WcdIdentityDescriptor {
    <#
    .SYNOPSIS
        Declares what Config-Identity contributes to the run.

    .DESCRIPTION
        The clock Steps always run: the tool asks whether to join the domain,
        so it should always be able to say whether the machine's clock can
        survive it. The identity Steps only exist when the technician asked for
        them, and a run that declined both still runs the Module for the clock.

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
        Get-WcdIdentityDescriptor -ExecutionOptions $options -Config $config -Translations $T
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

    # Declining is a choice, not a filter, so the rows stay Manual Steps rather
    # than Not Applicable - which also lets a fleet-wide report show which
    # machines are still unnamed.
    $wantsRename = -not [string]::IsNullOrWhiteSpace([string]$ExecutionOptions.NewComputerName)
    $wantsJoin = [bool]$ExecutionOptions.JoinDomain

    return [pscustomobject]@{
        Name     = 'Config-Identity'
        Order    = 10
        RowOrder = 10
        Steps    = @(
            @{ Key = 'TimeZone';     Label = 'Timezone' }
            @{ Key = 'TimeSync';     Label = 'Time sync' }
            @{ Key = 'ComputerName'; Label = 'Computer name'; Planned = $wantsRename }
            @{ Key = 'DomainJoin';   Label = 'Domain join';   Planned = $wantsJoin }
        )
        Rows     = @(
            @{ Label = $Translations.Checklist.TimeZone; Steps = @('TimeZone') }
            @{ Label = $Translations.Checklist.TimeSync; Steps = @('TimeSync') }
            @{ Label = $Translations.Checklist.ComputerName; Steps = @('ComputerName')
               MissingKind = 'manual'; MissingDetail = $Translations.IdentityManualDetail }
            @{ Label = $Translations.Checklist.DomainJoin;   Steps = @('DomainJoin')
               MissingKind = 'manual'; MissingDetail = $Translations.IdentityManualDetail }
        )
        Invoke   = {
            param($ctx)

            $domainName = if ($null -ne $ctx.DomainTarget) { [string]$ctx.DomainTarget.Name } else { '' }
            $ouPath = if ($null -ne $ctx.DomainTarget) { [string]$ctx.DomainTarget.OUPath } else { '' }

            $expectedZone = ''
            if ($null -ne $ctx.Config -and $ctx.Config.ContainsKey('TimeZone')) {
                $expectedZone = [string]$ctx.Config['TimeZone']
            }

            $results = @(Set-WcdClockStatus -ExpectedTimeZone $expectedZone `
                -JoinDomain $ctx.ExecutionOptions.JoinDomain `
                -LogPath $ctx.LogPath -ProgressCallback $ctx.ProgressCallback)

            $results += Set-WcdMachineIdentity `
                -NewComputerName $ctx.ExecutionOptions.NewComputerName `
                -JoinDomain $ctx.ExecutionOptions.JoinDomain `
                -DomainName $domainName `
                -OUPath $ouPath `
                -Elevated $ctx.Elevated `
                -PromptMessage ($ctx.Translations.CredentialPrompt -f $domainName) `
                -LogPath $ctx.LogPath -ProgressCallback $ctx.ProgressCallback

            return $results
        }
    }
}