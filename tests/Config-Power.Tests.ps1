Describe 'Config-Power' {
    BeforeAll {
        $helpersPath = Join-Path $PSScriptRoot 'MinimalHelpers.ps1'
        $modulePath  = Join-Path $PSScriptRoot 'Config-Power.ps1'

        if (-not (Test-Path -LiteralPath $helpersPath)) {
            $helpersPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'tests/MinimalHelpers.ps1'
        }
        if (-not (Test-Path -LiteralPath $modulePath)) {
            $modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'tests/Config-Power.ps1'
        }

        if (-not (Test-Path -LiteralPath $helpersPath)) { throw 'MinimalHelpers.ps1 introuvable.' }
        if (-not (Test-Path -LiteralPath $modulePath))  { throw 'Config-Power.ps1 introuvable.' }

        . $helpersPath
        . $modulePath

        $script:PesterMajorVersion = (Get-Module -Name Pester | Select-Object -First 1).Version.Major
    }

    It 'configure alimentation complete pour portable avec succes' {
        $logPath = Join-Path $TestDrive 'log_power_full.txt'

        Mock -CommandName 'Invoke-MinimalPowerCfg' {}

        $results = Set-MinimalPowerConfiguration -DeviceType 'Portable' -LogPath $logPath

        if ($script:PesterMajorVersion -ge 5) {
            $results.Count | Should -Be 5
            ($results | Where-Object Step -eq 'EcranBatterie10min').Success | Should -BeTrue
            ($results | Where-Object Step -eq 'EcranSecteur15min').Success | Should -BeTrue
            ($results | Where-Object Step -eq 'CapotSecteurNeRienFaire').Success | Should -BeTrue
            ($results | Where-Object Step -eq 'CapotBatterieNeRienFaire').Success | Should -BeTrue
            ($results | Where-Object Step -eq 'SetActiveSchemeCurrent').Success | Should -BeTrue
            Get-Content -Path $logPath -Raw | Should -Match 'ecran batterie 10 min'
            Get-Content -Path $logPath -Raw | Should -Match 'fermeture capot secteur ne rien faire'
            Get-Content -Path $logPath -Raw | Should -Match 'fermeture capot batterie ne rien faire'
            Get-Content -Path $logPath -Raw | Should -Match 'profil actif applique'
        } else {
            $results.Count | Should Be 5
            ($results | Where-Object Step -eq 'EcranBatterie10min').Success | Should Be $true
            ($results | Where-Object Step -eq 'EcranSecteur15min').Success | Should Be $true
            ($results | Where-Object Step -eq 'CapotSecteurNeRienFaire').Success | Should Be $true
            ($results | Where-Object Step -eq 'CapotBatterieNeRienFaire').Success | Should Be $true
            ($results | Where-Object Step -eq 'SetActiveSchemeCurrent').Success | Should Be $true
            Get-Content -Path $logPath -Raw | Should Match 'ecran batterie 10 min'
            Get-Content -Path $logPath -Raw | Should Match 'fermeture capot secteur ne rien faire'
            Get-Content -Path $logPath -Raw | Should Match 'fermeture capot batterie ne rien faire'
            Get-Content -Path $logPath -Raw | Should Match 'profil actif applique'
        }
    }

    It 'configure alimentation pour bureau sans etape capot' {
        $logPath = Join-Path $TestDrive 'log_power_bureau.txt'

        Mock -CommandName 'Invoke-MinimalPowerCfg' {}

        $results = Set-MinimalPowerConfiguration -DeviceType 'Bureau' -LogPath $logPath

        if ($script:PesterMajorVersion -ge 5) {
            $results.Count | Should -Be 2
            ($results | Where-Object Step -eq 'EcranBatterie10min') | Should -BeNullOrEmpty
            ($results | Where-Object Step -eq 'VeillePCBatterieJamais') | Should -BeNullOrEmpty
            ($results | Where-Object Step -eq 'CapotSecteurNeRienFaire') | Should -BeNullOrEmpty
            ($results | Where-Object Step -eq 'CapotBatterieNeRienFaire') | Should -BeNullOrEmpty
        } else {
            $results.Count | Should Be 2
            ($results | Where-Object Step -eq 'EcranBatterie10min') | Should BeNullOrEmpty
            ($results | Where-Object Step -eq 'VeillePCBatterieJamais') | Should BeNullOrEmpty
            ($results | Where-Object Step -eq 'CapotSecteurNeRienFaire') | Should BeNullOrEmpty
            ($results | Where-Object Step -eq 'CapotBatterieNeRienFaire') | Should BeNullOrEmpty
        }
    }

}
