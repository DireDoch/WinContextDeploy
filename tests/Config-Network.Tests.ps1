Describe 'Config-Network' {
    BeforeAll {
        $helpersPath = Join-Path $PSScriptRoot 'MinimalHelpers.ps1'
        $modulePath  = Join-Path $PSScriptRoot 'Config-Network.ps1'

        if (-not (Test-Path -LiteralPath $helpersPath)) {
            $helpersPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'tests/MinimalHelpers.ps1'
        }
        if (-not (Test-Path -LiteralPath $modulePath)) {
            $modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'tests/Config-Network.ps1'
        }

        if (-not (Test-Path -LiteralPath $helpersPath)) { throw 'MinimalHelpers.ps1 introuvable.' }
        if (-not (Test-Path -LiteralPath $modulePath))  { throw 'Config-Network.ps1 introuvable.' }

        . $helpersPath
        . $modulePath

        $script:PesterMajorVersion = (Get-Module -Name Pester | Select-Object -First 1).Version.Major
    }

    It 'retourne OK quand le ping reussit via Wi-Fi et que Refresh My Network Places est lance' {
        $logPath = Join-Path $TestDrive 'log_network_ok.txt'

        Mock -CommandName 'Get-MinimalNetworkAdapters' {
            @(
                [pscustomobject]@{
                    Name                 = 'Wi-Fi'
                    InterfaceAlias       = 'Wi-Fi'
                    InterfaceDescription = 'Intel(R) Wi-Fi 6E AX211 160MHz'
                    DriverDescription    = 'Intel(R) Wi-Fi 6E AX211 160MHz'
                    PhysicalMediaType    = 'Native 802.11'
                    InterfaceIndex       = 7
                    Status               = 'Up'
                }
            )
        }
        Mock -CommandName 'Get-MinimalAdapterIPv4' { '192.168.1.100' }
        Mock -CommandName 'Test-MinimalNetworkPing' {
            [pscustomobject]@{ Reachable = $true; Detail = '14 ms' }
        }
        Mock -CommandName 'Get-MinimalRefreshNetworkPlacesShortcutPath' {
            Join-Path $TestDrive 'Refresh My Network Places.lnk'
        }
        Mock -CommandName 'Invoke-MinimalNetworkShortcut' {}

        $results = @(Set-MinimalNetworkDiagnostics -LogPath $logPath)

        if ($script:PesterMajorVersion -ge 5) {
            $results.Count | Should -Be 3
            ($results | Where-Object Step -eq 'NetworkAdapterEtat').Severity | Should -Be 'INFO'
            ($results | Where-Object Step -eq 'NetworkPing8888').Severity | Should -Be 'INFO'
            ($results | Where-Object Step -eq 'RefreshNetworkPlaces').Severity | Should -Be 'INFO'
            Assert-MockCalled -CommandName 'Invoke-MinimalNetworkShortcut' -Times 1
        } else {
            $results.Count | Should Be 3
            ($results | Where-Object Step -eq 'NetworkAdapterEtat').Severity | Should Be 'INFO'
            ($results | Where-Object Step -eq 'NetworkPing8888').Severity | Should Be 'INFO'
            ($results | Where-Object Step -eq 'RefreshNetworkPlaces').Severity | Should Be 'INFO'
            Assert-MockCalled 'Invoke-MinimalNetworkShortcut' 1
        }
    }

    It 'avertit quand aucun adaptateur reseau pertinent n est actif' {
        $logPath = Join-Path $TestDrive 'log_network_no_adapter.txt'

        Mock -CommandName 'Get-MinimalNetworkAdapters' {
            @(
                [pscustomobject]@{
                    Name                 = 'Intel Ethernet'
                    InterfaceAlias       = 'Ethernet'
                    InterfaceDescription = 'Intel Ethernet'
                    DriverDescription    = 'Intel Ethernet'
                    PhysicalMediaType    = 'Native 802.3'
                    InterfaceIndex       = 3
                    Status               = 'Disconnected'
                }
            )
        }
        Mock -CommandName 'Get-MinimalAdapterIPv4' {}
        Mock -CommandName 'Test-MinimalNetworkPing' {
            throw 'Ne devrait pas etre appele.'
        }
        Mock -CommandName 'Get-MinimalRefreshNetworkPlacesShortcutPath' { $null }
        Mock -CommandName 'Invoke-MinimalNetworkShortcut' {}

        $results = @(Set-MinimalNetworkDiagnostics -LogPath $logPath)
        $adapterResult = $results | Where-Object Step -eq 'NetworkAdapterEtat'
        $pingResult = $results | Where-Object Step -eq 'NetworkPing8888'

        if ($script:PesterMajorVersion -ge 5) {
            $adapterResult.Severity | Should -Be 'WARNING'
            $pingResult.Severity | Should -Be 'WARNING'
            Assert-MockCalled -CommandName 'Test-MinimalNetworkPing' -Times 0
        } else {
            $adapterResult.Severity | Should Be 'WARNING'
            $pingResult.Severity | Should Be 'WARNING'
            Assert-MockCalled 'Test-MinimalNetworkPing' 0
        }
    }

    It 'avertit quand le ping vers 8.8.8.8 echoue via Wi-Fi' {
        $logPath = Join-Path $TestDrive 'log_network_ping_warning.txt'

        Mock -CommandName 'Get-MinimalNetworkAdapters' {
            @(
                [pscustomobject]@{
                    Name                 = 'Wi-Fi'
                    InterfaceAlias       = 'Wi-Fi'
                    InterfaceDescription = 'Intel(R) Wi-Fi 6E AX211 160MHz'
                    DriverDescription    = 'Intel(R) Wi-Fi 6E AX211 160MHz'
                    PhysicalMediaType    = 'Native 802.11'
                    InterfaceIndex       = 7
                    Status               = 'Up'
                }
            )
        }
        Mock -CommandName 'Get-MinimalAdapterIPv4' { '192.168.1.100' }
        Mock -CommandName 'Test-MinimalNetworkPing' {
            [pscustomobject]@{ Reachable = $false; Detail = '' }
        }
        Mock -CommandName 'Get-MinimalRefreshNetworkPlacesShortcutPath' {
            Join-Path $TestDrive 'Refresh My Network Places.lnk'
        }
        Mock -CommandName 'Invoke-MinimalNetworkShortcut' {}

        $results = @(Set-MinimalNetworkDiagnostics -LogPath $logPath)
        $pingResult = $results | Where-Object Step -eq 'NetworkPing8888'

        if ($script:PesterMajorVersion -ge 5) {
            $pingResult.Severity | Should -Be 'WARNING'
            $pingResult.Error | Should -Match '8.8.8.8'
        } else {
            $pingResult.Severity | Should Be 'WARNING'
            $pingResult.Error | Should Match '8.8.8.8'
        }
    }

    It 'avertit quand Refresh My Network Places est introuvable' {
        $logPath = Join-Path $TestDrive 'log_network_refresh_missing.txt'

        Mock -CommandName 'Get-MinimalNetworkAdapters' {
            @(
                [pscustomobject]@{
                    Name                 = 'Wi-Fi'
                    InterfaceAlias       = 'Wi-Fi'
                    InterfaceDescription = 'Intel(R) Wi-Fi 6E AX211 160MHz'
                    DriverDescription    = 'Intel(R) Wi-Fi 6E AX211 160MHz'
                    PhysicalMediaType    = 'Native 802.11'
                    InterfaceIndex       = 7
                    Status               = 'Up'
                }
            )
        }
        Mock -CommandName 'Get-MinimalAdapterIPv4' { '192.168.1.100' }
        Mock -CommandName 'Test-MinimalNetworkPing' {
            [pscustomobject]@{ Reachable = $true; Detail = '9 ms' }
        }
        Mock -CommandName 'Get-MinimalRefreshNetworkPlacesShortcutPath' { $null }
        Mock -CommandName 'Invoke-MinimalNetworkShortcut' {}

        $results = @(Set-MinimalNetworkDiagnostics -LogPath $logPath)
        $refreshResult = $results | Where-Object Step -eq 'RefreshNetworkPlaces'

        if ($script:PesterMajorVersion -ge 5) {
            $refreshResult.Severity | Should -Be 'WARNING'
            $refreshResult.Error | Should -Match 'introuvable'
            Assert-MockCalled -CommandName 'Invoke-MinimalNetworkShortcut' -Times 0
        } else {
            $refreshResult.Severity | Should Be 'WARNING'
            $refreshResult.Error | Should Match 'introuvable'
            Assert-MockCalled 'Invoke-MinimalNetworkShortcut' 0
        }
    }

    It 'retourne une erreur d inventaire si les adaptateurs ne peuvent pas etre lus' {
        $logPath = Join-Path $TestDrive 'log_network_inventory_error.txt'

        Mock -CommandName 'Get-MinimalNetworkAdapters' { throw 'WMI indisponible' }
        Mock -CommandName 'Get-MinimalAdapterIPv4' {}
        Mock -CommandName 'Test-MinimalNetworkPing' {}
        Mock -CommandName 'Get-MinimalRefreshNetworkPlacesShortcutPath' {
            Join-Path $TestDrive 'Refresh My Network Places.lnk'
        }
        Mock -CommandName 'Invoke-MinimalNetworkShortcut' {}

        $results = @(Set-MinimalNetworkDiagnostics -LogPath $logPath)
        $adapterResult = $results | Where-Object Step -eq 'NetworkAdapterEtat'
        $pingResult = $results | Where-Object Step -eq 'NetworkPing8888'

        if ($script:PesterMajorVersion -ge 5) {
            $adapterResult.Success | Should -BeFalse
            $adapterResult.Severity | Should -Be 'ERROR'
            $adapterResult.Error | Should -Match 'WMI indisponible'
            $pingResult.Severity | Should -Be 'WARNING'
            Assert-MockCalled -CommandName 'Test-MinimalNetworkPing' -Times 0
        } else {
            $adapterResult.Success | Should Be $false
            $adapterResult.Severity | Should Be 'ERROR'
            $adapterResult.Error | Should Match 'WMI indisponible'
            $pingResult.Severity | Should Be 'WARNING'
            Assert-MockCalled 'Test-MinimalNetworkPing' 0
        }
    }
}