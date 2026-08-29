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

        Mock -CommandName 'Invoke-WcdPowerCfg' {}

        $results = Set-WcdPowerConfiguration -FormFactor 'Desktop' -LogPath $logPath

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
