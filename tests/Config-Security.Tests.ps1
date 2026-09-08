Describe 'Config-Security' {
    BeforeAll {
        $srcDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'src'
        foreach ($file in @('WcdHelpers.ps1', 'Config-Security.ps1')) {
            $path = Join-Path $srcDir $file
            if (-not (Test-Path -LiteralPath $path)) { throw ('{0} introuvable.' -f $file) }
            . $path
        }

        # Les quatre lectures Windows passent par un adaptateur mince pour cette
        # raison: Get-CimInstance, Get-MpComputerStatus et Get-NetFirewallProfile
        # n existent pas sous Linux, et Mock ne peut pas remplacer une commande
        # absente. Le test simule l adaptateur, jamais l applet Windows.
        function New-TestLicense { param([int]$Status) [pscustomobject]@{ LicenseStatus = $Status } }
        function New-TestDefender {
            param([string]$Mode = 'Normal', [bool]$RealTime = $true, [int]$Age = 1)
            [pscustomobject]@{ AMRunningMode = $Mode; RealTimeProtectionEnabled = $RealTime; AntivirusSignatureAge = $Age }
        }
        function New-TestFirewall {
            param([bool]$Domain = $true, [bool]$Private = $true, [bool]$Public = $true)
            @(
                [pscustomobject]@{ Name = 'Domain';  Enabled = $Domain }
                [pscustomobject]@{ Name = 'Private'; Enabled = $Private }
                [pscustomobject]@{ Name = 'Public';  Enabled = $Public }
            )
        }

        # Un plancher sain que chaque test remplace pour l etape qu il vise.
        function Set-TestSecurityDefaults {
            Mock -CommandName 'Get-WcdWindowsLicenseProduct' { @(New-TestLicense -Status 1) }
            Mock -CommandName 'Get-WcdDefenderStatus' { New-TestDefender }
            Mock -CommandName 'Get-WcdFirewallProfileState' { New-TestFirewall }
        }
    }

    BeforeEach {
        $script:LogPath = Join-Path $TestDrive ('log_security_{0}.txt' -f [guid]::NewGuid())
    }

    Context 'activation Windows' {
        It 'rapporte OK sur un poste active' {
            Set-TestSecurityDefaults
            $result = Set-WcdSecurityStatus -LogPath $script:LogPath | Where-Object Step -eq 'WindowsActivation'

            $result.Success | Should -BeTrue
            $result.Severity | Should -Be 'INFO'
            $result.Error | Should -Match 'activated'
        }

        It 'rapporte une ERREUR sur un poste non active' {
            Set-TestSecurityDefaults
            Mock -CommandName 'Get-WcdWindowsLicenseProduct' { @(New-TestLicense -Status 0) }

            $result = Set-WcdSecurityStatus -LogPath $script:LogPath | Where-Object Step -eq 'WindowsActivation'

            $result.Severity | Should -Be 'ERROR'
            $result.RemedyKey | Should -Be 'WindowsNotActivated'
        }

        It 'rapporte un avertissement pendant la periode de grace' {
            Set-TestSecurityDefaults
            Mock -CommandName 'Get-WcdWindowsLicenseProduct' { @(New-TestLicense -Status 2) }

            $result = Set-WcdSecurityStatus -LogPath $script:LogPath | Where-Object Step -eq 'WindowsActivation'

            $result.Severity | Should -Be 'WARNING'
            $result.Error | Should -Match 'grace'
        }

        It 'retient le pire statut quand plusieurs entrees portent une cle' {
            Set-TestSecurityDefaults
            Mock -CommandName 'Get-WcdWindowsLicenseProduct' { @(New-TestLicense -Status 1), (New-TestLicense -Status 0) }

            $result = Set-WcdSecurityStatus -LogPath $script:LogPath | Where-Object Step -eq 'WindowsActivation'

            $result.Severity | Should -Be 'ERROR'
        }

        It 'traite un statut inconnu comme un avertissement, pas comme un succes' {
            (Get-WcdLicenseStatusInfo -Status 99).Severity | Should -Be 'WARNING'
        }

        It 'avertit quand aucune entree ne porte de cle' {
            Set-TestSecurityDefaults
            Mock -CommandName 'Get-WcdWindowsLicenseProduct' { @() }

            $result = Set-WcdSecurityStatus -LogPath $script:LogPath | Where-Object Step -eq 'WindowsActivation'

            $result.Severity | Should -Be 'WARNING'
        }
    }

    Context 'antivirus' {
        It 'rapporte OK quand Defender tourne en mode Normal' {
            Set-TestSecurityDefaults
            $result = Set-WcdSecurityStatus -LogPath $script:LogPath | Where-Object Step -eq 'AntivirusStatus'

            $result.Severity | Should -Be 'INFO'
            $result.Success | Should -BeTrue
        }

        It 'rapporte Non applicable en mode Passive, jamais une erreur' {
            # Un antivirus tiers qui gere le poste est un poste sain. Le
            # rapporter en erreur serait exactement l erreur que CONTEXT.md
            # tranche avec la visionneuse CAO.
            Set-TestSecurityDefaults
            Mock -CommandName 'Get-WcdDefenderStatus' { New-TestDefender -Mode 'Passive' }

            $result = Set-WcdSecurityStatus -LogPath $script:LogPath | Where-Object Step -eq 'AntivirusStatus'

            $result.Severity | Should -Be 'NA'
            $result.Success | Should -BeTrue
            $result.Error | Should -Match 'Passive'
        }

        It 'rapporte Non applicable en EDR Block Mode' {
            Set-TestSecurityDefaults
            Mock -CommandName 'Get-WcdDefenderStatus' { New-TestDefender -Mode 'EDR Block Mode' }

            $result = Set-WcdSecurityStatus -LogPath $script:LogPath | Where-Object Step -eq 'AntivirusStatus'

            $result.Severity | Should -Be 'NA'
            $result.Error | Should -Match 'EDR Block Mode'
        }

        It 'avertit quand la protection en temps reel est desactivee' {
            Set-TestSecurityDefaults
            Mock -CommandName 'Get-WcdDefenderStatus' { New-TestDefender -RealTime $false }

            $result = Set-WcdSecurityStatus -LogPath $script:LogPath | Where-Object Step -eq 'AntivirusStatus'

            $result.Severity | Should -Be 'WARNING'
            $result.RemedyKey | Should -Be 'RealTimeProtectionOff'
        }

        It 'avertit quand les signatures ont plus de sept jours' {
            Set-TestSecurityDefaults
            Mock -CommandName 'Get-WcdDefenderStatus' { New-TestDefender -Age 30 }

            $result = Set-WcdSecurityStatus -LogPath $script:LogPath | Where-Object Step -eq 'AntivirusStatus'

            $result.Severity | Should -Be 'WARNING'
            $result.RemedyKey | Should -Be 'AntivirusSignaturesStale'
            $result.Error | Should -Match '30 days'
        }

        It 'ne confond pas un Defender absent avec un antivirus eteint' {
            Set-TestSecurityDefaults
            Mock -CommandName 'Get-WcdDefenderStatus' { throw 'The term Get-MpComputerStatus is not recognized.' }

            $result = Set-WcdSecurityStatus -LogPath $script:LogPath | Where-Object Step -eq 'AntivirusStatus'

            $result.Severity | Should -Be 'WARNING'
            $result.RemedyKey | Should -Be 'DefenderUnavailable'
            $result.RemedyKey | Should -Not -Be 'RealTimeProtectionOff'
        }
    }

    Context 'pare-feu' {
        It 'rapporte OK quand les trois profils sont actifs' {
            Set-TestSecurityDefaults
            $result = Set-WcdSecurityStatus -LogPath $script:LogPath | Where-Object Step -eq 'FirewallProfiles'

            $result.Severity | Should -Be 'INFO'
        }

        It 'nomme le profil desactive' {
            Set-TestSecurityDefaults
            Mock -CommandName 'Get-WcdFirewallProfileState' { New-TestFirewall -Public $false }

            $result = Set-WcdSecurityStatus -LogPath $script:LogPath | Where-Object Step -eq 'FirewallProfiles'

            $result.Severity | Should -Be 'WARNING'
            $result.Error | Should -Match 'Public'
            $result.Error | Should -Not -Match 'Domain'
            $result.RemedyKey | Should -Be 'FirewallProfileOff'
        }

        It 'nomme les trois quand tous sont desactives' {
            Set-TestSecurityDefaults
            Mock -CommandName 'Get-WcdFirewallProfileState' { New-TestFirewall -Domain $false -Private $false -Public $false }

            $result = Set-WcdSecurityStatus -LogPath $script:LogPath | Where-Object Step -eq 'FirewallProfiles'

            $result.Severity | Should -Be 'WARNING'
            foreach ($name in @('Domain', 'Private', 'Public')) { $result.Error | Should -Match $name }
        }

        It 'lit le magasin actif, pas la strategie configuree' {
            # Sans ActiveStore, la ligne rapporte ce que le poste a demande et
            # non ce que la strategie de groupe applique reellement.
            $source = Get-Content -Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'src/Config-Security.ps1') -Raw
            $source | Should -Match "Get-NetFirewallProfile -PolicyStore 'ActiveStore'"
        }
    }

    Context 'contrat du module' {
        It 'produit un resultat par etape' {
            Set-TestSecurityDefaults
            $results = @(Set-WcdSecurityStatus -LogPath $script:LogPath)

            $results.Count | Should -Be 3
            @($results | ForEach-Object { $_.Step }) | Should -Be @('WindowsActivation', 'AntivirusStatus', 'FirewallProfiles')
        }

        It 'ne change rien sur le poste' {
            # Lecture seule: aucune applet qui ecrit ne doit apparaitre ici.
            $source = Get-Content -Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'src/Config-Security.ps1') -Raw
            $source | Should -Not -Match 'Set-MpPreference|Set-NetFirewallProfile|Enable-NetFirewallRule|Set-CimInstance'
        }
    }
}
