Describe 'Config-BitLocker' {
    BeforeAll {
        $srcDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'src'
        $helpersPath = Join-Path $srcDir 'WcdHelpers.ps1'
        $modulePath  = Join-Path $srcDir 'Config-BitLocker.ps1'

        if (-not (Test-Path -LiteralPath $helpersPath)) { throw 'WcdHelpers.ps1 introuvable.' }
        if (-not (Test-Path -LiteralPath $modulePath))  { throw 'Config-BitLocker.ps1 introuvable.' }

        . $helpersPath
        . $modulePath

        # Un TPM present et pret, pour les tests qui ne portent pas sur le TPM.
        function script:New-TestTpm {
            param([bool]$Present = $true, [bool]$Ready = $true)
            return [pscustomobject]@{ TpmPresent = $Present; TpmReady = $Ready }
        }

        # Un volume systeme chiffre, pour les tests qui ne portent pas sur
        # BitLocker.
        function script:New-TestBitLockerVolume {
            param(
                [string]$MountPoint = 'C:',
                [string]$ProtectionStatus = 'On',
                [string]$VolumeStatus = 'FullyEncrypted',
                [int]$EncryptionPercentage = 100
            )
            return [pscustomobject]@{
                MountPoint           = $MountPoint
                ProtectionStatus     = $ProtectionStatus
                VolumeStatus         = $VolumeStatus
                EncryptionPercentage = $EncryptionPercentage
            }
        }
    }

    Context 'TpmReadiness' {
        BeforeAll {
            Mock -CommandName 'Get-WcdSystemBitLockerVolume' { New-TestBitLockerVolume }
        }

        It 'retourne OK quand le TPM est present et pret' {
            $logPath = Join-Path $TestDrive 'log_tpm_ready.txt'

            Mock -CommandName 'Get-WcdTpmStatus' { New-TestTpm }

            $tpm = @(Set-WcdBitLockerStatus -LogPath $logPath | Where-Object { $_.Step -eq 'TpmReadiness' })

            $tpm.Count | Should -Be 1
            $tpm[0].Success | Should -BeTrue
            $tpm[0].Severity | Should -Be 'INFO'
        }

        It 'retourne warning quand aucun TPM n est present' {
            $logPath = Join-Path $TestDrive 'log_tpm_absent.txt'

            Mock -CommandName 'Get-WcdTpmStatus' { New-TestTpm -Present $false -Ready $false }

            $tpm = @(Set-WcdBitLockerStatus -LogPath $logPath | Where-Object { $_.Step -eq 'TpmReadiness' })[0]

            $tpm.Success | Should -BeTrue
            $tpm.Severity | Should -Be 'WARNING'
            $tpm.Error | Should -Match 'No TPM'
            $tpm.RemedyKey | Should -Be 'TpmNotReady'
        }

        It 'retourne warning quand le TPM est present mais pas pret' {
            $logPath = Join-Path $TestDrive 'log_tpm_notready.txt'

            Mock -CommandName 'Get-WcdTpmStatus' { New-TestTpm -Present $true -Ready $false }

            $tpm = @(Set-WcdBitLockerStatus -LogPath $logPath | Where-Object { $_.Step -eq 'TpmReadiness' })[0]

            $tpm.Success | Should -BeTrue
            $tpm.Severity | Should -Be 'WARNING'
            $tpm.Error | Should -Match 'not ready'
            $tpm.RemedyKey | Should -Be 'TpmNotReady'
        }

        It 'rapporte proprement quand Get-Tpm est absent' {
            $logPath = Join-Path $TestDrive 'log_tpm_missing.txt'

            Mock -CommandName 'Get-WcdTpmStatus' { $null }

            $tpm = @(Set-WcdBitLockerStatus -LogPath $logPath | Where-Object { $_.Step -eq 'TpmReadiness' })[0]

            $tpm.Success | Should -BeTrue
            $tpm.Severity | Should -Be 'WARNING'
            $tpm.Error | Should -Match 'Get-Tpm'
        }

        It 'retourne erreur si Get-Tpm echoue' {
            $logPath = Join-Path $TestDrive 'log_tpm_throw.txt'

            Mock -CommandName 'Get-WcdTpmStatus' { throw 'TPM inaccessible' }

            $tpm = @(Set-WcdBitLockerStatus -LogPath $logPath | Where-Object { $_.Step -eq 'TpmReadiness' })[0]

            $tpm.Success | Should -BeFalse
            $tpm.Severity | Should -Be 'ERROR'
            $tpm.Error | Should -Match 'TPM inaccessible'
        }
    }

    Context 'BitLockerStatus' {
        BeforeAll {
            Mock -CommandName 'Get-WcdTpmStatus' { New-TestTpm }
        }

        It 'retourne OK quand le disque systeme est protege' {
            $logPath = Join-Path $TestDrive 'log_bl_protected.txt'

            Mock -CommandName 'Get-WcdSystemBitLockerVolume' { New-TestBitLockerVolume }

            $volume = @(Set-WcdBitLockerStatus -LogPath $logPath | Where-Object { $_.Step -eq 'BitLockerStatus' })[0]

            $volume.Success | Should -BeTrue
            $volume.Severity | Should -Be 'INFO'
            $volume.Error | Should -Match 'C:'
            $volume.Error | Should -Match 'FullyEncrypted'
        }

        It 'retourne warning quand le disque systeme n est pas protege' {
            $logPath = Join-Path $TestDrive 'log_bl_off.txt'

            Mock -CommandName 'Get-WcdSystemBitLockerVolume' {
                New-TestBitLockerVolume -ProtectionStatus 'Off' -VolumeStatus 'FullyDecrypted' -EncryptionPercentage 0
            }

            $volume = @(Set-WcdBitLockerStatus -LogPath $logPath | Where-Object { $_.Step -eq 'BitLockerStatus' })[0]

            $volume.Success | Should -BeTrue
            $volume.Severity | Should -Be 'WARNING'
            $volume.Error | Should -Match 'Not protected'
            $volume.RemedyKey | Should -Be 'BitLockerOff'
        }

        It 'avertit et rapporte le pourcentage pendant le chiffrement' {
            $logPath = Join-Path $TestDrive 'log_bl_progress.txt'

            # Windows bascule ProtectionStatus a On des que les protecteurs
            # existent, bien avant la fin du chiffrement. Un disque a 47 % doit
            # donc avertir malgre ce On: a moitie chiffre n est pas protege.
            Mock -CommandName 'Get-WcdSystemBitLockerVolume' {
                New-TestBitLockerVolume -ProtectionStatus 'On' -VolumeStatus 'EncryptionInProgress' -EncryptionPercentage 47
            }

            $volume = @(Set-WcdBitLockerStatus -LogPath $logPath | Where-Object { $_.Step -eq 'BitLockerStatus' })[0]

            $volume.Success | Should -BeTrue
            $volume.Severity | Should -Be 'WARNING'
            $volume.Error | Should -Match '47'
            $volume.RemedyKey | Should -Be 'BitLockerInProgress'
        }

        It 'rapporte proprement quand les cmdlets BitLocker sont absentes' {
            $logPath = Join-Path $TestDrive 'log_bl_missing.txt'

            Mock -CommandName 'Get-WcdSystemBitLockerVolume' { $null }

            $volume = @(Set-WcdBitLockerStatus -LogPath $logPath | Where-Object { $_.Step -eq 'BitLockerStatus' })[0]

            $volume.Success | Should -BeTrue
            $volume.Severity | Should -Be 'WARNING'
            $volume.Error | Should -Match 'edition'
            $volume.RemedyKey | Should -Be 'BitLockerUnavailable'
        }

        It 'retourne erreur si Get-BitLockerVolume echoue' {
            $logPath = Join-Path $TestDrive 'log_bl_throw.txt'

            Mock -CommandName 'Get-WcdSystemBitLockerVolume' { throw 'Volume introuvable' }

            $volume = @(Set-WcdBitLockerStatus -LogPath $logPath | Where-Object { $_.Step -eq 'BitLockerStatus' })[0]

            $volume.Success | Should -BeFalse
            $volume.Severity | Should -Be 'ERROR'
            $volume.Error | Should -Match 'Volume introuvable'
        }
    }

    Context 'Sans elevation' {
        It 'signale les deux etapes comme exigeant une elevation, sans rien interroger' {
            $logPath = Join-Path $TestDrive 'log_not_elevated.txt'

            Mock -CommandName 'Get-WcdTpmStatus' { New-TestTpm }
            Mock -CommandName 'Get-WcdSystemBitLockerVolume' { New-TestBitLockerVolume }

            $results = @(Set-WcdBitLockerStatus -Elevated $false -LogPath $logPath)

            $results.Count | Should -Be 2
            foreach ($result in $results) {
                $result.Success | Should -BeTrue
                $result.Severity | Should -Be 'WARNING'
                $result.RemedyKey | Should -Be 'RequiresAdmin'
            }

            Should -Invoke -CommandName 'Get-WcdTpmStatus' -Times 0
            Should -Invoke -CommandName 'Get-WcdSystemBitLockerVolume' -Times 0
        }
    }

    Context 'Get-WcdSystemDriveLetter' {
        It 'lit %SystemDrive% et retombe sur C' {
            $original = $env:SystemDrive
            try {
                $env:SystemDrive = 'D:'
                Get-WcdSystemDriveLetter | Should -Be 'D'

                $env:SystemDrive = ''
                Get-WcdSystemDriveLetter | Should -Be 'C'
            } finally {
                $env:SystemDrive = $original
            }
        }
    }
}
