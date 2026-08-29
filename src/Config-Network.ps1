<#
.SYNOPSIS
    Effectue un diagnostic reseau: inventorie les adaptateurs actifs, teste la
    connectivite vers 8.8.8.8 via Wi-Fi, et active le raccourci
    "Refresh My Network Places" si present.

.DESCRIPTION
    Utilise Get-NetAdapter pour lister les adaptateurs pertinents (filtre
    Bluetooth, loopback, VPN, etc.), puis effectue un ping 8.8.8.8 avec source
    forcee (-S) sur l'adaptateur Wi-Fi. Tente ensuite de lancer le raccourci
    .lnk "Refresh My Network Places" depuis le profil utilisateur.
    Requiert WcdHelpers.ps1 charge au prealable via dot-source.

.PARAMETER LogPath
    Chemin complet vers le fichier journal (.txt). Si omis, resolu automatiquement
    par Resolve-WcdLogPath.

.OUTPUTS
    [pscustomobject[]] — tableau de resultats avec Step, Success, Severity, Error.
    Etapes possibles: NetworkAdapterStatus, NetworkPing8888, RefreshNetworkPlaces.
#>

function Get-WcdNetworkAdapters {
    [CmdletBinding()]
    param()

    $command = Get-Command -Name 'Get-NetAdapter' -ErrorAction SilentlyContinue
    if (-not $command) {
        throw 'Get-NetAdapter est indisponible sur cette session.'
    }

    return @(Get-NetAdapter -ErrorAction Stop)
}

function Test-WcdNetworkAdapterActive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Adapter
    )

    $status = [string]$Adapter.Status
    return ($status -match '^(Up|Connected)$')
}

function Test-WcdRelevantNetworkAdapter {
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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Adapters
    )

    return @($Adapters | Where-Object { $_.PhysicalMediaType -eq 'Native 802.11' }) | Select-Object -First 1
}

function Get-WcdAdapterIPv4 {
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

    return 'Autre'
}

function Format-WcdNetworkAdapterSummary {
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
            $label = 'Adaptateur inconnu'
        }

        '{0}: {1}' -f (Get-WcdNetworkAdapterKind -Adapter $_), $label
    })

    $summary = $preview -join ', '
    if (@($Adapters).Count -gt $Limit) {
        $summary = '{0}, +{1} autre(s)' -f $summary, (@($Adapters).Count - $Limit)
    }

    return $summary
}

function Test-WcdNetworkPing {
    [CmdletBinding()]
    param(
        [string]$ComputerName = '8.8.8.8',
        [string]$SourceAddress
    )

    # Utilise ping.exe avec -S <source> pour forcer l interface de sortie
    # (bypass de la priorite Ethernet quand on veut tester le Wi-Fi).
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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    Start-Process -FilePath $Path -ErrorAction Stop
}

function Set-WcdNetworkDiagnostics {
    [CmdletBinding()]
    param(
        [string]$LogPath
    )

    $resolvedLogPath = Resolve-WcdLogPath -CandidatePath $LogPath
    $results = @()
    $activeAdapters = @()
    $adapterInventoryUnavailable = $false

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
            $message = 'Aucun adaptateur reseau actif pertinent detecte.'
            if ($adapters.Count -gt 0) {
                $message = '{0} Adaptateurs vus: {1}' -f $message, (Format-WcdNetworkAdapterSummary -Adapters $adapters)
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
        $message = 'Impossible d inventorier les adaptateurs reseau: {0}' -f $_.Exception.Message
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message $message
        $results += [pscustomobject]@{
            Step     = 'NetworkAdapterStatus'
            Success  = $false
            Severity = 'ERROR'
            Error    = $message
        }
    }

    if ($adapterInventoryUnavailable) {
        $message = 'Ping 8.8.8.8 ignore: inventaire des adaptateurs reseau indisponible.'
        Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message $message
        $results += [pscustomobject]@{
            Step     = 'NetworkPing8888'
            Success  = $true
            Severity = 'WARNING'
            Error    = $message
        }
    } elseif ($activeAdapters.Count -eq 0) {
        $message = 'Ping 8.8.8.8 ignore: aucun adaptateur reseau actif pertinent detecte.'
        Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message $message
        $results += [pscustomobject]@{
            Step     = 'NetworkPing8888'
            Success  = $true
            Severity = 'WARNING'
            Error    = $message
        }
    } else {
        # --- Ping 8.8.8.8 via Wi-Fi (source forcee avec -S) ---
        $wifiAdapter = Get-WcdWiFiAdapter -Adapters $adapters

        if ($null -eq $wifiAdapter) {
            $message = 'Adaptateur Wi-Fi (802.11) non detecte sur ce poste. Ping Wi-Fi ignore.'
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('Network: {0}' -f $message)
            $results += [pscustomobject]@{
                Step     = 'NetworkPing8888'
                Success  = $true
                Severity = 'WARNING'
                Error    = $message
            }
        } elseif (-not (Test-WcdNetworkAdapterActive -Adapter $wifiAdapter)) {
            $wifiName = if (-not [string]::IsNullOrWhiteSpace($wifiAdapter.InterfaceDescription)) { $wifiAdapter.InterfaceDescription } else { $wifiAdapter.Name }
            $message = 'Adaptateur Wi-Fi detecte ({0}) mais non actif (Status: {1}). Ping Wi-Fi ignore.' -f $wifiName, $wifiAdapter.Status
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
                $message = 'Adaptateur Wi-Fi actif ({0}) mais aucune adresse IPv4 attribuee. Ping Wi-Fi ignore.' -f $wifiName
                Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('Network: {0}' -f $message)
                $results += [pscustomobject]@{
                    Step     = 'NetworkPing8888'
                    Success  = $true
                    Severity = 'WARNING'
                    Error    = $message
                }
            } else {
                try {
                    $pingResult = Test-WcdNetworkPing -ComputerName '8.8.8.8' -SourceAddress $wifiIPv4
                    if ($pingResult.Reachable) {
                        $detail = ''
                        if (-not [string]::IsNullOrWhiteSpace($pingResult.Detail)) {
                            $detail = ' ({0})' -f $pingResult.Detail
                        }

                        Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('Network: ping 8.8.8.8 over Wi-Fi ({0}, source {1}) succeeded{2}.' -f $wifiName, $wifiIPv4, $detail)
                        $results += [pscustomobject]@{
                            Step     = 'NetworkPing8888'
                            Success  = $true
                            Severity = 'INFO'
                            Error    = ''
                        }
                    } else {
                        $message = 'Le ping vers 8.8.8.8 via Wi-Fi ({0}, source {1}) a echoue.' -f $wifiName, $wifiIPv4
                        Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('Network: {0}' -f $message)
                        $results += [pscustomobject]@{
                            Step     = 'NetworkPing8888'
                            Success  = $true
                            Severity = 'WARNING'
                            Error    = $message
                        }
                    }
                } catch {
                    $message = 'Le ping vers 8.8.8.8 via Wi-Fi n a pas pu etre execute: {0}' -f $_.Exception.Message
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

    try {
        $shortcutPath = Get-WcdRefreshNetworkPlacesShortcutPath
        if ([string]::IsNullOrWhiteSpace($shortcutPath)) {
            $message = 'Refresh My Network Places introuvable dans les raccourcis reseau de l utilisateur.'
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
        $message = 'Refresh My Network Places n a pas pu etre active: {0}' -f $_.Exception.Message
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message $message
        $results += [pscustomobject]@{
            Step     = 'RefreshNetworkPlaces'
            Success  = $true
            Severity = 'WARNING'
            Error    = $message
        }
    }

    return $results
}