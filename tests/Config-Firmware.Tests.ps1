Describe 'Config-Firmware' {
    BeforeAll {
        $srcDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'src'
        foreach ($file in @('WcdHelpers.ps1', 'Config-Firmware.ps1')) {
            $path = Join-Path $srcDir $file
            if (-not (Test-Path -LiteralPath $path)) { throw ('{0} introuvable.' -f $file) }
            . $path
        }

        # Confirm-SecureBootUEFI n existe pas sous Linux et Mock ne peut pas
        # remplacer une commande absente, d ou les deux adaptateurs minces.
        $script:NotSupported = 'Cmdlet not supported on this platform.'
        $script:AccessDenied = 'Unable to set proper privileges. Access was denied.'
    }

    BeforeEach {
        $script:LogPath = Join-Path $TestDrive ('log_firmware_{0}.txt' -f [guid]::NewGuid())
    }

    Context 'mode d amorcage' {
        It 'rapporte OK sur un poste amorce en UEFI' {
            Mock -CommandName 'Get-WcdFirmwareType' { 'UEFI' }
            Mock -CommandName 'Get-WcdSecureBootState' { $true }

            $result = Set-WcdFirmwareStatus -LogPath $script:LogPath | Where-Object Step -eq 'FirmwareMode'

            $result.Severity | Should -Be 'INFO'
            $result.Error | Should -Match 'UEFI'
        }

        It 'avertit sur un poste amorce en BIOS herite' {
            Mock -CommandName 'Get-WcdFirmwareType' { 'Legacy' }
            Mock -CommandName 'Get-WcdSecureBootState' { throw $script:NotSupported }

            $result = Set-WcdFirmwareStatus -LogPath $script:LogPath | Where-Object Step -eq 'FirmwareMode'

            $result.Severity | Should -Be 'WARNING'
            $result.RemedyKey | Should -Be 'LegacyBios'
        }

        It 'avertit quand Windows ne rapporte aucun mode' {
            Mock -CommandName 'Get-WcdFirmwareType' { '' }
            Mock -CommandName 'Get-WcdSecureBootState' { $true }

            $result = Set-WcdFirmwareStatus -LogPath $script:LogPath | Where-Object Step -eq 'FirmwareMode'

            $result.Severity | Should -Be 'WARNING'
            $result.RemedyKey | Should -Be 'FirmwareModeUnreadable'
        }
    }

    Context 'demarrage securise' {
        It 'rapporte OK quand il est actif sur un poste UEFI' {
            Mock -CommandName 'Get-WcdFirmwareType' { 'UEFI' }
            Mock -CommandName 'Get-WcdSecureBootState' { $true }

            $result = Set-WcdFirmwareStatus -LogPath $script:LogPath | Where-Object Step -eq 'SecureBootState'

            $result.Severity | Should -Be 'INFO'
            $result.Success | Should -BeTrue
        }

        It 'avertit quand il est desactive sur un poste UEFI' {
            Mock -CommandName 'Get-WcdFirmwareType' { 'UEFI' }
            Mock -CommandName 'Get-WcdSecureBootState' { $false }

            $result = Set-WcdFirmwareStatus -LogPath $script:LogPath | Where-Object Step -eq 'SecureBootState'

            $result.Severity | Should -Be 'WARNING'
            $result.RemedyKey | Should -Be 'SecureBootOff'
        }

        It 'rapporte Non applicable sur un BIOS herite, sans planter' {
            # L applet leve sur un poste non UEFI. Ce n est pas une erreur,
            # c est la reponse, et la ligne du mode d amorcage l a deja donnee.
            Mock -CommandName 'Get-WcdFirmwareType' { 'Legacy' }
            Mock -CommandName 'Get-WcdSecureBootState' { throw $script:NotSupported }

            $result = Set-WcdFirmwareStatus -LogPath $script:LogPath | Where-Object Step -eq 'SecureBootState'

            $result.Severity | Should -Be 'NA'
            $result.Success | Should -BeTrue
            $result.Error | Should -Match 'legacy BIOS'
        }

        It 'ne devine pas quand la meme exception arrive sur un poste UEFI' {
            # Meme texte d exception, autre machine: micrologiciel UEFI sans
            # prise en charge du demarrage securise. Le detail doit le dire.
            Mock -CommandName 'Get-WcdFirmwareType' { 'UEFI' }
            Mock -CommandName 'Get-WcdSecureBootState' { throw $script:NotSupported }

            $result = Set-WcdFirmwareStatus -LogPath $script:LogPath | Where-Object Step -eq 'SecureBootState'

            $result.Severity | Should -Be 'WARNING'
            $result.Severity | Should -Not -Be 'NA'
            $result.Error | Should -Match 'cannot tell them apart'
        }

        It 'rapporte le besoin d elevation sans appeler l applet' {
            Mock -CommandName 'Get-WcdFirmwareType' { 'UEFI' }
            Mock -CommandName 'Get-WcdSecureBootState' { $true }

            $result = Set-WcdFirmwareStatus -Elevated $false -LogPath $script:LogPath | Where-Object Step -eq 'SecureBootState'

            $result.Severity | Should -Be 'WARNING'
            $result.RemedyKey | Should -Be 'RequiresAdmin'
            Should -Invoke 'Get-WcdSecureBootState' -Times 0
        }

        It 'traite un acces refuse comme un besoin d elevation' {
            Mock -CommandName 'Get-WcdFirmwareType' { 'UEFI' }
            Mock -CommandName 'Get-WcdSecureBootState' { throw $script:AccessDenied }

            $result = Set-WcdFirmwareStatus -LogPath $script:LogPath | Where-Object Step -eq 'SecureBootState'

            $result.RemedyKey | Should -Be 'RequiresAdmin'
        }

        It 'rapporte proprement une applet absente' {
            Mock -CommandName 'Get-WcdFirmwareType' { 'UEFI' }
            Mock -CommandName 'Get-WcdSecureBootState' { $null }

            $result = Set-WcdFirmwareStatus -LogPath $script:LogPath | Where-Object Step -eq 'SecureBootState'

            $result.Severity | Should -Be 'WARNING'
            $result.RemedyKey | Should -Be 'SecureBootUnreadable'
        }

        It 'rapporte le mode d amorcage meme sans elevation' {
            # C est la raison d etre du Module separe: FirmwareMode ne demande
            # rien et doit continuer a repondre sur une execution non elevee.
            Mock -CommandName 'Get-WcdFirmwareType' { 'UEFI' }
            Mock -CommandName 'Get-WcdSecureBootState' { $true }

            $result = Set-WcdFirmwareStatus -Elevated $false -LogPath $script:LogPath | Where-Object Step -eq 'FirmwareMode'

            $result.Severity | Should -Be 'INFO'
        }
    }

    Context 'contrat du module' {
        It 'produit un resultat par etape' {
            Mock -CommandName 'Get-WcdFirmwareType' { 'UEFI' }
            Mock -CommandName 'Get-WcdSecureBootState' { $true }

            $results = @(Set-WcdFirmwareStatus -LogPath $script:LogPath)

            $results.Count | Should -Be 2
            @($results | ForEach-Object { $_.Step }) | Should -Be @('FirmwareMode', 'SecureBootState')
        }

        It 'ne change rien au micrologiciel' {
            $source = Get-Content -Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'src/Config-Firmware.ps1') -Raw
            $source | Should -Not -Match 'Set-SecureBootUEFI|bcdedit|mbr2gpt\.exe'
        }
    }
}
