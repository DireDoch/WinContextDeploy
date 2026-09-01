# Config-BitLocker.ps1 - TPM readiness, and encryption on the system drive.
# Entry point: Set-WcdBitLockerStatus. Requires WcdHelpers.ps1.
#
# Report only: it never enables BitLocker and never touches a recovery key.
# Turning encryption on is a security decision with a real lockout risk, not a
# verification, and it belongs to whoever owns the fleet policy.
#
# Both cmdlets need Administrator, so unelevated it reports what would have
# needed it rather than failing, the same way Config-Power does.

function Get-WcdTpmStatus {
    <#
    .SYNOPSIS
        Returns what Get-Tpm reports about the machine's TPM.

    .DESCRIPTION
        Thin wrapper over Get-Tpm, so the Step has a seam the tests can mock.
        A session without the cmdlet - a stripped image, or a Windows edition
        that omits it - returns $null rather than throwing: that is a state to
        report, not a failed Step.

    .OUTPUTS
        The TPM object, or $null when Get-Tpm is unavailable.

    .EXAMPLE
        (Get-WcdTpmStatus).TpmReady
    #>
    [CmdletBinding()]
    param()

    if (-not (Get-Command -Name 'Get-Tpm' -ErrorAction SilentlyContinue)) {
        return $null
    }

    return (Get-Tpm -ErrorAction Stop)
}

function Get-WcdSystemBitLockerVolume {
    <#
    .SYNOPSIS
        Returns the BitLocker volume for the drive Windows sits on.

    .DESCRIPTION
        Only the system drive is checked: a technician's USB key is not the
        machine's disk, and a data volume left unencrypted on a freshly imaged
        machine is not what a handover check is for.

        Windows Home ships without the BitLocker module entirely, so the cmdlet
        is probed for rather than the edition string parsed - a stripped
        Professional image behaves the same way and would fool the string.
        An absent cmdlet returns $null rather than throwing.

    .OUTPUTS
        The BitLocker volume, or $null when Get-BitLockerVolume is unavailable.

    .EXAMPLE
        (Get-WcdSystemBitLockerVolume).ProtectionStatus
    #>
    [CmdletBinding()]
    param()

    if (-not (Get-Command -Name 'Get-BitLockerVolume' -ErrorAction SilentlyContinue)) {
        return $null
    }

    $mountPoint = '{0}:' -f (Get-WcdSystemDriveLetter)
    return (Get-BitLockerVolume -MountPoint $mountPoint -ErrorAction Stop)
}

function Set-WcdBitLockerStatus {
    <#
    .SYNOPSIS
        Reports whether the TPM is ready and whether the system drive is
        encrypted.

    .DESCRIPTION
        Handing over an unencrypted laptop is invisible on the day and expensive
        later, so an unprotected system drive is always a warning. There is no
        manifest knob for it: a fleet that applies encryption by policy after
        enrolment will see the warning on a fresh machine, and that is the
        correct thing for the checklist to say. A drive still encrypting warns
        too, and names the percentage - Windows calls it protected long before
        it finishes.

        Report only - nothing here enables BitLocker or reads a recovery key.

        Both cmdlets need Administrator. Unelevated, both Steps report as
        needing elevation instead of failing, matching the power Steps. Kept out
        of Config-Disk for exactly that reason: disk health needs no elevation
        and must keep reporting normally on a non-elevated run.

    .PARAMETER Elevated
        Whether the run holds Administrator rights. When $false neither cmdlet is
        called. Defaults to $true.

    .PARAMETER LogPath
        Full path to the log file. Resolved automatically when omitted.

    .PARAMETER ProgressCallback
        Scriptblock invoked at the start and end of each step for progress display.

    .OUTPUTS
        [pscustomobject[]] with Step, Success, Severity, Error and optionally
        RemedyKey, for TpmReadiness and BitLockerStatus.

    .EXAMPLE
        Set-WcdBitLockerStatus -LogPath 'C:\temp\log.txt'

    .EXAMPLE
        # Unelevated: reports what would need Administrator instead of failing
        Set-WcdBitLockerStatus -Elevated $false
    #>
    [CmdletBinding()]
    param(
        [bool]$Elevated = $true,

        [string]$LogPath,

        [scriptblock]$ProgressCallback
    )

    $resolvedLogPath = Resolve-WcdLogPath -CandidatePath $LogPath
    $moduleName = 'Config-BitLocker'
    $results = @()

    # --- TPM readiness -------------------------------------------------------
    Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'TpmReadiness' -Event 'Start'

    if (-not $Elevated) {
        Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'BitLocker: TPM readiness skipped, Get-Tpm requires Administrator.'
        $results += [pscustomobject]@{
            Step      = 'TpmReadiness'
            Success   = $true
            Severity  = 'WARNING'
            Error     = 'Get-Tpm requires Administrator.'
            RemedyKey = 'RequiresAdmin'
        }
    } else {
        try {
            $tpm = Get-WcdTpmStatus

            if ($null -eq $tpm) {
                $message = 'Get-Tpm is unavailable in this session; the TPM state could not be read.'
                Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('BitLocker: {0}' -f $message)
                $results += [pscustomobject]@{
                    Step     = 'TpmReadiness'
                    Success  = $true
                    Severity = 'WARNING'
                    Error    = $message
                }
            } elseif (-not $tpm.TpmPresent) {
                $message = 'No TPM reported by Get-Tpm.'
                Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('BitLocker: {0}' -f $message)
                $results += [pscustomobject]@{
                    Step      = 'TpmReadiness'
                    Success   = $true
                    Severity  = 'WARNING'
                    Error     = $message
                    RemedyKey = 'TpmNotReady'
                }
            } elseif (-not $tpm.TpmReady) {
                $message = 'TPM present but not ready.'
                Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('BitLocker: {0}' -f $message)
                $results += [pscustomobject]@{
                    Step      = 'TpmReadiness'
                    Success   = $true
                    Severity  = 'WARNING'
                    Error     = $message
                    RemedyKey = 'TpmNotReady'
                }
            } else {
                Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'BitLocker: TPM present and ready.'
                $results += [pscustomobject]@{
                    Step     = 'TpmReadiness'
                    Success  = $true
                    Severity = 'INFO'
                    Error    = 'TPM present and ready.'
                }
            }
        } catch {
            $message = 'The TPM state could not be read: {0}' -f $_.Exception.Message
            Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message $message
            $results += [pscustomobject]@{
                Step     = 'TpmReadiness'
                Success  = $false
                Severity = 'ERROR'
                Error    = $message
            }
        }
    }

    Complete-WcdProgressStep -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'TpmReadiness' -Results $results

    # --- Encryption on the system drive --------------------------------------
    Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'BitLockerStatus' -Event 'Start'

    if (-not $Elevated) {
        Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'BitLocker: encryption status skipped, Get-BitLockerVolume requires Administrator.'
        $results += [pscustomobject]@{
            Step      = 'BitLockerStatus'
            Success   = $true
            Severity  = 'WARNING'
            Error     = 'Get-BitLockerVolume requires Administrator.'
            RemedyKey = 'RequiresAdmin'
        }
    } else {
        try {
            $volume = Get-WcdSystemBitLockerVolume

            if ($null -eq $volume) {
                $message = 'This Windows edition does not include BitLocker.'
                Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('BitLocker: {0}' -f $message)
                $results += [pscustomobject]@{
                    Step      = 'BitLockerStatus'
                    Success   = $true
                    Severity  = 'WARNING'
                    Error     = $message
                    RemedyKey = 'BitLockerUnavailable'
                }
            } elseif (([string]$volume.VolumeStatus) -eq 'EncryptionInProgress') {
                # Progress outranks protection here. Windows flips
                # ProtectionStatus to On as soon as the protectors exist, which
                # is long before the drive is actually encrypted - so keying the
                # severity off ProtectionStatus alone would print a green OK for
                # a machine sitting at 47%. A machine handed over half encrypted
                # is not a protected machine.
                $message = 'Encryption still running: {0} {1}% complete.' -f $volume.MountPoint, ([double]$volume.EncryptionPercentage)
                Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('BitLocker: {0}' -f $message)
                $results += [pscustomobject]@{
                    Step      = 'BitLockerStatus'
                    Success   = $true
                    Severity  = 'WARNING'
                    Error     = $message
                    RemedyKey = 'BitLockerInProgress'
                }
            } else {
                $detail = '{0} {1}.' -f $volume.MountPoint, $volume.VolumeStatus

                if (([string]$volume.ProtectionStatus) -eq 'On') {
                    $message = 'Protected: {0}' -f $detail
                    Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('BitLocker: {0}' -f $message)
                    $results += [pscustomobject]@{
                        Step     = 'BitLockerStatus'
                        Success  = $true
                        Severity = 'INFO'
                        Error    = $message
                    }
                } else {
                    $message = 'Not protected: {0}' -f $detail
                    Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('BitLocker: {0}' -f $message)
                    $results += [pscustomobject]@{
                        Step      = 'BitLockerStatus'
                        Success   = $true
                        Severity  = 'WARNING'
                        Error     = $message
                        RemedyKey = 'BitLockerOff'
                    }
                }
            }
        } catch {
            $message = 'The encryption status of the system drive could not be read: {0}' -f $_.Exception.Message
            Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message $message
            $results += [pscustomobject]@{
                Step     = 'BitLockerStatus'
                Success  = $false
                Severity = 'ERROR'
                Error    = $message
            }
        }
    }

    Complete-WcdProgressStep -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'BitLockerStatus' -Results $results

    return $results
}
