Describe 'Config-WindowsUpdate' {
    BeforeAll {
        $srcDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'src'
        $helpersPath = Join-Path $srcDir 'WcdHelpers.ps1'
        $modulePath  = Join-Path $srcDir 'Config-WindowsUpdate.ps1'

        if (-not (Test-Path -LiteralPath $helpersPath)) { throw 'WcdHelpers.ps1 introuvable.' }
        if (-not (Test-Path -LiteralPath $modulePath))  { throw 'Config-WindowsUpdate.ps1 introuvable.' }

        . $helpersPath
        . $modulePath

        # Une entree d historique telle que QueryHistory la retourne.
        function script:New-TestHistoryEntry {
            param(
                [string]$Title = '2026-08 Cumulative Update for Windows 11 (KB5031354)',
                [int]$ResultCode = 2,
                [int]$HResult = 0,
                [int]$DaysAgo = 1
            )
            return [pscustomobject]@{
                Title      = $Title
                ResultCode = $ResultCode
                HResult    = $HResult
                Date       = [DateTime]::UtcNow.AddDays(-$DaysAgo)
            }
        }

        function script:New-TestHistory {
            param([object[]]$Entries = @(), [bool]$Available = $true)
            return [pscustomobject]@{ Available = $Available; Entries = @($Entries) }
        }
    }

    Context 'WindowsUpdateHistory' {
        It 'retourne OK quand l historique recent est propre' {
            $logPath = Join-Path $TestDrive 'log_wu_clean.txt'
            Mock -CommandName 'Get-WcdWindowsUpdateHistory' { New-TestHistory -Entries @(New-TestHistoryEntry) }
            Mock -CommandName 'Test-WcdWindowsUpdateRebootPending' { $false }

            $history = @(Set-WcdWindowsUpdateStatus -LogPath $logPath | Where-Object { $_.Step -eq 'WindowsUpdateHistory' })[0]

            $history.Success | Should -BeTrue
            $history.Severity | Should -Be 'INFO'
        }

        It 'avertit et nomme la mise a jour en echec avec son HRESULT' {
            $logPath = Join-Path $TestDrive 'log_wu_one.txt'
            Mock -CommandName 'Get-WcdWindowsUpdateHistory' {
                New-TestHistory -Entries @(
                    New-TestHistoryEntry
                    New-TestHistoryEntry -Title 'Security Update (KB5030219)' -ResultCode 4 -HResult -2145124329
                )
            }
            Mock -CommandName 'Test-WcdWindowsUpdateRebootPending' { $false }

            $history = @(Set-WcdWindowsUpdateStatus -LogPath $logPath | Where-Object { $_.Step -eq 'WindowsUpdateHistory' })[0]

            $history.Severity | Should -Be 'WARNING'
            # une etape qui rapporte n est pas une etape cassee
            $history.Success | Should -BeTrue
            $history.Error | Should -Match 'KB5030219'
            $history.Error | Should -Match '0x80240017'
            $history.RemedyKey | Should -Be 'WindowsUpdateFailed'
        }

        It 'compte les echecs et n en nomme que les premiers' {
            $logPath = Join-Path $TestDrive 'log_wu_many.txt'
            Mock -CommandName 'Get-WcdWindowsUpdateHistory' {
                New-TestHistory -Entries @(1..5 | ForEach-Object {
                    New-TestHistoryEntry -Title ("Update KB50000{0}" -f $_) -ResultCode 4 -HResult -2145124329
                })
            }
            Mock -CommandName 'Test-WcdWindowsUpdateRebootPending' { $false }

            $history = @(Set-WcdWindowsUpdateStatus -LogPath $logPath | Where-Object { $_.Step -eq 'WindowsUpdateHistory' })[0]

            $history.Severity | Should -Be 'WARNING'
            $history.Error | Should -Match '\(5\)'
            $history.Error | Should -Match '\+2 more'
        }

        It 'ignore l historique plus vieux que la fenetre retenue' {
            $logPath = Join-Path $TestDrive 'log_wu_old.txt'
            Mock -CommandName 'Get-WcdWindowsUpdateHistory' {
                # Un poste reimage par-dessus une ancienne installation porte un
                # historique qui ne concerne pas ce deploiement.
                New-TestHistory -Entries @(New-TestHistoryEntry -ResultCode 4 -HResult -2145124329 -DaysAgo 90)
            }
            Mock -CommandName 'Test-WcdWindowsUpdateRebootPending' { $false }

            $history = @(Set-WcdWindowsUpdateStatus -LogPath $logPath | Where-Object { $_.Step -eq 'WindowsUpdateHistory' })[0]

            $history.Severity | Should -Be 'INFO'
        }

        It 'traite un agent Windows Update absent comme une note, pas un plantage' {
            $logPath = Join-Path $TestDrive 'log_wu_nocom.txt'
            Mock -CommandName 'Get-WcdWindowsUpdateHistory' { New-TestHistory -Available $false }
            Mock -CommandName 'Test-WcdWindowsUpdateRebootPending' { $false }

            $history = @(Set-WcdWindowsUpdateStatus -LogPath $logPath | Where-Object { $_.Step -eq 'WindowsUpdateHistory' })[0]

            $history.Success | Should -BeTrue
            $history.Severity | Should -Be 'INFO'
            $history.Error | Should -Match 'Windows Update Agent'
        }
    }

    Context 'WindowsUpdateReboot' {
        BeforeEach {
            Mock -CommandName 'Get-WcdWindowsUpdateHistory' { New-TestHistory -Entries @(New-TestHistoryEntry) }
        }

        It 'avertit quand la cle RebootRequired existe' {
            $logPath = Join-Path $TestDrive 'log_wu_reboot.txt'
            Mock -CommandName 'Test-WcdWindowsUpdateRebootPending' { $true }

            $reboot = @(Set-WcdWindowsUpdateStatus -LogPath $logPath | Where-Object { $_.Step -eq 'WindowsUpdateReboot' })[0]

            $reboot.Severity | Should -Be 'WARNING'
            $reboot.Success | Should -BeTrue
            $reboot.RemedyKey | Should -Be 'RebootPending'
            # lu par la checklist, qui n affiche qu une seule ligne de redemarrage
            $reboot.RebootPending | Should -BeTrue
        }

        It 'retourne OK quand la cle est absente' {
            $logPath = Join-Path $TestDrive 'log_wu_noreboot.txt'
            Mock -CommandName 'Test-WcdWindowsUpdateRebootPending' { $false }

            $reboot = @(Set-WcdWindowsUpdateStatus -LogPath $logPath | Where-Object { $_.Step -eq 'WindowsUpdateReboot' })[0]

            $reboot.Severity | Should -Be 'INFO'
            $reboot.RebootPending | Should -BeFalse
        }
    }

    Context 'Format-WcdFailedUpdateSummary' {
        It 'nomme le titre et le HRESULT en hexadecimal' {
            $summary = Format-WcdFailedUpdateSummary -Updates @(
                New-TestHistoryEntry -Title 'Security Update (KB5030219)' -ResultCode 4 -HResult -2145124329
            )

            $summary | Should -Be 'Security Update (KB5030219) (HRESULT 0x80240017)'
        }

        It 'remplace un titre vide plutot que de laisser une ligne muette' {
            $summary = Format-WcdFailedUpdateSummary -Updates @(
                New-TestHistoryEntry -Title '' -ResultCode 4 -HResult 0
            )

            $summary | Should -Match 'Unnamed update'
        }
    }
}
