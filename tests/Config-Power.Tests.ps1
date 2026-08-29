Describe 'Config-Power' {
    BeforeAll {
        $srcDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'src'
        $helpersPath = Join-Path $srcDir 'WcdHelpers.ps1'
        $modulePath  = Join-Path $srcDir 'Config-Power.ps1'

        if (-not (Test-Path -LiteralPath $helpersPath)) { throw 'WcdHelpers.ps1 introuvable.' }
        if (-not (Test-Path -LiteralPath $modulePath))  { throw 'Config-Power.ps1 introuvable.' }

        . $helpersPath
        . $modulePath

        $script:PesterMajorVersion = (Get-Module -Name Pester | Select-Object -First 1).Version.Major
    }

    It 'configure alimentation complete pour portable avec succes' {
        $logPath = Join-Path $TestDrive 'log_power_full.txt'

        Mock -CommandName 'Invoke-WcdPowerCfg' {}

        $results = Set-WcdPowerConfiguration -FormFactor 'Laptop' -LogPath $logPath

        if ($script:PesterMajorVersion -ge 5) {
            $results.Count | Should -Be 5
            ($results | Where-Object Step -eq 'ScreenTimeoutBattery').Success | Should -BeTrue
            ($results | Where-Object Step -eq 'ScreenTimeoutAc').Success | Should -BeTrue
            ($results | Where-Object Step -eq 'LidActionAcNone').Success | Should -BeTrue
            ($results | Where-Object Step -eq 'LidActionBatteryNone').Success | Should -BeTrue
            ($results | Where-Object Step -eq 'SetActiveSchemeCurrent').Success | Should -BeTrue
            Get-Content -Path $logPath -Raw | Should -Match 'screen timeout on battery set to 10 min'
            Get-Content -Path $logPath -Raw | Should -Match 'lid close on AC set to do nothing'
            Get-Content -Path $logPath -Raw | Should -Match 'lid close on battery set to do nothing'
            Get-Content -Path $logPath -Raw | Should -Match 'active scheme applied'
        } else {
            $results.Count | Should Be 5
            ($results | Where-Object Step -eq 'ScreenTimeoutBattery').Success | Should Be $true
            ($results | Where-Object Step -eq 'ScreenTimeoutAc').Success | Should Be $true
            ($results | Where-Object Step -eq 'LidActionAcNone').Success | Should Be $true
            ($results | Where-Object Step -eq 'LidActionBatteryNone').Success | Should Be $true
            ($results | Where-Object Step -eq 'SetActiveSchemeCurrent').Success | Should Be $true
            Get-Content -Path $logPath -Raw | Should Match 'screen timeout on battery set to 10 min'
            Get-Content -Path $logPath -Raw | Should Match 'lid close on AC set to do nothing'
            Get-Content -Path $logPath -Raw | Should Match 'lid close on battery set to do nothing'
            Get-Content -Path $logPath -Raw | Should Match 'active scheme applied'
        }
    }

    It 'configure alimentation pour bureau sans etape capot' {
        $logPath = Join-Path $TestDrive 'log_power_bureau.txt'

        Mock -CommandName 'Invoke-WcdPowerCfg' {}

        $results = Set-WcdPowerConfiguration -FormFactor 'Desktop' -LogPath $logPath

        if ($script:PesterMajorVersion -ge 5) {
            $results.Count | Should -Be 2
            ($results | Where-Object Step -eq 'ScreenTimeoutBattery') | Should -BeNullOrEmpty
            ($results | Where-Object Step -eq 'SleepBatteryNever') | Should -BeNullOrEmpty
            ($results | Where-Object Step -eq 'LidActionAcNone') | Should -BeNullOrEmpty
            ($results | Where-Object Step -eq 'LidActionBatteryNone') | Should -BeNullOrEmpty
        } else {
            $results.Count | Should Be 2
            ($results | Where-Object Step -eq 'ScreenTimeoutBattery') | Should BeNullOrEmpty
            ($results | Where-Object Step -eq 'SleepBatteryNever') | Should BeNullOrEmpty
            ($results | Where-Object Step -eq 'LidActionAcNone') | Should BeNullOrEmpty
            ($results | Where-Object Step -eq 'LidActionBatteryNone') | Should BeNullOrEmpty
        }
    }

}
