# Config-Disk.ps1 - disk health, and free space on the system drive.
# Entry point: Set-WcdDiskStatus. Requires WcdHelpers.ps1.
#
# Read-only: it changes nothing and needs no elevation.

function Get-WcdPhysicalDisks {
    <#
    .SYNOPSIS
        Returns every physical disk Windows knows about.

    .DESCRIPTION
        Thin wrapper over Get-PhysicalDisk, so the inventory has a seam the tests
        can mock and a session without the Storage module fails with a clear
        message.

    .OUTPUTS
        [object[]] Physical disk objects. Throws when Get-PhysicalDisk is
        unavailable.

    .EXAMPLE
        @(Get-WcdPhysicalDisks).Count
    #>
    [CmdletBinding()]
    param()

    $command = Get-Command -Name 'Get-PhysicalDisk' -ErrorAction SilentlyContinue
    if (-not $command) {
        throw 'Get-PhysicalDisk is unavailable in this session.'
    }

    return @(Get-PhysicalDisk -ErrorAction Stop)
}

function Test-WcdRemovableDisk {
    <#
    .SYNOPSIS
        Reports whether a disk is removable rather than part of the machine.

    .DESCRIPTION
        A technician's USB key or an SD card in the reader is not the machine's
        disk, and its health must never block a handover. Matched on the bus type
        rather than the name, which varies by vendor.

    .PARAMETER Disk
        A physical disk object.

    .OUTPUTS
        [bool] $true for a USB, SD or MMC disk.

    .EXAMPLE
        Test-WcdRemovableDisk -Disk $disk
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Disk
    )

    return (@('USB', 'SD', 'MMC') -contains [string]$Disk.BusType)
}

function Get-WcdDiskHealthSeverity {
    <#
    .SYNOPSIS
        Maps a HealthStatus to a Result severity.

    .DESCRIPTION
        Healthy passes. Warning is a warning. Unhealthy is an error. Anything
        else - Unknown, or a controller that reports nothing - is a warning
        rather than a silent pass: an unreadable disk is not a healthy one.

    .PARAMETER HealthStatus
        HealthStatus as reported by Get-PhysicalDisk.

    .OUTPUTS
        [string] 'INFO', 'WARNING' or 'ERROR'.

    .EXAMPLE
        Get-WcdDiskHealthSeverity -HealthStatus 'Unhealthy'   # ERROR
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$HealthStatus
    )

    switch ($HealthStatus) {
        'Healthy'   { return 'INFO' }
        'Warning'   { return 'WARNING' }
        'Unhealthy' { return 'ERROR' }
        default     { return 'WARNING' }
    }
}

function Format-WcdDiskSummary {
    <#
    .SYNOPSIS
        Names disks the way a technician can find them in a machine.

    .DESCRIPTION
        The friendly name alone is not enough to pull the right drive out of a
        two-disk machine, so the serial number goes with it whenever the disk
        reports one.

    .PARAMETER Disks
        Physical disk objects to name.

    .OUTPUTS
        [string] e.g. 'WDC WD10EZEX (serial WD-WCC6Y1234567)'.

    .EXAMPLE
        Format-WcdDiskSummary -Disks $unhealthy
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Disks
    )

    return (@($Disks | ForEach-Object {
        $name = [string]$_.FriendlyName
        if ([string]::IsNullOrWhiteSpace($name)) { $name = 'Unnamed disk' }

        $serial = ([string]$_.SerialNumber).Trim()
        if ([string]::IsNullOrWhiteSpace($serial)) {
            $name
        } else {
            '{0} (serial {1})' -f $name, $serial
        }
    }) -join ', ')
}

function Get-WcdSystemVolume {
    <#
    .SYNOPSIS
        Returns the volume the running Windows sits on.

    .DESCRIPTION
        Reads the drive letter through Get-WcdSystemDriveLetter rather than
        assuming C:. Thin wrapper over Get-Volume, so the tests have a seam to
        mock.

    .OUTPUTS
        The system volume. Throws when Get-Volume is unavailable or the drive
        cannot be read.

    .EXAMPLE
        (Get-WcdSystemVolume).SizeRemaining
    #>
    [CmdletBinding()]
    param()

    $command = Get-Command -Name 'Get-Volume' -ErrorAction SilentlyContinue
    if (-not $command) {
        throw 'Get-Volume is unavailable in this session.'
    }

    return (Get-Volume -DriveLetter (Get-WcdSystemDriveLetter) -ErrorAction Stop)
}

function Get-WcdMinimumFreeGB {
    <#
    .SYNOPSIS
        Returns the free-space threshold in GB.

    .DESCRIPTION
        Site-specific, so it comes from the manifest's Disk.MinFreeGB. A missing,
        unreadable or non-positive value falls back to 20 GB rather than failing
        the run on a typo.

    .PARAMETER Config
        The imported manifest. Optional.

    .OUTPUTS
        [double] The threshold in GB.

    .EXAMPLE
        Get-WcdMinimumFreeGB -Config $config   # 20
    #>
    [CmdletBinding()]
    param(
        [hashtable]$Config
    )

    if ($null -ne $Config -and $null -ne $Config.Disk -and $null -ne $Config.Disk.MinFreeGB) {
        $configured = $Config.Disk.MinFreeGB -as [double]
        if ($null -ne $configured -and $configured -gt 0) {
            return $configured
        }
    }

    return 20
}

function Set-WcdDiskStatus {
    <#
    .SYNOPSIS
        Reports the health of the machine's disks and the free space on the
        system drive.

    .DESCRIPTION
        A freshly imaged machine can still be sitting on a dying drive, or on a
        partition far smaller than the image expects. Both are caught here rather
        than by the user weeks later.

        Removable disks are left out of the health check: a technician's USB key
        is not the machine's disk. Free space is read on the system drive only,
        for the same reason.

        Read-only: nothing here changes the machine, and it needs no elevation.

    .PARAMETER LogPath
        Full path to the log file. Resolved automatically when omitted.

    .PARAMETER Config
        The imported manifest. Its Disk.MinFreeGB overrides the default threshold
        of 20 GB.

    .PARAMETER ProgressCallback
        Scriptblock invoked at the start and end of each step for progress display.

    .OUTPUTS
        [pscustomobject[]] with Step, Success, Severity, Error and optionally
        RemedyKey and RemedyArgs, for DiskHealth and DiskFreeSpace.

    .EXAMPLE
        Set-WcdDiskStatus -Config $config -LogPath 'C:\temp\log.txt'
    #>
    [CmdletBinding()]
    param(
        [string]$LogPath,

        [hashtable]$Config,

        [scriptblock]$ProgressCallback
    )

    $resolvedLogPath = Resolve-WcdLogPath -CandidatePath $LogPath
    $moduleName = 'Config-Disk'
    $results = @()

    # --- Disk health ---------------------------------------------------------
    Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'DiskHealth' -Event 'Start'

    try {
        $disks = @(Get-WcdPhysicalDisks | Where-Object { -not (Test-WcdRemovableDisk -Disk $_) })

        $unhealthy = @($disks | Where-Object { (Get-WcdDiskHealthSeverity -HealthStatus ([string]$_.HealthStatus)) -eq 'ERROR' })
        $warning = @($disks | Where-Object { (Get-WcdDiskHealthSeverity -HealthStatus ([string]$_.HealthStatus)) -eq 'WARNING' })

        if ($disks.Count -eq 0) {
            $message = 'No fixed disk reported by Get-PhysicalDisk.'
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('Disk: {0}' -f $message)
            $results += [pscustomobject]@{
                Step     = 'DiskHealth'
                Success  = $true
                Severity = 'WARNING'
                Error    = $message
            }
        } elseif ($unhealthy.Count -gt 0) {
            $names = Format-WcdDiskSummary -Disks $unhealthy
            $message = 'Disk reported Unhealthy: {0}' -f $names
            Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ('Disk: {0}' -f $message)
            $results += [pscustomobject]@{
                Step       = 'DiskHealth'
                Success    = $false
                Severity   = 'ERROR'
                Error      = $message
                RemedyKey  = 'DiskUnhealthy'
                RemedyArgs = @($names)
            }
        } elseif ($warning.Count -gt 0) {
            $message = 'Disk health not confirmed: {0} ({1})' -f (Format-WcdDiskSummary -Disks $warning), (@($warning | ForEach-Object { [string]$_.HealthStatus }) -join ', ')
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('Disk: {0}' -f $message)
            $results += [pscustomobject]@{
                Step     = 'DiskHealth'
                Success  = $true
                Severity = 'WARNING'
                Error    = $message
            }
        } else {
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('Disk: every fixed disk reports Healthy ({0}).' -f (Format-WcdDiskSummary -Disks $disks))
            $results += [pscustomobject]@{
                Step     = 'DiskHealth'
                Success  = $true
                Severity = 'INFO'
                Error    = ''
            }
        }
    } catch {
        $message = 'The disks could not be inventoried: {0}' -f $_.Exception.Message
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message $message
        $results += [pscustomobject]@{
            Step     = 'DiskHealth'
            Success  = $false
            Severity = 'ERROR'
            Error    = $message
        }
    }

    Complete-WcdProgressStep -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'DiskHealth' -Results $results

    # --- Free space on the system drive --------------------------------------
    Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'DiskFreeSpace' -Event 'Start'

    $minFreeGB = Get-WcdMinimumFreeGB -Config $Config

    try {
        $volume = Get-WcdSystemVolume
        $freeGB = [double]$volume.SizeRemaining / 1GB
        $totalGB = [double]$volume.Size / 1GB
        # Floored, never rounded: "20 GB free" printed beside "below the 20 GB
        # threshold" reads as a bug. The comparison below is made on the raw
        # figure, so 19.6 GB cannot pass a 20 GB threshold either way.
        $detail = '{0:N0} GB free of {1:N0} GB' -f [math]::Floor($freeGB), [math]::Floor($totalGB)

        if ($freeGB -ge $minFreeGB) {
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('Disk: {0}, at or above the {1:N0} GB threshold.' -f $detail, $minFreeGB)
            $results += [pscustomobject]@{
                Step     = 'DiskFreeSpace'
                Success  = $true
                Severity = 'INFO'
                Error    = $detail
            }
        } else {
            $message = '{0}, below the {1:N0} GB threshold.' -f $detail, $minFreeGB
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('Disk: {0}' -f $message)
            $results += [pscustomobject]@{
                Step      = 'DiskFreeSpace'
                Success   = $true
                Severity  = 'WARNING'
                Error     = $message
                RemedyKey = 'DiskLowFreeSpace'
            }
        }
    } catch {
        $message = 'The free space on the system drive could not be read: {0}' -f $_.Exception.Message
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message $message
        $results += [pscustomobject]@{
            Step     = 'DiskFreeSpace'
            Success  = $false
            Severity = 'ERROR'
            Error    = $message
        }
    }

    Complete-WcdProgressStep -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'DiskFreeSpace' -Results $results

    return $results
}
