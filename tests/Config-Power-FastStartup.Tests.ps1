Describe 'Config-Power - demarrage rapide' {
    BeforeAll {
        $srcDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'src'
        foreach ($file in @('WcdHelpers.ps1', 'Config-Power.ps1')) {
            $path = Join-Path $srcDir $file
            if (-not (Test-Path -LiteralPath $path)) { throw ('{0} introuvable.' -f $file) }
            . $path
        }
    }

    BeforeEach {
        $script:LogPath = Join-Path $TestDrive ('log_faststartup_{0}.txt' -f [guid]::NewGuid())
        Mock -CommandName 'Invoke-WcdPowerCfg' { }
        Mock -CommandName 'Get-WcdBatteryReportHtml' { '<html><td>52,000 mWh</td><td>48,900 mWh</td></html>' }
    }

    It 'rapporte OK quand la valeur est a zero' {
        Mock -CommandName 'Get-WcdFastStartupValue' { 0 }

        $result = Set-WcdPowerConfiguration -FormFactor 'Laptop' -LogPath $script:LogPath | Where-Object Step -eq 'FastStartup'

        $result.Severity | Should -Be 'INFO'
        $result.FastStartupEnabled | Should -BeFalse
    }

    It 'avertit quand la valeur est a un' {
        Mock -CommandName 'Get-WcdFastStartupValue' { 1 }

        $result = Set-WcdPowerConfiguration -FormFactor 'Laptop' -LogPath $script:LogPath | Where-Object Step -eq 'FastStartup'

        $result.Severity | Should -Be 'WARNING'
        $result.RemedyKey | Should -Be 'FastStartupOn'
        $result.FastStartupEnabled | Should -BeTrue
    }

    It 'traite une valeur absente comme active, pas comme une erreur' {
        # Le demarrage rapide est actif par defaut et Windows n ecrit la cle que
        # si quelque chose la change: lire "absent" comme "desactive"
        # rapporterait le cas par defaut comme propre.
        Mock -CommandName 'Get-WcdFastStartupValue' { $null }

        $result = Set-WcdPowerConfiguration -FormFactor 'Laptop' -LogPath $script:LogPath | Where-Object Step -eq 'FastStartup'

        $result.Severity | Should -Be 'WARNING'
        $result.Success | Should -BeTrue
        $result.Error | Should -Match 'default'
    }

    It 'traite une cle absente comme une valeur absente' {
        # Get-WcdFastStartupValue rend $null dans les deux cas; c est la meme
        # reponse et elle doit donner la meme ligne.
        (Get-WcdFastStartupInfo -Value $null).Enabled | Should -BeTrue
        (Get-WcdFastStartupInfo -Value $null).Severity | Should -Be 'WARNING'
    }

    It 's applique aux deux Form Factors' {
        Mock -CommandName 'Get-WcdFastStartupValue' { 1 }

        foreach ($formFactor in @('Laptop', 'Desktop')) {
            $result = Set-WcdPowerConfiguration -FormFactor $formFactor -LogPath $script:LogPath | Where-Object Step -eq 'FastStartup'
            $result | Should -Not -BeNullOrEmpty -Because ('{0} a aussi un demarrage rapide' -f $formFactor)
        }
    }

    It 'rapporte meme sans elevation, parce qu une lecture HKLM est ouverte' {
        Mock -CommandName 'Get-WcdFastStartupValue' { 1 }

        $result = Set-WcdPowerConfiguration -FormFactor 'Desktop' -Elevated $false -LogPath $script:LogPath |
            Where-Object Step -eq 'FastStartup'

        $result.RemedyKey | Should -Be 'FastStartupOn'
        $result.RemedyKey | Should -Not -Be 'RequiresAdmin'
    }

    It 'n ecrit jamais la cle' {
        $source = Get-Content -Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'src/Config-Power.ps1') -Raw
        $source | Should -Not -Match 'Set-ItemProperty|New-ItemProperty|Set-WcdRegistryValue'
    }
}
