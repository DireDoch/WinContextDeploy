# Config-Security.ps1 - Windows activation, antivirus and firewall status.
# Entry point: Set-WcdSecurityStatus. Requires WcdHelpers.ps1.
#
# Read-only: three things a technician is supposed to eyeball before a machine
# leaves the bench, none of which this tool changes. An unactivated machine
# shows a watermark days later, an image that shipped with Defender off stays
# off, and a firewall profile disabled during imaging stays disabled - all three
# are silent until someone looks.
#
# No elevation. Every read here is a CIM query or an inbox cmdlet.

# Defender signatures older than this many days are stale enough to warn about.
# A constant rather than a manifest key: nothing suggests it varies by site, and
# the manifest is for values that do.
$script:WcdSignatureAgeWarningDays = 7

function Get-WcdWindowsLicenseProduct {
    <#
    .SYNOPSIS
        Returns the Windows licensing entries that carry a product key.

    .DESCRIPTION
        Thin wrapper over SoftwareLicensingProduct, so the activation check has a
        seam the tests can mock.

        The PartialProductKey filter is not cosmetic. Without it the class
        returns every licensing stub on the machine - dozens of rows for editions
        and add-ons that were never installed - and one Windows install reads as
        several conflicting answers.

    .OUTPUTS
        [object[]] SoftwareLicensingProduct instances with a PartialProductKey.
        Throws when CIM cannot be queried.

    .EXAMPLE
        @(Get-WcdWindowsLicenseProduct).Count
    #>
    [CmdletBinding()]
    param()

    return @(Get-CimInstance -ClassName 'SoftwareLicensingProduct' `
            -Filter "Name like 'Windows%' AND PartialProductKey is not null" -ErrorAction Stop)
}

function Get-WcdDefenderStatus {
    <#
    .SYNOPSIS
        Returns Microsoft Defender's current status.

    .DESCRIPTION
        Thin wrapper over Get-MpComputerStatus, so the antivirus check has a seam
        the tests can mock. The cmdlet ships with the Defender feature; an image
        built without it does not have the command at all, which is why the
        caller treats a missing command as its own answer.

    .OUTPUTS
        [object] The Defender status. Throws when the cmdlet is absent or fails.

    .EXAMPLE
        (Get-WcdDefenderStatus).AMRunningMode   # Normal
    #>
    [CmdletBinding()]
    param()

    return Get-MpComputerStatus -ErrorAction Stop
}

function Get-WcdFirewallProfileState {
    <#
    .SYNOPSIS
        Returns the firewall profiles as they are actually enforced.

    .DESCRIPTION
        Thin wrapper over Get-NetFirewallProfile, so the firewall check has a
        seam the tests can mock.

        -PolicyStore ActiveStore is the whole point of the wrapper. The default
        store is the configured policy - what this machine asked for - and a
        technician asking "is the firewall on" means what Group Policy is
        actually enforcing, which is the active store.

    .OUTPUTS
        [object[]] Profiles with Name and Enabled. Throws when the read fails.

    .EXAMPLE
        Get-WcdFirewallProfileState | Select-Object Name, Enabled
    #>
    [CmdletBinding()]
    param()

    return @(Get-NetFirewallProfile -PolicyStore 'ActiveStore' -ErrorAction Stop)
}

function Get-WcdLicenseStatusInfo {
    <#
    .SYNOPSIS
        Maps a SoftwareLicensingProduct LicenseStatus to a severity and a label.

    .DESCRIPTION
        UNVERIFIED AGAINST HARDWARE. There is no Microsoft Learn page enumerating
        LicenseStatus for SoftwareLicensingProduct; this mapping comes from
        community documentation and has not been spot-checked against
        'slmgr /dlv' on a real machine. Confirm the intermediate values before
        trusting them.

          0  Unlicensed             ERROR
          1  Licensed               OK
          2  OOB Grace              WARNING - initial grace period
          3  OOT Grace              WARNING - out-of-tolerance, the clock moved
          4  Non-Genuine Grace      WARNING
          5  Notification           WARNING - activation nag, not activated
          6  Extended Grace         WARNING

        Anything unrecognised is a warning rather than an assumed pass: a value
        this function has never seen is a machine worth looking at, not a
        machine to wave through.

    .PARAMETER Status
        The LicenseStatus value.

    .OUTPUTS
        [hashtable] with Severity and Label.

    .EXAMPLE
        (Get-WcdLicenseStatusInfo -Status 1).Severity   # INFO
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$Status
    )

    switch ($Status) {
        0 { return @{ Severity = 'ERROR';   Label = 'Windows is not activated (Unlicensed).' } }
        1 { return @{ Severity = 'INFO';    Label = 'Windows is activated.' } }
        2 { return @{ Severity = 'WARNING'; Label = 'Windows is in the initial grace period (OOB Grace).' } }
        3 { return @{ Severity = 'WARNING'; Label = 'Windows is out of tolerance (OOT Grace); the machine clock may have moved.' } }
        4 { return @{ Severity = 'WARNING'; Label = 'Windows reports a non-genuine grace period.' } }
        5 { return @{ Severity = 'WARNING'; Label = 'Windows is in notification state and is not activated.' } }
        6 { return @{ Severity = 'WARNING'; Label = 'Windows is in the extended grace period.' } }
        default { return @{ Severity = 'WARNING'; Label = ('Windows reported an unrecognised LicenseStatus ({0}).' -f $Status) } }
    }
}

function Get-WcdDefenderStatusInfo {
    <#
    .SYNOPSIS
        Turns a Defender status object into a severity and a label.

    .DESCRIPTION
        AMRunningMode is the field that decides whether Defender is even the
        machine's antivirus. 'Passive' means a third-party product owns the
        machine and Defender has stood down; 'EDR Block Mode' means Defender for
        Endpoint. Both are healthy machines, and reporting them as errors would
        be the same mistake as warning about a CAD viewer that is absent because
        the endpoint is a Vdi. So they are Not Applicable, with the mode named so
        the technician can confirm the third-party product is the intended one.

        Only in Normal mode does real-time protection and signature age mean
        anything, and only then are they judged.

    .PARAMETER Status
        A Get-MpComputerStatus result.

    .PARAMETER SignatureAgeWarningDays
        Signature age, in days, past which the machine is warned about.

    .OUTPUTS
        [hashtable] with Severity, Label and, when there is one, RemedyKey.

    .EXAMPLE
        Get-WcdDefenderStatusInfo -Status (Get-WcdDefenderStatus)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Status,

        [int]$SignatureAgeWarningDays = 7
    )

    if ($null -eq $Status) {
        return @{ Severity = 'WARNING'; Label = 'Defender returned no status.'; RemedyKey = 'DefenderUnavailable' }
    }

    $mode = [string]$Status.AMRunningMode
    if ($mode -eq 'Passive' -or $mode -eq 'EDR Block Mode') {
        return @{ Severity = 'NA'
                  Label    = ('Defender is in {0} mode; another antivirus owns this machine.' -f $mode) }
    }

    if (-not $Status.RealTimeProtectionEnabled) {
        return @{ Severity  = 'WARNING'
                  Label     = 'Defender real-time protection is off.'
                  RemedyKey = 'RealTimeProtectionOff' }
    }

    $signatureAge = [int]$Status.AntivirusSignatureAge
    if ($signatureAge -gt $SignatureAgeWarningDays) {
        return @{ Severity   = 'WARNING'
                  Label      = ('Defender signatures are {0} days old.' -f $signatureAge)
                  RemedyKey  = 'AntivirusSignaturesStale'
                  RemedyArgs = @($SignatureAgeWarningDays) }
    }

    return @{ Severity = 'INFO'
              Label    = ('Defender is running, real-time protection on, signatures {0} day(s) old.' -f $signatureAge) }
}

function Set-WcdSecurityStatus {
    <#
    .SYNOPSIS
        Reports Windows activation, antivirus and firewall status.

    .DESCRIPTION
        Three read-only Steps. Nothing here changes the machine and none of it
        needs Administrator.

        Each Step is its own checklist row, because the answers are acted on
        differently: an unactivated machine is a licensing path problem, a
        disabled firewall profile is a policy question, and a passive Defender
        is not a problem at all.

    .PARAMETER LogPath
        Full path to the log file. Resolved automatically when omitted.

    .PARAMETER ProgressCallback
        Scriptblock invoked at the start and end of each step for progress display.

    .OUTPUTS
        [pscustomobject[]] with Step, Success, Severity and Error.

    .EXAMPLE
        Set-WcdSecurityStatus -LogPath 'C:\temp\log.txt'
    #>
    [CmdletBinding()]
    param(
        [string]$LogPath,

        [scriptblock]$ProgressCallback
    )

    $resolvedLogPath = Resolve-WcdLogPath -CandidatePath $LogPath
    $moduleName = 'Config-Security'
    $signatureAgeDays = $script:WcdSignatureAgeWarningDays
    $results = @()

    $results += Invoke-WcdStep -Module $moduleName -Key 'WindowsActivation' `
        -LogPath $resolvedLogPath -ProgressCallback $ProgressCallback `
        -FailureLabel 'Windows activation' -FailureRemedy 'ActivationUnreadable' `
        -Action {
            $products = @(Get-WcdWindowsLicenseProduct)
            if ($products.Count -eq 0) {
                return @{ Severity = 'WARNING'
                          Error    = 'No Windows licensing entry carries a product key, so activation could not be read.'
                          Log      = 'Security: no Windows licensing entry with a product key.' }
            }

            # Several keyed Windows entries on one install is unusual, but when
            # it happens the worst status wins: an unactivated edition must not
            # hide behind a licensed one. Unlicensed beats everything, then
            # anything that is not plainly Licensed.
            $statuses = @($products | ForEach-Object { [int]$_.LicenseStatus })
            $notLicensed = @($statuses | Where-Object { $_ -ne 1 })
            $worstStatus = if ($statuses -contains 0) { 0 }
                           elseif ($notLicensed.Count -gt 0) { $notLicensed[0] }
                           else { 1 }

            $info = Get-WcdLicenseStatusInfo -Status $worstStatus
            return @{ Severity  = $info.Severity
                      Error     = $info.Label
                      RemedyKey = $(if ($info.Severity -eq 'INFO') { '' } else { 'WindowsNotActivated' })
                      Log       = 'Security: {0}' -f $info.Label }
        }

    $results += Invoke-WcdStep -Module $moduleName -Key 'AntivirusStatus' `
        -LogPath $resolvedLogPath -ProgressCallback $ProgressCallback `
        -FailureLabel 'Antivirus status' `
        -OnFailure {
            param($errorRecord)

            # A missing Get-MpComputerStatus and a Defender that is switched off
            # are not the same machine, and must not read as the same row.
            @{ Severity = 'WARNING'
               Success  = $true
               Error    = ('Defender status could not be read: {0}' -f $errorRecord.Exception.Message)
               RemedyKey = 'DefenderUnavailable'
               Log      = 'Security: Defender status could not be read: {0}' -f $errorRecord.Exception.Message }
        } `
        -Action {
            $info = Get-WcdDefenderStatusInfo -Status (Get-WcdDefenderStatus) -SignatureAgeWarningDays $signatureAgeDays
            $fragment = @{ Severity = $info.Severity; Error = $info.Label; Log = 'Security: {0}' -f $info.Label }
            if ($info.ContainsKey('RemedyKey'))  { $fragment['RemedyKey'] = $info.RemedyKey }
            if ($info.ContainsKey('RemedyArgs')) { $fragment['RemedyArgs'] = $info.RemedyArgs }
            return $fragment
        }

    $results += Invoke-WcdStep -Module $moduleName -Key 'FirewallProfiles' `
        -LogPath $resolvedLogPath -ProgressCallback $ProgressCallback `
        -FailureLabel 'Firewall profiles' -FailureRemedy 'FirewallUnreadable' `
        -Action {
            $profiles = @(Get-WcdFirewallProfileState)
            if ($profiles.Count -eq 0) {
                return @{ Severity = 'WARNING'
                          Error    = 'No firewall profile was returned.'
                          Log      = 'Security: no firewall profile returned.' }
            }

            $disabled = @($profiles | Where-Object { -not $_.Enabled } | ForEach-Object { [string]$_.Name })
            if ($disabled.Count -gt 0) {
                $message = 'Firewall disabled on: {0}.' -f ($disabled -join ', ')
                return @{ Severity  = 'WARNING'
                          Error     = $message
                          RemedyKey = 'FirewallProfileOff'
                          Log       = 'Security: {0}' -f $message }
            }

            $message = 'Firewall enabled on all {0} profiles.' -f $profiles.Count
            return @{ Severity = 'INFO'; Error = $message; Log = 'Security: {0}' -f $message }
        }

    return $results
}

function Get-WcdSecurityDescriptor {
    <#
    .SYNOPSIS
        Declares what Config-Security contributes to the run.

    .DESCRIPTION
        Three Steps, three rows. Each one is answered differently, so none of
        them share a row: an unactivated machine and a disabled firewall profile
        go to two different places, and a passive Defender goes nowhere at all.

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
        Get-WcdSecurityDescriptor -ExecutionOptions $options -Config $config -Translations $T
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

    return [pscustomobject]@{
        Name     = 'Config-Security'
        Order    = 95
        RowOrder = 85
        Steps    = @(
            @{ Key = 'WindowsActivation'; Label = 'Windows activation' }
            @{ Key = 'AntivirusStatus';   Label = 'Antivirus' }
            @{ Key = 'FirewallProfiles';  Label = 'Firewall' }
        )
        Rows     = @(
            @{ Label = $Translations.Checklist.Activation; Steps = @('WindowsActivation') }
            @{ Label = $Translations.Checklist.Antivirus;  Steps = @('AntivirusStatus') }
            @{ Label = $Translations.Checklist.Firewall;   Steps = @('FirewallProfiles') }
        )
        Invoke   = {
            param($ctx)

            Set-WcdSecurityStatus -LogPath $ctx.LogPath -ProgressCallback $ctx.ProgressCallback
        }
    }
}
