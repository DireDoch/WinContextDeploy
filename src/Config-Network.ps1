# Config-Network.ps1 - network adapter inventory, connectivity test, and the
# "Refresh My Network Places" shortcut.
# Entry point: Set-WcdNetworkDiagnostics. Requires WcdHelpers.ps1.
#
# Read-only: it changes nothing and needs no elevation.

function Get-WcdNetworkAdapters {
    <#
    .SYNOPSIS
        Returns every network adapter Windows knows about.

    .DESCRIPTION
        Thin wrapper over Get-NetAdapter, so the inventory has a seam the tests can
        mock and a session without the NetAdapter module fails with a clear message.

    .OUTPUTS
        [object[]] Adapter objects. Throws when Get-NetAdapter is unavailable.

    .EXAMPLE
        @(Get-WcdNetworkAdapters).Count
    #>
    [CmdletBinding()]
    param()

    $command = Get-Command -Name 'Get-NetAdapter' -ErrorAction SilentlyContinue
    if (-not $command) {
        throw 'Get-NetAdapter is unavailable in this session.'
    }

    return @(Get-NetAdapter -ErrorAction Stop)
}

function Test-WcdNetworkAdapterActive {
    <#
    .SYNOPSIS
        Reports whether an adapter is up.

    .PARAMETER Adapter
        An adapter object.

    .OUTPUTS
        [bool] $true when its Status is Up or Connected.

    .EXAMPLE
        Test-WcdNetworkAdapterActive -Adapter $adapter
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Adapter
    )

    $status = [string]$Adapter.Status
    return ($status -match '^(Up|Connected)$')
}

function Test-WcdRelevantNetworkAdapter {
    <#
    .SYNOPSIS
        Reports whether an adapter is one a technician cares about.

    .DESCRIPTION
        A freshly imaged machine carries a dozen virtual adapters - Bluetooth,
        loopback, VPN, hypervisor, WAN miniports - that would drown the real
        Wi-Fi and Ethernet interfaces in the summary.

    .PARAMETER Adapter
        An adapter object.

    .OUTPUTS
        [bool] $false for a virtual or auxiliary interface.

    .EXAMPLE
        Test-WcdRelevantNetworkAdapter -Adapter $adapter
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Adapter
    )

    $text = @(
        [string]$Adapter.Name,
        [string]$Adapter.InterfaceAlias,
        [string]$Adapter.InterfaceDescription,
        [string]$Adapter.DriverDescription
    ) -join ' '

    return (-not ($text -match 'bluetooth|loopback|isatap|teredo|vmware|hyper-v|vEthernet|virtual|vpn|wan miniport|miniport|pangp|anyconnect|juniper|tap'))
}

function Get-WcdActiveNetworkAdapters {
    <#
    .SYNOPSIS
        Returns the adapters that are both up and relevant.

    .PARAMETER Adapters
        Adapters to filter.

    .OUTPUTS
        [object[]] The active, relevant adapters.

    .EXAMPLE
        Get-WcdActiveNetworkAdapters -Adapters (Get-WcdNetworkAdapters)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Adapters
    )

    return @($Adapters | Where-Object {
        (Test-WcdNetworkAdapterActive -Adapter $_) -and
        (Test-WcdRelevantNetworkAdapter -Adapter $_)
    })
}

function Get-WcdWiFiAdapter {
    <#
    .SYNOPSIS
        Returns the first Wi-Fi adapter, or $null.

    .DESCRIPTION
        Matches on the physical media type rather than the adapter name, which
        varies by vendor and by display language.

    .PARAMETER Adapters
        Adapters to search.

    .OUTPUTS
        The Wi-Fi adapter, or $null when the machine has none.

    .EXAMPLE
        Get-WcdWiFiAdapter -Adapters (Get-WcdNetworkAdapters)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Adapters
    )

    return @($Adapters | Where-Object { $_.PhysicalMediaType -eq 'Native 802.11' }) | Select-Object -First 1
}

function Get-WcdAdapterIPv4 {
    <#
    .SYNOPSIS
        Returns an adapter's usable IPv4 address.

    .DESCRIPTION
        Link-local (169.254.x.x) and loopback addresses are ignored: an adapter
        holding only those has no working connection to test from.

    .PARAMETER Adapter
        The adapter to read.

    .OUTPUTS
        [string] The IPv4 address, or $null.

    .EXAMPLE
        Get-WcdAdapterIPv4 -Adapter $wifiAdapter
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Adapter
    )

    $ipEntries = @(Get-NetIPAddress -InterfaceIndex $Adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue)
    $valid = $ipEntries | Where-Object { $_.IPAddress -notmatch '^169\.254\.' -and $_.IPAddress -ne '127.0.0.1' } | Select-Object -First 1

    if ($null -ne $valid) {
        return $valid.IPAddress
    }

    return $null
}

function Get-WcdNetworkAdapterKind {
    <#
    .SYNOPSIS
        Classifies an adapter as Wi-Fi, Ethernet or Other.

    .PARAMETER Adapter
        The adapter to classify.

    .OUTPUTS
        [string] 'Wi-Fi', 'Ethernet' or 'Other'.

    .EXAMPLE
        Get-WcdNetworkAdapterKind -Adapter $adapter
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Adapter
    )

    $text = @(
        [string]$Adapter.Name,
        [string]$Adapter.InterfaceAlias,
        [string]$Adapter.InterfaceDescription,
        [string]$Adapter.DriverDescription
    ) -join ' '

    if ($text -match 'wi-?fi|wireless|802\.11|wlan') {
        return 'Wi-Fi'
    }

    if ($text -match 'ethernet|gigabit|gbe|lan') {
        return 'Ethernet'
    }

    return 'Other'
}

function Format-WcdNetworkAdapterSummary {
    <#
    .SYNOPSIS
        Summarizes adapters into one readable line.

    .PARAMETER Adapters
        Adapters to summarize.

    .PARAMETER Limit
        How many to name before collapsing the rest into a count. Defaults to 3.

    .OUTPUTS
        [string] e.g. 'Wi-Fi: Wi-Fi, Ethernet: Ethernet, +1 more'.

    .EXAMPLE
        Format-WcdNetworkAdapterSummary -Adapters $active
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Adapters,

        [int]$Limit = 3
    )

    $preview = @($Adapters | Select-Object -First $Limit | ForEach-Object {
        $label = [string]$_.InterfaceAlias
        if ([string]::IsNullOrWhiteSpace($label)) {
            $label = [string]$_.Name
        }
        if ([string]::IsNullOrWhiteSpace($label)) {
            $label = [string]$_.InterfaceDescription
        }
        if ([string]::IsNullOrWhiteSpace($label)) {
            $label = 'Unknown adapter'
        }

        '{0}: {1}' -f (Get-WcdNetworkAdapterKind -Adapter $_), $label
    })

    $summary = $preview -join ', '
    if (@($Adapters).Count -gt $Limit) {
        $summary = '{0}, +{1} more' -f $summary, (@($Adapters).Count - $Limit)
    }

    return $summary
}

function Test-WcdNetworkPing {
    <#
    .SYNOPSIS
        Pings a host, optionally from a chosen source address.

    .DESCRIPTION
        Uses ping.exe rather than Test-Connection because -S pins the outgoing
        interface: with a cable plugged in, a test aimed at the Wi-Fi adapter would
        otherwise be answered over Ethernet and pass while Wi-Fi is broken.

    .PARAMETER ComputerName
        Host to ping. Defaults to 8.8.8.8.

    .PARAMETER SourceAddress
        Local address to send from. Omit to let Windows choose.

    .OUTPUTS
        [pscustomobject] with Reachable and Detail.

    .EXAMPLE
        Test-WcdNetworkPing -ComputerName '10.0.0.1' -SourceAddress '192.168.1.100'
    #>
    [CmdletBinding()]
    param(
        [string]$ComputerName = '8.8.8.8',
        [string]$SourceAddress
    )

    # ping.exe with -S <source> forces the outgoing interface, so an
    # Ethernet cable cannot answer a test aimed at the Wi-Fi adapter.
    $pingArgs = @('-n', '1', '-w', '3000')
    if (-not [string]::IsNullOrWhiteSpace($SourceAddress)) {
        $pingArgs += '-S'
        $pingArgs += $SourceAddress
    }
    $pingArgs += $ComputerName

    $output = & ping.exe @pingArgs 2>&1
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
        $detail = ''
        $joined = $output -join "`n"
        if ($joined -match '(?:temps|time)[=<]\s*(\d+)\s*ms') {
            $detail = '{0} ms' -f $Matches[1]
        }

        return [pscustomobject]@{
            Reachable = $true
            Detail    = $detail
        }
    }

    return [pscustomobject]@{
        Reachable = $false
        Detail    = (($output | Where-Object { $_ -match '\S' }) -join ' ').Trim()
    }
}

function Get-WcdRefreshNetworkPlacesShortcutPath {
    <#
    .SYNOPSIS
        Finds the user's "Refresh My Network Places" shortcut.

    .DESCRIPTION
        Looks in the user's Network Shortcuts folder, by exact name first and then
        by a looser match, since the shortcut name is localized on some images.

    .OUTPUTS
        [string] Full path to the shortcut, or $null when there is none.

    .EXAMPLE
        $shortcut = Get-WcdRefreshNetworkPlacesShortcutPath
    #>
    [CmdletBinding()]
    param()

    $bases = @()
    if (-not [string]::IsNullOrWhiteSpace($env:APPDATA)) {
        $bases += (Join-Path $env:APPDATA 'Microsoft\Windows\Network Shortcuts')
    }
    if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        $bases += (Join-Path $env:USERPROFILE 'AppData\Roaming\Microsoft\Windows\Network Shortcuts')
    }

    foreach ($base in @($bases | Select-Object -Unique)) {
        if ([string]::IsNullOrWhiteSpace($base) -or -not (Test-Path -LiteralPath $base)) {
            continue
        }

        $items = @(Get-ChildItem -LiteralPath $base -File -Filter '*.lnk' -ErrorAction SilentlyContinue)
        $exact = $items | Where-Object { $_.BaseName -eq 'Refresh My Network Places' } | Select-Object -First 1
        if ($null -ne $exact) {
            return $exact.FullName
        }

        $partial = $items | Where-Object { $_.BaseName -match 'refresh\s+my\s+network\s+places' } | Select-Object -First 1
        if ($null -ne $partial) {
            return $partial.FullName
        }
    }

    return $null
}

function Invoke-WcdNetworkShortcut {
    <#
    .SYNOPSIS
        Launches a network shortcut.

    .PARAMETER Path
        Full path to the .lnk file.

    .OUTPUTS
        None. Throws when the shortcut cannot be started.

    .EXAMPLE
        Invoke-WcdNetworkShortcut -Path $shortcut
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    Start-Process -FilePath $Path -ErrorAction Stop
}

function Set-WcdNetworkDiagnostics {
    <#
    .SYNOPSIS
        Inventories the network adapters, tests connectivity, and refreshes the
        user's network places.

    .DESCRIPTION
        Read-only: nothing here changes the machine, so it is safe to run
        unelevated. A blocked ping is reported as a warning rather than a hard
        failure - plenty of corporate networks drop ICMP - and the ping target is a
        manifest value so it can point at something that answers on your network.

    .PARAMETER LogPath
        Full path to the log file. Resolved automatically when omitted.

    .PARAMETER Config
        The imported manifest. Its Network.PingTarget overrides the default target
        of 8.8.8.8.

    .PARAMETER ProgressCallback
        Scriptblock invoked at the start and end of each step for progress display.

    .OUTPUTS
        [pscustomobject[]] with Step, Success, Severity and Error, for
        NetworkAdapterStatus, NetworkPing8888 and RefreshNetworkPlaces.

    .EXAMPLE
        Set-WcdNetworkDiagnostics -Config $config -LogPath 'C:\temp\log.txt'
    #>
    [CmdletBinding()]
    param(
        [string]$LogPath,

        [hashtable]$Config,

        [scriptblock]$ProgressCallback
    )

    $resolvedLogPath = Resolve-WcdLogPath -CandidatePath $LogPath
    $moduleName = 'Config-Network'
    $results = @()
    $activeAdapters = @()
    $adapterInventoryUnavailable = $false

    # The ping target is a manifest value: 8.8.8.8 is blocked outright on some
    # corporate networks, which would report a false failure every run.
    $pingTarget = '8.8.8.8'
    if ($null -ne $Config -and $null -ne $Config.Network -and -not [string]::IsNullOrWhiteSpace([string]$Config.Network.PingTarget)) {
        $pingTarget = [string]$Config.Network.PingTarget
    }

    Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'NetworkAdapterStatus' -Event 'Start'

    try {
        $adapters = @(Get-WcdNetworkAdapters)
        $activeAdapters = @(Get-WcdActiveNetworkAdapters -Adapters $adapters)

        if ($activeAdapters.Count -gt 0) {
            $summary = Format-WcdNetworkAdapterSummary -Adapters $activeAdapters
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('Network: active adapters detected: {0}' -f $summary)
            $results += [pscustomobject]@{
                Step     = 'NetworkAdapterStatus'
                Success  = $true
                Severity = 'INFO'
                Error    = ''
            }
        } else {
            $message = 'No relevant active network adapter detected.'
            if ($adapters.Count -gt 0) {
                $message = '{0} Adapters seen: {1}' -f $message, (Format-WcdNetworkAdapterSummary -Adapters $adapters)
            }

            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('Network: {0}' -f $message)
            $results += [pscustomobject]@{
                Step     = 'NetworkAdapterStatus'
                Success  = $true
                Severity = 'WARNING'
                Error    = $message
            }
        }
    } catch {
        $adapterInventoryUnavailable = $true
        $message = 'The network adapters could not be inventoried: {0}' -f $_.Exception.Message
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message $message
        $results += [pscustomobject]@{
            Step     = 'NetworkAdapterStatus'
            Success  = $false
            Severity = 'ERROR'
            Error    = $message
        }
    }

    Complete-WcdProgressStep -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'NetworkAdapterStatus' -Results $results
    Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'NetworkPing8888' -Event 'Start'

    if ($adapterInventoryUnavailable) {
        $message = 'Ping {0} skipped: the network adapter inventory is unavailable.' -f $pingTarget
        Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message $message
        $results += [pscustomobject]@{
            Step     = 'NetworkPing8888'
            Success  = $true
            Severity = 'WARNING'
            Error    = $message
        }
    } elseif ($activeAdapters.Count -eq 0) {
        $message = 'Ping {0} skipped: no relevant active network adapter detected.' -f $pingTarget
        Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message $message
        $results += [pscustomobject]@{
            Step     = 'NetworkPing8888'
            Success  = $true
            Severity = 'WARNING'
            Error    = $message
        }
    } else {
        # --- Ping the target over Wi-Fi, source address forced with -S ---
        $wifiAdapter = Get-WcdWiFiAdapter -Adapters $adapters

        if ($null -eq $wifiAdapter) {
            $message = 'No Wi-Fi (802.11) adapter detected on this machine. Wi-Fi ping skipped.'
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('Network: {0}' -f $message)
            $results += [pscustomobject]@{
                Step     = 'NetworkPing8888'
                Success  = $true
                Severity = 'WARNING'
                Error    = $message
            }
        } elseif (-not (Test-WcdNetworkAdapterActive -Adapter $wifiAdapter)) {
            $wifiName = if (-not [string]::IsNullOrWhiteSpace($wifiAdapter.InterfaceDescription)) { $wifiAdapter.InterfaceDescription } else { $wifiAdapter.Name }
            $message = 'Wi-Fi adapter detected ({0}) but not active (Status: {1}). Wi-Fi ping skipped.' -f $wifiName, $wifiAdapter.Status
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('Network: {0}' -f $message)
            $results += [pscustomobject]@{
                Step     = 'NetworkPing8888'
                Success  = $true
                Severity = 'WARNING'
                Error    = $message
            }
        } else {
            $wifiIPv4 = Get-WcdAdapterIPv4 -Adapter $wifiAdapter
            $wifiName = if (-not [string]::IsNullOrWhiteSpace($wifiAdapter.InterfaceDescription)) { $wifiAdapter.InterfaceDescription } else { $wifiAdapter.Name }

            if ([string]::IsNullOrWhiteSpace($wifiIPv4)) {
                $message = 'Wi-Fi adapter active ({0}) but no IPv4 address assigned. Wi-Fi ping skipped.' -f $wifiName
                Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('Network: {0}' -f $message)
                $results += [pscustomobject]@{
                    Step     = 'NetworkPing8888'
                    Success  = $true
                    Severity = 'WARNING'
                    Error    = $message
                }
            } else {
                try {
                    $pingResult = Test-WcdNetworkPing -ComputerName $pingTarget -SourceAddress $wifiIPv4
                    if ($pingResult.Reachable) {
                        $detail = ''
                        if (-not [string]::IsNullOrWhiteSpace($pingResult.Detail)) {
                            $detail = ' ({0})' -f $pingResult.Detail
                        }

                        Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('Network: ping {0} over Wi-Fi ({1}, source {2}) succeeded{3}.' -f $pingTarget, $wifiName, $wifiIPv4, $detail)
                        $results += [pscustomobject]@{
                            Step     = 'NetworkPing8888'
                            Success  = $true
                            Severity = 'INFO'
                            Error    = ''
                        }
                    } else {
                        $message = 'The ping to {0} over Wi-Fi ({1}, source {2}) failed.' -f $pingTarget, $wifiName, $wifiIPv4
                        Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('Network: {0}' -f $message)
                        $results += [pscustomobject]@{
                            Step     = 'NetworkPing8888'
                            Success  = $true
                            Severity = 'WARNING'
                            Error    = $message
                        }
                    }
                } catch {
                    $message = 'The ping to {0} over Wi-Fi could not be run: {1}' -f $pingTarget, $_.Exception.Message
                    Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message $message
                    $results += [pscustomobject]@{
                        Step     = 'NetworkPing8888'
                        Success  = $true
                        Severity = 'WARNING'
                        Error    = $message
                    }
                }
            }
        }
    }

    Complete-WcdProgressStep -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'NetworkPing8888' -Results $results
    Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'RefreshNetworkPlaces' -Event 'Start'

    try {
        $shortcutPath = Get-WcdRefreshNetworkPlacesShortcutPath
        if ([string]::IsNullOrWhiteSpace($shortcutPath)) {
            $message = 'Refresh My Network Places not found in the user network shortcuts.'
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('Network: {0}' -f $message)
            $results += [pscustomobject]@{
                Step     = 'RefreshNetworkPlaces'
                Success  = $true
                Severity = 'WARNING'
                Error    = $message
            }
        } else {
            Invoke-WcdNetworkShortcut -Path $shortcutPath
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('Network: Refresh My Network Places triggered via {0}.' -f $shortcutPath)
            $results += [pscustomobject]@{
                Step     = 'RefreshNetworkPlaces'
                Success  = $true
                Severity = 'INFO'
                Error    = ''
            }
        }
    } catch {
        $message = 'Refresh My Network Places could not be triggered: {0}' -f $_.Exception.Message
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message $message
        $results += [pscustomobject]@{
            Step     = 'RefreshNetworkPlaces'
            Success  = $true
            Severity = 'WARNING'
            Error    = $message
        }
    }

    Complete-WcdProgressStep -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'RefreshNetworkPlaces' -Results $results

    return $results
}