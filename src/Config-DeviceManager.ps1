# Config-DeviceManager.ps1 - reports the devices Windows cannot configure.
# Entry point: Set-WcdDeviceManagerStatus. Requires WcdHelpers.ps1.
#
# Read-only: it inspects Win32_PnPEntity and changes nothing.

function Get-WcdPnPDevices {
    <#
    .SYNOPSIS
        Returns every Plug-and-Play device known to Windows.

    .DESCRIPTION
        Thin wrapper over the Win32_PnPEntity CIM class, so the inventory has a
        seam the tests can mock.

    .OUTPUTS
        [object[]] Win32_PnPEntity instances. Throws when CIM cannot be queried.

    .EXAMPLE
        @(Get-WcdPnPDevices).Count
    #>
    [CmdletBinding()]
    param()

    return @(Get-CimInstance -ClassName 'Win32_PnPEntity' -ErrorAction Stop)
}

function Get-WcdDeviceManagerCodeInfo {
    <#
    .SYNOPSIS
        Maps a ConfigManagerErrorCode to a severity and a readable label.

    .DESCRIPTION
        Codes meaning "will resolve itself" - a pending reboot, a device not
        currently connected - are warnings. Codes meaning a driver is missing or
        broken are errors. An unknown code is treated as an error rather than
        quietly passed over.

    .PARAMETER Code
        A non-zero ConfigManagerErrorCode.

    .OUTPUTS
        [hashtable] with Severity and Label.

    .EXAMPLE
        (Get-WcdDeviceManagerCodeInfo -Code 28).Severity   # ERROR
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$Code
    )

    switch ($Code) {
        14 { return @{ Severity = 'WARNING'; Label = 'A restart is needed to finish configuring the device.' } }
        24 { return @{ Severity = 'WARNING'; Label = 'Device not present, or its configuration is incomplete.' } }
        45 { return @{ Severity = 'WARNING'; Label = 'Device is not currently connected.' } }
        47 { return @{ Severity = 'WARNING'; Label = 'Device is waiting on removal or a restart.' } }
        1  { return @{ Severity = 'ERROR'; Label = 'Device is not configured correctly.' } }
        3  { return @{ Severity = 'ERROR'; Label = 'Driver is probably damaged or missing.' } }
        10 { return @{ Severity = 'ERROR'; Label = 'Device cannot start.' } }
        18 { return @{ Severity = 'ERROR'; Label = 'Driver must be reinstalled.' } }
        28 { return @{ Severity = 'ERROR'; Label = 'No driver installed for this device.' } }
        31 { return @{ Severity = 'ERROR'; Label = 'Windows cannot load the required drivers.' } }
        43 { return @{ Severity = 'ERROR'; Label = 'Device reported a problem and was stopped.' } }
        default { return @{ Severity = 'ERROR'; Label = 'Device Manager reported a problem.' } }
    }
}

function Test-WcdIgnoredDeviceManagerIssue {
    <#
    .SYNOPSIS
        Reports whether a device problem is a known false positive.

    .DESCRIPTION
        The GlobalProtect virtual adapter reports code 22 on a healthy machine.
        Only that exact name and code pair is ignored, so no genuine Device Manager
        problem is ever masked.

    .PARAMETER DeviceName
        Device name as reported by Windows.

    .PARAMETER Code
        Its ConfigManagerErrorCode.

    .OUTPUTS
        [bool] $true when the problem should not be reported.

    .EXAMPLE
        Test-WcdIgnoredDeviceManagerIssue -DeviceName 'PANGP Virtual Ethernet Adapter' -Code 22
    #>
    [CmdletBinding()]
    param(
        [string]$DeviceName,

        [int]$Code
    )

    # The GlobalProtect virtual adapter reports code 22 on a perfectly healthy
    # machine. Only that exact name and code pair is ignored, so no genuine
    # Device Manager problem is ever masked.
    return ($Code -eq 22 -and $DeviceName -like 'PANGP Virtual Ethernet Adapter*')
}

function Format-WcdDeviceManagerSummary {
    <#
    .SYNOPSIS
        Summarizes problem devices into one readable line.

    .PARAMETER Devices
        Problem devices, each with Name and Code.

    .PARAMETER Limit
        How many to name before collapsing the rest into a count. Defaults to 3.

    .OUTPUTS
        [string] e.g. 'Unknown device (code 28), +2 more'.

    .EXAMPLE
        Format-WcdDeviceManagerSummary -Devices $problems -Limit 3
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Devices,

        [int]$Limit = 3
    )

    $preview = @($Devices | Select-Object -First $Limit | ForEach-Object {
        '{0} (code {1})' -f $_.Name, $_.Code
    })

    $summary = $preview -join ', '
    if (@($Devices).Count -gt $Limit) {
        $summary = '{0}, +{1} more' -f $summary, (@($Devices).Count - $Limit)
    }

    return $summary
}

function Set-WcdDeviceManagerStatus {
    <#
    .SYNOPSIS
        Reports the devices Windows cannot configure.

    .DESCRIPTION
        Reads every Plug-and-Play device and reports those with a non-zero
        ConfigManagerErrorCode, classified as a warning or an error by code. A
        freshly imaged machine missing a driver is exactly what this catches.

        Read-only: nothing here changes the machine, and it needs no elevation.

    .PARAMETER LogPath
        Full path to the log file. Resolved automatically when omitted.

    .PARAMETER ProgressCallback
        Scriptblock invoked at the start and end of each step for progress display.

    .OUTPUTS
        [pscustomobject] with Step, Success, Severity and Error.

    .EXAMPLE
        Set-WcdDeviceManagerStatus -LogPath 'C:\temp\log.txt'
    #>
    [CmdletBinding()]
    param(
        [string]$LogPath,
        [scriptblock]$ProgressCallback
    )

    $resolvedLogPath = Resolve-WcdLogPath -CandidatePath $LogPath
    $moduleName = 'Config-DeviceManager'
    Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'DeviceManagerStatus' -Event 'Start'

    try {
        $devices = @(Get-WcdPnPDevices)
    } catch {
        $note = 'Device Manager could not be queried through CIM: {0}' -f $_.Exception.Message
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message $note
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'DeviceManagerStatus' -Event 'Finish' -Kind 'error'

        return [pscustomobject]@{
            Step     = 'DeviceManagerStatus'
            Success  = $false
            Severity = 'ERROR'
            Error    = $note
        }
    }

    $problemDevices = @()
    foreach ($device in $devices) {
        $code = 0
        if ($null -ne $device.ConfigManagerErrorCode) {
            $code = [int]$device.ConfigManagerErrorCode
        }

        if ($code -eq 0) {
            continue
        }

        $info = Get-WcdDeviceManagerCodeInfo -Code $code
        $deviceName = $device.Name
        if ([string]::IsNullOrWhiteSpace($deviceName)) {
            $deviceName = $device.PNPDeviceID
        }
        if ([string]::IsNullOrWhiteSpace($deviceName)) {
            $deviceName = 'Unnamed device'
        }

        if (Test-WcdIgnoredDeviceManagerIssue -DeviceName $deviceName -Code $code) {
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('Device Manager: device ignored by a known exception: {0} (code {1}).' -f $deviceName, $code)
            continue
        }

        $problemDevices += [pscustomobject]@{
            Name     = $deviceName
            Code     = $code
            Severity = $info.Severity
            Label    = $info.Label
        }
    }

    $warningDevices = @($problemDevices | Where-Object { $_.Severity -eq 'WARNING' })
    $errorDevices = @($problemDevices | Where-Object { $_.Severity -eq 'ERROR' })

    if ($errorDevices.Count -gt 0) {
        $errorSummary = Format-WcdDeviceManagerSummary -Devices $errorDevices
        $warningSummary = ''
        if ($warningDevices.Count -gt 0) {
            $warningSummary = ' | Warnings: {0}' -f (Format-WcdDeviceManagerSummary -Devices $warningDevices)
        }

        $message = 'Device Manager errors detected ({0}): {1}{2}' -f $errorDevices.Count, $errorSummary, $warningSummary
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message $message
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'DeviceManagerStatus' -Event 'Finish' -Kind 'error'

        return [pscustomobject]@{
            Step     = 'DeviceManagerStatus'
            Success  = $false
            Severity = 'ERROR'
            Error    = $message
        }
    }

    if ($warningDevices.Count -gt 0) {
        $message = 'Device Manager warnings detected ({0}): {1}' -f $warningDevices.Count, (Format-WcdDeviceManagerSummary -Devices $warningDevices)
        Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message $message
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'DeviceManagerStatus' -Event 'Finish' -Kind 'warning'

        return [pscustomobject]@{
            Step     = 'DeviceManagerStatus'
            Success  = $true
            Severity = 'WARNING'
            Error    = $message
        }
    }

    Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'Device Manager: no warnings or errors detected.'
    Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'DeviceManagerStatus' -Event 'Finish' -Kind 'success'
    return [pscustomobject]@{
        Step     = 'DeviceManagerStatus'
        Success  = $true
        Severity = 'INFO'
        Error    = ''
    }
}