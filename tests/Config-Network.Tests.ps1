Describe 'Config-Network' {
    BeforeAll {
        $srcDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'src'
        $helpersPath = Join-Path $srcDir 'WcdHelpers.ps1'
        $modulePath  = Join-Path $srcDir 'Config-Network.ps1'

        if (-not (Test-Path -LiteralPath $helpersPath)) { throw 'WcdHelpers.ps1 introuvable.' }
        if (-not (Test-Path -LiteralPath $modulePath))  { throw 'Config-Network.ps1 introuvable.' }

        . $helpersPath
        . $modulePath

        $script:PesterMajorVersion = (Get-Module -Name Pester | Select-Object -First 1).Version.Major
    }

    It 'retourne OK quand le ping reussit via Wi-Fi et que Refresh My Network Places est lance' {
        $logPath = Join-Path $TestDrive 'log_network_ok.txt'

        Mock -CommandName 'Get-WcdNetworkAdapters' {
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
        Mock -CommandName 'Get-WcdAdapterIPv4' { '192.168.1.100' }
        Mock -CommandName 'Test-WcdNetworkPing' {
            [pscustomobject]@{ Reachable = $true; Detail = '14 ms' }
        }
        Mock -CommandName 'Get-WcdRefreshNetworkPlacesShortcutPath' {
            Join-Path $TestDrive 'Refresh My Network Places.lnk'
        }
        Mock -CommandName 'Invoke-WcdNetworkShortcut' {}

        $results = @(Set-WcdNetworkDiagnostics -LogPath $logPath)

        if ($script:PesterMajorVersion -ge 5) {
            $results.Count | Should -Be 3
            ($results | Where-Object Step -eq 'NetworkAdapterStatus').Severity | Should -Be 'INFO'
            ($results | Where-Object Step -eq 'NetworkPing8888').Severity | Should -Be 'INFO'
            ($results | Where-Object Step -eq 'RefreshNetworkPlaces').Severity | Should -Be 'INFO'
            Assert-MockCalled -CommandName 'Invoke-WcdNetworkShortcut' -Times 1
        } else {
            $results.Count | Should Be 3
            ($results | Where-Object Step -eq 'NetworkAdapterStatus').Severity | Should Be 'INFO'
            ($results | Where-Object Step -eq 'NetworkPing8888').Severity | Should Be 'INFO'
            ($results | Where-Object Step -eq 'RefreshNetworkPlaces').Severity | Should Be 'INFO'
            Assert-MockCalled 'Invoke-WcdNetworkShortcut' 1
        }
    }

    It 'avertit quand aucun adaptateur reseau pertinent n est actif' {
        $logPath = Join-Path $TestDrive 'log_network_no_adapter.txt'

        Mock -CommandName 'Get-WcdNetworkAdapters' {
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
        Mock -CommandName 'Get-WcdAdapterIPv4' {}
        Mock -CommandName 'Test-WcdNetworkPing' {
            throw 'Ne devrait pas etre appele.'
        }
        Mock -CommandName 'Get-WcdRefreshNetworkPlacesShortcutPath' { $null }
        Mock -CommandName 'Invoke-WcdNetworkShortcut' {}

        $results = @(Set-WcdNetworkDiagnostics -LogPath $logPath)
        $adapterResult = $results | Where-Object Step -eq 'NetworkAdapterStatus'
        $pingResult = $results | Where-Object Step -eq 'NetworkPing8888'

        if ($script:PesterMajorVersion -ge 5) {
            $adapterResult.Severity | Should -Be 'WARNING'
            $pingResult.Severity | Should -Be 'WARNING'
            Assert-MockCalled -CommandName 'Test-WcdNetworkPing' -Times 0
        } else {
            $adapterResult.Severity | Should Be 'WARNING'
            $pingResult.Severity | Should Be 'WARNING'
            Assert-MockCalled 'Test-WcdNetworkPing' 0
        }
    }

    It 'avertit quand le ping vers 8.8.8.8 echoue via Wi-Fi' {
        $logPath = Join-Path $TestDrive 'log_network_ping_warning.txt'

        Mock -CommandName 'Get-WcdNetworkAdapters' {
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
        Mock -CommandName 'Get-WcdAdapterIPv4' { '192.168.1.100' }
        Mock -CommandName 'Test-WcdNetworkPing' {
            [pscustomobject]@{ Reachable = $false; Detail = '' }
        }
        Mock -CommandName 'Get-WcdRefreshNetworkPlacesShortcutPath' {
            Join-Path $TestDrive 'Refresh My Network Places.lnk'
        }
        Mock -CommandName 'Invoke-WcdNetworkShortcut' {}

        $results = @(Set-WcdNetworkDiagnostics -LogPath $logPath)
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

        Mock -CommandName 'Get-WcdNetworkAdapters' {
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
        Mock -CommandName 'Get-WcdAdapterIPv4' { '192.168.1.100' }
        Mock -CommandName 'Test-WcdNetworkPing' {
            [pscustomobject]@{ Reachable = $true; Detail = '9 ms' }
        }
        Mock -CommandName 'Get-WcdRefreshNetworkPlacesShortcutPath' { $null }
        Mock -CommandName 'Invoke-WcdNetworkShortcut' {}

        $results = @(Set-WcdNetworkDiagnostics -LogPath $logPath)
        $refreshResult = $results | Where-Object Step -eq 'RefreshNetworkPlaces'

        if ($script:PesterMajorVersion -ge 5) {
            $refreshResult.Severity | Should -Be 'WARNING'
            $refreshResult.Error | Should -Match 'not found'
            Assert-MockCalled -CommandName 'Invoke-WcdNetworkShortcut' -Times 0
        } else {
            $refreshResult.Severity | Should Be 'WARNING'
            $refreshResult.Error | Should Match 'not found'
            Assert-MockCalled 'Invoke-WcdNetworkShortcut' 0
        }
    }

    It 'retourne une erreur d inventaire si les adaptateurs ne peuvent pas etre lus' {
        $logPath = Join-Path $TestDrive 'log_network_inventory_error.txt'

        Mock -CommandName 'Get-WcdNetworkAdapters' { throw 'WMI indisponible' }
        Mock -CommandName 'Get-WcdAdapterIPv4' {}
        Mock -CommandName 'Test-WcdNetworkPing' {}
        Mock -CommandName 'Get-WcdRefreshNetworkPlacesShortcutPath' {
            Join-Path $TestDrive 'Refresh My Network Places.lnk'
        }
        Mock -CommandName 'Invoke-WcdNetworkShortcut' {}

        $results = @(Set-WcdNetworkDiagnostics -LogPath $logPath)
        $adapterResult = $results | Where-Object Step -eq 'NetworkAdapterStatus'
        $pingResult = $results | Where-Object Step -eq 'NetworkPing8888'

        if ($script:PesterMajorVersion -ge 5) {
            $adapterResult.Success | Should -BeFalse
            $adapterResult.Severity | Should -Be 'ERROR'
            $adapterResult.Error | Should -Match 'WMI indisponible'
            $pingResult.Severity | Should -Be 'WARNING'
            Assert-MockCalled -CommandName 'Test-WcdNetworkPing' -Times 0
        } else {
            $adapterResult.Success | Should Be $false
            $adapterResult.Severity | Should Be 'ERROR'
            $adapterResult.Error | Should Match 'WMI indisponible'
            $pingResult.Severity | Should Be 'WARNING'
            Assert-MockCalled 'Test-WcdNetworkPing' 0
        }
    }
}