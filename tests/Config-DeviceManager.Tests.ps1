Describe 'Config-DeviceManager' {
    BeforeAll {
        $srcDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'src'
        $helpersPath = Join-Path $srcDir 'WcdHelpers.ps1'
        $modulePath  = Join-Path $srcDir 'Config-DeviceManager.ps1'

        if (-not (Test-Path -LiteralPath $helpersPath)) { throw 'WcdHelpers.ps1 introuvable.' }
        if (-not (Test-Path -LiteralPath $modulePath))  { throw 'Config-DeviceManager.ps1 introuvable.' }

        . $helpersPath
        . $modulePath

        $script:PesterMajorVersion = (Get-Module -Name Pester | Select-Object -First 1).Version.Major
    }

    It 'retourne OK quand aucun peripherique n a de probleme' {
        $logPath = Join-Path $TestDrive 'log_device_ok.txt'

        Mock -CommandName 'Get-WcdPnPDevices' {
            @(
                [pscustomobject]@{ Name = 'Intel Wi-Fi'; ConfigManagerErrorCode = 0; PNPDeviceID = 'PCI\\VEN_OK' }
                [pscustomobject]@{ Name = 'NVIDIA Audio'; ConfigManagerErrorCode = 0; PNPDeviceID = 'PCI\\VEN_OK2' }
            )
        }

        $result = Set-WcdDeviceManagerStatus -LogPath $logPath

        if ($script:PesterMajorVersion -ge 5) {
            $result.Success | Should -BeTrue
            $result.Severity | Should -Be 'INFO'
            $result.Step | Should -Be 'DeviceManagerStatus'
            $result.Error | Should -Be ''
        } else {
            $result.Success | Should Be $true
            $result.Severity | Should Be 'INFO'
            $result.Step | Should Be 'DeviceManagerStatus'
            $result.Error | Should Be ''
        }
    }

    It 'retourne warning quand seuls des avertissements sont detectes' {
        $logPath = Join-Path $TestDrive 'log_device_warning.txt'

        Mock -CommandName 'Get-WcdPnPDevices' {
            @(
                [pscustomobject]@{ Name = 'USB Dock'; ConfigManagerErrorCode = 45; PNPDeviceID = 'USB\\WARN2' }
            )
        }

        $result = Set-WcdDeviceManagerStatus -LogPath $logPath

        if ($script:PesterMajorVersion -ge 5) {
            $result.Success | Should -BeTrue
            $result.Severity | Should -Be 'WARNING'
            $result.Error | Should -Match 'Bluetooth Adapter|USB Dock'
            Get-Content -Path $logPath -Raw | Should -Match 'Device Manager warnings detected'
        } else {
            $result.Success | Should Be $true
            $result.Severity | Should Be 'WARNING'
            $result.Error | Should Match 'Bluetooth Adapter|USB Dock'
            Get-Content -Path $logPath -Raw | Should Match 'Device Manager warnings detected'
        }
    }

    It 'ignore PANGP Virtual Ethernet Adapter en code 22' {
        $logPath = Join-Path $TestDrive 'log_device_ignore_pangp.txt'

        Mock -CommandName 'Get-WcdPnPDevices' {
            @(
                [pscustomobject]@{ Name = 'PANGP Virtual Ethernet Adapter Secure'; ConfigManagerErrorCode = 22; PNPDeviceID = 'ROOT\\NET\\0001' }
            )
        }

        $result = Set-WcdDeviceManagerStatus -LogPath $logPath

        if ($script:PesterMajorVersion -ge 5) {
            $result.Success | Should -BeTrue
            $result.Severity | Should -Be 'INFO'
            $result.Error | Should -Be ''
            Get-Content -Path $logPath -Raw | Should -Match 'device ignored by a known exception'
        } else {
            $result.Success | Should Be $true
            $result.Severity | Should Be 'INFO'
            $result.Error | Should Be ''
            Get-Content -Path $logPath -Raw | Should Match 'device ignored by a known exception'
        }
    }

    It 'retourne erreur quand au moins un peripherique est en erreur' {
        $logPath = Join-Path $TestDrive 'log_device_error.txt'

        Mock -CommandName 'Get-WcdPnPDevices' {
            @(
                [pscustomobject]@{ Name = 'Audio Controller'; ConfigManagerErrorCode = 28; PNPDeviceID = 'PCI\\ERR1' }
                [pscustomobject]@{ Name = 'USB Dock'; ConfigManagerErrorCode = 45; PNPDeviceID = 'USB\\WARN2' }
            )
        }

        $result = Set-WcdDeviceManagerStatus -LogPath $logPath

        if ($script:PesterMajorVersion -ge 5) {
            $result.Success | Should -BeFalse
            $result.Severity | Should -Be 'ERROR'
            $result.Error | Should -Match 'Audio Controller'
            $result.Error | Should -Match 'Warnings'
        } else {
            $result.Success | Should Be $false
            $result.Severity | Should Be 'ERROR'
            $result.Error | Should Match 'Audio Controller'
            $result.Error | Should Match 'Warnings'
        }
    }

    It 'retourne erreur si interrogation CIM impossible' {
        $logPath = Join-Path $TestDrive 'log_device_cim_error.txt'

        Mock -CommandName 'Get-WcdPnPDevices' { throw 'CIM indisponible' }

        $result = Set-WcdDeviceManagerStatus -LogPath $logPath

        if ($script:PesterMajorVersion -ge 5) {
            $result.Success | Should -BeFalse
            $result.Severity | Should -Be 'ERROR'
            $result.Error | Should -Match 'CIM'
        } else {
            $result.Success | Should Be $false
            $result.Severity | Should Be 'ERROR'
            $result.Error | Should Match 'CIM'
        }
    }
}