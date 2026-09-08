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

        # Le compte est trouve par le SID en -500, jamais par le nom: c est le
        # nom qui peut avoir change, et il est localise.
        function New-TestAdminAccount {
            param([string]$Name = 'Administrator', [bool]$Enabled = $false, [string]$Sid = 'S-1-5-21-1111111111-2222222222-3333333333-500')
            [pscustomobject]@{ Name = $Name; Enabled = $Enabled; SID = $Sid }
        }

        # Un plancher sain que chaque test remplace pour l etape qu il vise.
        function Set-TestSecurityDefaults {
            Mock -CommandName 'Get-WcdWindowsLicenseProduct' { @(New-TestLicense -Status 1) }
            Mock -CommandName 'Get-WcdDefenderStatus' { New-TestDefender }
            Mock -CommandName 'Get-WcdFirewallProfileState' { New-TestFirewall }
            Mock -CommandName 'Get-WcdLocalAdministratorAccount' { New-TestAdminAccount }
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
            $result.Success | Should -BeTrue
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

        It 'avertit quand les trois profils ne sont pas tous rapportes' {
            # Ne juger que les profils revenus rendrait vert un poste dont la
            # lecture n en a ramene qu un, qui est le poste le plus a regarder.
            Set-TestSecurityDefaults
            Mock -CommandName 'Get-WcdFirewallProfileState' {
                @([pscustomobject]@{ Name = 'Domain'; Enabled = $true })
            }

            $result = Set-WcdSecurityStatus -LogPath $script:LogPath | Where-Object Step -eq 'FirewallProfiles'

            $result.Severity | Should -Be 'WARNING'
            $result.Error | Should -Match 'Private'
            $result.Error | Should -Match 'Public'
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

            $results.Count | Should -Be 4
            @($results | ForEach-Object { $_.Step }) | Should -Be @('WindowsActivation', 'AntivirusStatus', 'FirewallProfiles', 'LocalAdminPosture')
        }

        It 'ne change rien sur le poste' {
            # Lecture seule: aucune applet qui ecrit ne doit apparaitre ici.
            $source = Get-Content -Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'src/Config-Security.ps1') -Raw
            $source | Should -Not -Match 'Set-MpPreference|Set-NetFirewallProfile|Enable-NetFirewallRule|Set-CimInstance'
        }
    }

    Context 'posture de l Administrateur integre' {
        BeforeEach {
            Set-TestSecurityDefaults
        }

        It 'rapporte OK quand la posture correspond a la reference' {
            Mock -CommandName 'Get-WcdLocalAdministratorAccount' { New-TestAdminAccount -Name 'ADM-LOCAL' -Enabled $false }

            $result = Set-WcdSecurityStatus -LocalAdministrator @{ Enabled = $false; Renamed = $true } -LogPath $script:LogPath |
                Where-Object Step -eq 'LocalAdminPosture'

            $result.Severity | Should -Be 'INFO'
            $result.Error | Should -Match 'matches the expected posture'
        }

        It 'avertit quand le compte est actif alors qu il devrait etre desactive' {
            Mock -CommandName 'Get-WcdLocalAdministratorAccount' { New-TestAdminAccount -Name 'ADM-LOCAL' -Enabled $true }

            $result = Set-WcdSecurityStatus -LocalAdministrator @{ Enabled = $false; Renamed = $true } -LogPath $script:LogPath |
                Where-Object Step -eq 'LocalAdminPosture'

            $result.Severity | Should -Be 'WARNING'
            $result.RemedyKey | Should -Be 'LocalAdminPosture'
            $result.Error | Should -Match 'expects it disabled'
        }

        It 'avertit quand le nom par defaut subsiste alors qu un renommage est attendu' {
            Mock -CommandName 'Get-WcdLocalAdministratorAccount' { New-TestAdminAccount -Name 'Administrator' -Enabled $false }

            $result = Set-WcdSecurityStatus -LocalAdministrator @{ Enabled = $false; Renamed = $true } -LogPath $script:LogPath |
                Where-Object Step -eq 'LocalAdminPosture'

            $result.Severity | Should -Be 'WARNING'
            $result.Error | Should -Match 'still has the default name'
        }

        It 'reconnait le nom par defaut francais comme non renomme' {
            # Un poste francais qui a toujours Administrateur n a pas ete
            # renomme, et ne doit pas se lire comme s il l avait ete.
            $info = Get-WcdLocalAdminPostureInfo -Account (New-TestAdminAccount -Name 'Administrateur' -Enabled $false) `
                -Expected @{ Renamed = $true }

            $info.Severity | Should -Be 'WARNING'
            $info.Label | Should -Match 'still has the default name'
        }

        It 'trouve un compte renomme par son SID' {
            # Get-LocalUser -Name Administrator echouerait sur exactement les
            # postes correctement configures, d ou le filtre sur -500.
            $accounts = @(
                [pscustomobject]@{ Name = 'Invite';    Enabled = $false; SID = 'S-1-5-21-1-2-3-501' }
                [pscustomobject]@{ Name = 'ADM-LOCAL'; Enabled = $false; SID = 'S-1-5-21-1-2-3-500' }
                [pscustomobject]@{ Name = 'technicien'; Enabled = $true;  SID = 'S-1-5-21-1-2-3-1001' }
            )
            $found = @($accounts | Where-Object { [string]$_.SID -like '*-500' }) | Select-Object -First 1

            $found.Name | Should -Be 'ADM-LOCAL'
        }

        It 'ne juge rien quand le manifeste ne declare aucune reference' {
            # Un atelier sans reference de securite ne doit pas etre averti de ne
            # pas en avoir une.
            Mock -CommandName 'Get-WcdLocalAdministratorAccount' { New-TestAdminAccount -Name 'Administrator' -Enabled $true }

            $result = Set-WcdSecurityStatus -LogPath $script:LogPath | Where-Object Step -eq 'LocalAdminPosture'

            $result.Severity | Should -Be 'INFO'
            $result.Error | Should -Match 'Administrator'
        }

        It 'avertit quand aucun compte -500 n existe' {
            Mock -CommandName 'Get-WcdLocalAdministratorAccount' { $null }

            $result = Set-WcdSecurityStatus -LogPath $script:LogPath | Where-Object Step -eq 'LocalAdminPosture'

            $result.Severity | Should -Be 'WARNING'
        }

        It 'trouve le compte par le suffixe de SID, pas par le nom' {
            $source = Get-Content -Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'src/Config-Security.ps1') -Raw
            $source | Should -Match ([regex]::Escape("Get-LocalUser -ErrorAction Stop | Where-Object { [string]`$_.SID -like '*-500' }"))
        }

        It 'ne peut ni renommer ni desactiver le compte' {
            # La ligne que ce Module ne franchit pas: desactiver l Administrateur
            # integre sans confirmer qu un autre compte peut elever peut enfermer
            # un technicien hors du poste.
            $source = Get-Content -Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'src/Config-Security.ps1') -Raw
            $source | Should -Not -Match 'Rename-LocalUser|Disable-LocalUser|Set-LocalUser|Enable-LocalUser'
        }
    }
}
