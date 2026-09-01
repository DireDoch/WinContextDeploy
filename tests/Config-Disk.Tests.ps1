Describe 'Config-Disk' {
    BeforeAll {
        $srcDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'src'
        $helpersPath = Join-Path $srcDir 'WcdHelpers.ps1'
        $modulePath  = Join-Path $srcDir 'Config-Disk.ps1'

        if (-not (Test-Path -LiteralPath $helpersPath)) { throw 'WcdHelpers.ps1 introuvable.' }
        if (-not (Test-Path -LiteralPath $modulePath))  { throw 'Config-Disk.ps1 introuvable.' }

        . $helpersPath
        . $modulePath

        # Un volume systeme large et sain, pour les tests qui ne portent pas
        # sur l espace libre.
        function script:New-TestVolume {
            param([double]$FreeGB = 400, [double]$TotalGB = 476)
            return [pscustomobject]@{
                DriveLetter   = 'C'
                Size          = $TotalGB * 1GB
                SizeRemaining = $FreeGB * 1GB
            }
        }
    }

    Context 'DiskHealth' {
        It 'retourne OK quand tous les disques fixes sont sains' {
            $logPath = Join-Path $TestDrive 'log_disk_healthy.txt'

            Mock -CommandName 'Get-WcdPhysicalDisks' {
                @(
                    [pscustomobject]@{ FriendlyName = 'Samsung SSD 990'; SerialNumber = 'S6Z1'; HealthStatus = 'Healthy'; BusType = 'NVMe' }
                )
            }
            Mock -CommandName 'Get-WcdSystemVolume' { New-TestVolume }

            $health = @(Set-WcdDiskStatus -LogPath $logPath | Where-Object { $_.Step -eq 'DiskHealth' })

            $health.Count | Should -Be 1
            $health[0].Success | Should -BeTrue
            $health[0].Severity | Should -Be 'INFO'
            $health[0].Error | Should -Be ''
        }

        It 'retourne erreur et nomme le disque quand il est Unhealthy' {
            $logPath = Join-Path $TestDrive 'log_disk_unhealthy.txt'

            Mock -CommandName 'Get-WcdPhysicalDisks' {
                @(
                    [pscustomobject]@{ FriendlyName = 'WDC WD10EZEX'; SerialNumber = 'WD-WCC6Y1234567'; HealthStatus = 'Unhealthy'; BusType = 'SATA' }
                )
            }
            Mock -CommandName 'Get-WcdSystemVolume' { New-TestVolume }

            $health = @(Set-WcdDiskStatus -LogPath $logPath | Where-Object { $_.Step -eq 'DiskHealth' })[0]

            $health.Success | Should -BeFalse
            $health.Severity | Should -Be 'ERROR'
            $health.Error | Should -Match 'WDC WD10EZEX'
            $health.Error | Should -Match 'WD-WCC6Y1234567'
            $health.RemedyKey | Should -Be 'DiskUnhealthy'
            $health.RemedyArgs[0] | Should -Match 'WDC WD10EZEX'
        }

        It 'retourne warning quand un disque est en Warning' {
            $logPath = Join-Path $TestDrive 'log_disk_warning.txt'

            Mock -CommandName 'Get-WcdPhysicalDisks' {
                @(
                    [pscustomobject]@{ FriendlyName = 'Kingston A400'; SerialNumber = ''; HealthStatus = 'Warning'; BusType = 'SATA' }
                )
            }
            Mock -CommandName 'Get-WcdSystemVolume' { New-TestVolume }

            $health = @(Set-WcdDiskStatus -LogPath $logPath | Where-Object { $_.Step -eq 'DiskHealth' })[0]

            $health.Success | Should -BeTrue
            $health.Severity | Should -Be 'WARNING'
            $health.Error | Should -Match 'Kingston A400'
        }

        It 'ignore une cle USB en mauvaise sante' {
            $logPath = Join-Path $TestDrive 'log_disk_usb.txt'

            Mock -CommandName 'Get-WcdPhysicalDisks' {
                @(
                    [pscustomobject]@{ FriendlyName = 'Samsung SSD 990'; SerialNumber = 'S6Z1'; HealthStatus = 'Healthy'; BusType = 'NVMe' }
                    [pscustomobject]@{ FriendlyName = 'SanDisk Cruzer'; SerialNumber = '4C53'; HealthStatus = 'Unhealthy'; BusType = 'USB' }
                )
            }
            Mock -CommandName 'Get-WcdSystemVolume' { New-TestVolume }

            $health = @(Set-WcdDiskStatus -LogPath $logPath | Where-Object { $_.Step -eq 'DiskHealth' })[0]

            $health.Success | Should -BeTrue
            $health.Severity | Should -Be 'INFO'
        }

        It 'retourne erreur si Get-PhysicalDisk echoue' {
            $logPath = Join-Path $TestDrive 'log_disk_throw.txt'

            Mock -CommandName 'Get-WcdPhysicalDisks' { throw 'Storage indisponible' }
            Mock -CommandName 'Get-WcdSystemVolume' { New-TestVolume }

            $health = @(Set-WcdDiskStatus -LogPath $logPath | Where-Object { $_.Step -eq 'DiskHealth' })[0]

            $health.Success | Should -BeFalse
            $health.Severity | Should -Be 'ERROR'
            $health.Error | Should -Match 'Storage indisponible'
        }
    }

    Context 'DiskFreeSpace' {
        BeforeAll {
            Mock -CommandName 'Get-WcdPhysicalDisks' {
                @([pscustomobject]@{ FriendlyName = 'Samsung SSD 990'; SerialNumber = 'S6Z1'; HealthStatus = 'Healthy'; BusType = 'NVMe' })
            }
        }

        It 'retourne OK et rapporte le chiffre au-dessus du seuil' {
            $logPath = Join-Path $TestDrive 'log_space_ok.txt'

            Mock -CommandName 'Get-WcdSystemVolume' { New-TestVolume -FreeGB 412 -TotalGB 476 }

            $space = @(Set-WcdDiskStatus -LogPath $logPath | Where-Object { $_.Step -eq 'DiskFreeSpace' })[0]

            $space.Success | Should -BeTrue
            $space.Severity | Should -Be 'INFO'
            $space.Error | Should -Be '412 GB free of 476 GB'
        }

        It 'retourne warning sous le seuil, avec la remediation' {
            $logPath = Join-Path $TestDrive 'log_space_low.txt'

            Mock -CommandName 'Get-WcdSystemVolume' { New-TestVolume -FreeGB 8 -TotalGB 128 }

            $space = @(Set-WcdDiskStatus -LogPath $logPath | Where-Object { $_.Step -eq 'DiskFreeSpace' })[0]

            $space.Success | Should -BeTrue
            $space.Severity | Should -Be 'WARNING'
            $space.Error | Should -Match '8 GB free of 128 GB'
            $space.Error | Should -Match '20 GB threshold'
            $space.RemedyKey | Should -Be 'DiskLowFreeSpace'
        }

        It 'respecte Disk.MinFreeGB du manifeste' {
            $logPath = Join-Path $TestDrive 'log_space_threshold.txt'

            Mock -CommandName 'Get-WcdSystemVolume' { New-TestVolume -FreeGB 40 -TotalGB 476 }

            $config = @{ Disk = @{ MinFreeGB = 100 } }
            $space = @(Set-WcdDiskStatus -LogPath $logPath -Config $config | Where-Object { $_.Step -eq 'DiskFreeSpace' })[0]

            $space.Severity | Should -Be 'WARNING'
            $space.Error | Should -Match '100 GB threshold'
        }

        It 'ne laisse pas l arrondi franchir le seuil' {
            $logPath = Join-Path $TestDrive 'log_space_rounding.txt'

            # 19,6 Go reste sous un seuil de 20 Go, et le chiffre affiche est
            # tronque et non arrondi: "20 GB free ... below the 20 GB threshold"
            # se lirait comme un bogue.
            Mock -CommandName 'Get-WcdSystemVolume' { New-TestVolume -FreeGB 19.6 -TotalGB 256 }

            $space = @(Set-WcdDiskStatus -LogPath $logPath | Where-Object { $_.Step -eq 'DiskFreeSpace' })[0]

            $space.Severity | Should -Be 'WARNING'
            $space.Error | Should -Be '19 GB free of 256 GB, below the 20 GB threshold.'
        }

        It 'retourne erreur si Get-Volume echoue' {
            $logPath = Join-Path $TestDrive 'log_space_throw.txt'

            Mock -CommandName 'Get-WcdSystemVolume' { throw 'Volume introuvable' }

            $space = @(Set-WcdDiskStatus -LogPath $logPath | Where-Object { $_.Step -eq 'DiskFreeSpace' })[0]

            $space.Success | Should -BeFalse
            $space.Severity | Should -Be 'ERROR'
            $space.Error | Should -Match 'Volume introuvable'
        }
    }

    Context 'Get-WcdMinimumFreeGB' {
        It 'retombe sur 20 Go quand la cle est absente ou invalide' {
            Get-WcdMinimumFreeGB | Should -Be 20
            Get-WcdMinimumFreeGB -Config @{} | Should -Be 20
            Get-WcdMinimumFreeGB -Config @{ Disk = @{ MinFreeGB = 'beaucoup' } } | Should -Be 20
            Get-WcdMinimumFreeGB -Config @{ Disk = @{ MinFreeGB = 0 } } | Should -Be 20
            Get-WcdMinimumFreeGB -Config @{ Disk = @{ MinFreeGB = 50 } } | Should -Be 50
        }
    }
}
