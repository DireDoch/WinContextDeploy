# Config-Firmware.ps1 - the boot mode the machine came up in, and Secure Boot.
# Entry point: Set-WcdFirmwareStatus. Requires WcdHelpers.ps1.
#
# Read only: both Steps report what firmware was set to before the image landed
# and neither changes it. Boot mode and Secure Boot decide whether a machine can
# run Windows 11 at all and whether it survives the next upgrade, and both are
# invisible from the desktop - which is how they get found six months later.
#
# Kept out of Config-BitLocker for the reason that Module was kept out of
# Config-Disk: FirmwareMode needs no elevation and no particular edition, and
# must keep reporting on a non-elevated run rather than being dragged into a
# half-elevated Module.

function Get-WcdFirmwareType {
    <#
    .SYNOPSIS
        Returns the boot mode Windows came up in.

    .DESCRIPTION
        Thin wrapper over $env:firmware_type, so the Step has a seam the tests
        can mock. Windows sets the variable itself; reading it needs no
        elevation and does not touch Confirm-SecureBootUEFI, which is why this
        runs first and why the Secure Boot Step can lean on its answer.

    .OUTPUTS
        [string] 'UEFI', 'Legacy', or empty when Windows set nothing.

    .EXAMPLE
        Get-WcdFirmwareType   # UEFI
    #>
    [CmdletBinding()]
    param()

    return [string]$env:firmware_type
}

function Get-WcdSecureBootState {
    <#
    .SYNOPSIS
        Returns whether Secure Boot is enabled.

    .DESCRIPTION
        Thin wrapper over Confirm-SecureBootUEFI, so the Step has a seam the
        tests can mock. An absent cmdlet returns $null rather than throwing -
        that is a state to report, the same way Get-WcdTpmStatus treats a
        missing Get-Tpm.

        Everything else the cmdlet does wrong is left to throw, because the
        caller has to tell those cases apart: it needs Administrator, and it
        raises "Cmdlet not supported on this platform" on a machine that booted
        legacy BIOS.

    .OUTPUTS
        [bool] when the cmdlet answered, or $null when it is unavailable.
        Throws when the cmdlet refuses.

    .EXAMPLE
        Get-WcdSecureBootState   # True
    #>
    [CmdletBinding()]
    param()

    if (-not (Get-Command -Name 'Confirm-SecureBootUEFI' -ErrorAction SilentlyContinue)) {
        return $null
    }

    return [bool](Confirm-SecureBootUEFI -ErrorAction Stop)
}

function Get-WcdSecureBootFailureInfo {
    <#
    .SYNOPSIS
        Classifies why Confirm-SecureBootUEFI refused.

    .DESCRIPTION
        The cmdlet has more failure shapes than most, and each is a different
        sentence to the technician:

        - Access denied. It needs Administrator. Reported as needing elevation,
          not as a failed Step, matching the power Steps.
        - Not supported on this platform. On a machine that booted legacy BIOS
          this is not an error, it is the answer, and the FirmwareMode Step
          above already gave it. Not Applicable, pointing at that row.
        - The same exception on a UEFI machine means UEFI firmware without
          Secure Boot support. The exception text does not distinguish the two,
          so the detail says which reading the boot mode supports rather than
          guessing.

    .PARAMETER Message
        The exception message from Confirm-SecureBootUEFI.

    .PARAMETER FirmwareType
        What Get-WcdFirmwareType reported, which is what tells the last two
        cases apart.

    .OUTPUTS
        [hashtable] with Severity, Label and, when there is one, RemedyKey.

    .EXAMPLE
        Get-WcdSecureBootFailureInfo -Message 'Cmdlet not supported on this platform.' -FirmwareType 'Legacy'
    #>
    [CmdletBinding()]
    param(
        [string]$Message,

        [string]$FirmwareType
    )

    if ($Message -match 'Access (was )?denied|proper privileges') {
        return @{ Severity  = 'WARNING'
                  Label     = 'Secure Boot could not be read without Administrator.'
                  RemedyKey = 'RequiresAdmin' }
    }

    if ($Message -match 'not supported on this platform') {
        if ($FirmwareType -eq 'Legacy') {
            return @{ Severity = 'NA'
                      Label    = 'Secure Boot does not apply: this machine booted legacy BIOS, as the boot mode row says.' }
        }

        # Same exception text, different machine. Saying which is which without
        # being able to tell them apart would be a guess printed as a fact.
        return @{ Severity  = 'WARNING'
                  Label     = ('Secure Boot is not supported by this firmware. The boot mode reads "{0}", so this is UEFI firmware without Secure Boot support rather than a legacy BIOS - the cmdlet reports both the same way and cannot tell them apart.' -f $FirmwareType)
                  RemedyKey = 'SecureBootUnsupported' }
    }

    return @{ Severity  = 'WARNING'
              Label     = ('Secure Boot could not be read: {0}' -f $Message)
              RemedyKey = 'SecureBootUnreadable' }
}

function Set-WcdFirmwareStatus {
    <#
    .SYNOPSIS
        Reports the boot mode and the Secure Boot state.

    .DESCRIPTION
        Two read-only Steps. FirmwareMode reads an environment variable and
        always reports; SecureBootState calls a cmdlet that needs Administrator
        and, on a legacy BIOS machine, throws rather than answering.

        FirmwareMode runs first so SecureBootState can use its answer to tell
        "legacy BIOS, so the question does not apply" from "UEFI firmware
        without Secure Boot support" - the cmdlet reports both identically.

    .PARAMETER Elevated
        Whether the run holds Administrator rights. When $false the Secure Boot
        cmdlet is not called. Defaults to $true.

    .PARAMETER LogPath
        Full path to the log file. Resolved automatically when omitted.

    .PARAMETER ProgressCallback
        Scriptblock invoked at the start and end of each step for progress display.

    .OUTPUTS
        [pscustomobject[]] with Step, Success, Severity and Error.

    .EXAMPLE
        Set-WcdFirmwareStatus -LogPath 'C:\temp\log.txt'

    .EXAMPLE
        # Unelevated: Secure Boot reports as needing Administrator, not as failed
        Set-WcdFirmwareStatus -Elevated $false
    #>
    [CmdletBinding()]
    param(
        [bool]$Elevated = $true,

        [string]$LogPath,

        [scriptblock]$ProgressCallback
    )

    $resolvedLogPath = Resolve-WcdLogPath -CandidatePath $LogPath
    $moduleName = 'Config-Firmware'
    $requiresElevation = -not $Elevated
    $results = @()

    $firmwareType = Get-WcdFirmwareType

    $results += Invoke-WcdStep -Module $moduleName -Key 'FirmwareMode' `
        -LogPath $resolvedLogPath -ProgressCallback $ProgressCallback `
        -FailureLabel 'Firmware mode' -FailureRemedy 'FirmwareModeUnreadable' `
        -Action {
            if ($firmwareType -eq 'UEFI') {
                return @{ Severity = 'INFO'
                          Error    = 'The machine booted UEFI.'
                          Log      = 'Firmware: the machine booted UEFI.' }
            }

            if ($firmwareType -eq 'Legacy') {
                return @{ Severity  = 'WARNING'
                          Error     = 'The machine booted legacy BIOS.'
                          RemedyKey = 'LegacyBios'
                          Log       = 'Firmware: the machine booted legacy BIOS.' }
            }

            $reported = if ([string]::IsNullOrWhiteSpace($firmwareType)) { 'nothing' } else { $firmwareType }
            return @{ Severity  = 'WARNING'
                      Error     = ('Windows reported the boot mode as {0}.' -f $reported)
                      RemedyKey = 'FirmwareModeUnreadable'
                      Log       = 'Firmware: boot mode reported as {0}.' -f $reported }
        }

    $results += Invoke-WcdStep -Module $moduleName -Key 'SecureBootState' `
        -LogPath $resolvedLogPath -ProgressCallback $ProgressCallback `
        -FailureLabel 'Secure Boot' -FailureRemedy 'SecureBootUnreadable' `
        -Action {
            if ($requiresElevation) {
                return @{ Severity  = 'WARNING'
                          Error     = 'Confirm-SecureBootUEFI requires Administrator.'
                          RemedyKey = 'RequiresAdmin'
                          Log       = 'Secure Boot: skipped, Confirm-SecureBootUEFI requires Administrator.' }
            }

            # Caught here rather than handed to -OnFailure, because none of
            # these are failures. Invoke-WcdStep marks anything that threw as a
            # failed Step whatever the classifier says, and that is right - so a
            # legacy BIOS machine, which is answering the question rather than
            # failing it, must not reach that path.
            try {
                $state = Get-WcdSecureBootState
            } catch {
                $info = Get-WcdSecureBootFailureInfo -Message $_.Exception.Message -FirmwareType $firmwareType
                return @{ Severity  = $info.Severity
                          Error     = $info.Label
                          RemedyKey = $info.RemedyKey
                          Log       = 'Firmware: {0}' -f $info.Label }
            }

            if ($null -eq $state) {
                return @{ Severity  = 'WARNING'
                          Error     = 'Confirm-SecureBootUEFI is not available on this image, so Secure Boot could not be read.'
                          RemedyKey = 'SecureBootUnreadable'
                          Log       = 'Firmware: Confirm-SecureBootUEFI is not available on this image.' }
            }

            if ($state) {
                return @{ Severity = 'INFO'
                          Error    = 'Secure Boot is enabled.'
                          Log      = 'Firmware: Secure Boot is enabled.' }
            }

            return @{ Severity  = 'WARNING'
                      Error     = 'Secure Boot is disabled.'
                      RemedyKey = 'SecureBootOff'
                      Log       = 'Firmware: Secure Boot is disabled.' }
        }

    return $results
}

function Get-WcdFirmwareDescriptor {
    <#
    .SYNOPSIS
        Declares what Config-Firmware contributes to the run.

    .DESCRIPTION
        Two Steps, two rows. They are answered differently: converting a legacy
        BIOS machine needs mbr2gpt and a firmware change, which is a reimage
        decision, while turning Secure Boot on is a trip into firmware setup.

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
        Get-WcdFirmwareDescriptor -ExecutionOptions $options -Config $config -Translations $T
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
        Name     = 'Config-Firmware'
        Order    = 85
        RowOrder = 82
        Steps    = @(
            @{ Key = 'FirmwareMode';    Label = 'Boot mode' }
            @{ Key = 'SecureBootState'; Label = 'Secure Boot' }
        )
        Rows     = @(
            @{ Label = $Translations.Checklist.FirmwareMode; Steps = @('FirmwareMode') }
            @{ Label = $Translations.Checklist.SecureBoot;   Steps = @('SecureBootState') }
        )
        Invoke   = {
            param($ctx)

            Set-WcdFirmwareStatus -Elevated $ctx.Elevated -LogPath $ctx.LogPath -ProgressCallback $ctx.ProgressCallback
        }
    }
}
