Describe 'Config-Applications' {
    BeforeAll {
        $helpersPath = Join-Path $PSScriptRoot 'MinimalHelpers.ps1'
        $modulePath  = Join-Path $PSScriptRoot 'Config-Applications.ps1'

        if (-not (Test-Path -LiteralPath $helpersPath)) {
            $helpersPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'tests/MinimalHelpers.ps1'
        }
        if (-not (Test-Path -LiteralPath $modulePath)) {
            $modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'tests/Config-Applications.ps1'
        }

        if (-not (Test-Path -LiteralPath $helpersPath)) { throw 'MinimalHelpers.ps1 introuvable.' }
        if (-not (Test-Path -LiteralPath $modulePath))  { throw 'Config-Applications.ps1 introuvable.' }

        . $helpersPath
        . $modulePath

        $script:PesterMajorVersion = (Get-Module -Name Pester | Select-Object -First 1).Version.Major

        # Config de test avec chemins bidon
        $script:TestConfig = @{
            Applications = @{
                SoftwareCenter            = (Join-Path $TestDrive 'SoftwareCenter.lnk')
                Outlook                   = (Join-Path $TestDrive 'Outlook.lnk')
                ChromePath                = (Join-Path $TestDrive 'Chrome.lnk')
                TeamsExe                  = 'ms-teams.exe'
                SnipItExe                 = 'snippingtool'
                GlobalProtectProcessNames = @('PanGPA_test', 'pangps_test')
                MicroFocus                = (Join-Path $TestDrive 'MicroFocus')
                ServiceNowUrl             = 'https://example.com/servicenow'
            }
        }
    }

    It 'retourne un skip quand OpenApps est false' {
        $logPath = Join-Path $TestDrive 'log_apps_skip.txt'

        Mock -CommandName 'Open-MinimalApplication' {}
        Mock -CommandName 'Open-MinimalInExplorer' {}

        $results = @(Set-MinimalApplicationsConfiguration -Usage 'Principal' -OpenApps $false -LogPath $logPath -Config $script:TestConfig)

        if ($script:PesterMajorVersion -ge 5) {
            $results.Count | Should -Be 1
            $results[0].Step | Should -Be 'ApplicationsSkip'
            $results[0].Success | Should -BeTrue
            Assert-MockCalled -CommandName 'Open-MinimalApplication' -Times 0
        } else {
            $results.Count | Should Be 1
            $results[0].Step | Should Be 'ApplicationsSkip'
            $results[0].Success | Should Be $true
            Assert-MockCalled 'Open-MinimalApplication' 0
        }
    }

    It 'retourne des avertissements pour les applications introuvables' {
        $logPath = Join-Path $TestDrive 'log_apps_missing.txt'

        Mock -CommandName 'Open-MinimalApplication' {}
        Mock -CommandName 'Open-MinimalInExplorer' {}
        Mock -CommandName 'Start-Process' { throw 'introuvable' } -ParameterFilter { $FilePath -eq 'ms-teams.exe' -or $FilePath -eq 'snippingtool' }
        Mock -CommandName 'Test-Path' { return $false } -ParameterFilter { $LiteralPath -and $LiteralPath -ne $logPath -and $LiteralPath -notlike '*log*' }
        Mock -CommandName 'Get-Process' { return $null } -ParameterFilter { $Name -in @('PanGPA_test', 'pangps_test') }

        $results = @(Set-MinimalApplicationsConfiguration -Usage 'Principal' -OpenApps $true -LogPath $logPath -Config $script:TestConfig)

        if ($script:PesterMajorVersion -ge 5) {
            $results.Count | Should -BeGreaterOrEqual 8
            ($results | Where-Object Step -eq 'AppChrome').Severity | Should -Be 'WARNING'
            # Software Center, Outlook, Chrome, Teams, SnipIt, GlobalProtect introuvables = WARNING
            $warnings = @($results | Where-Object { $_.PSObject.Properties['Severity'] -and $_.Severity -eq 'WARNING' })
            $warnings.Count | Should -BeGreaterOrEqual 4
        } else {
            $results.Count | Should BeGreaterOrEqual 8
        }
    }

    It 'ouvre les applications trouvees avec succes' {
        $logPath = Join-Path $TestDrive 'log_apps_success.txt'

        # Creer les fichiers fictifs
        New-Item -Path (Join-Path $TestDrive 'SoftwareCenter.lnk') -ItemType File -Force | Out-Null
        New-Item -Path (Join-Path $TestDrive 'Outlook.lnk') -ItemType File -Force | Out-Null
        New-Item -Path (Join-Path $TestDrive 'Chrome.lnk') -ItemType File -Force | Out-Null
        New-Item -Path (Join-Path $TestDrive 'MicroFocus') -ItemType Directory -Force | Out-Null

        Mock -CommandName 'Open-MinimalApplication' {}
        Mock -CommandName 'Open-MinimalInExplorer' {}
        Mock -CommandName 'Start-Process' {} -ParameterFilter { $FilePath -eq 'ms-teams.exe' -or $FilePath -eq 'snippingtool' }
        # GlobalProtect detecte via Get-Process (PanGPA_test simule un processus actif)
        Mock -CommandName 'Get-Process' { return [pscustomobject]@{ Name = $Name; Id = 99999 } } -ParameterFilter { $Name -eq 'PanGPA_test' }

        $results = @(Set-MinimalApplicationsConfiguration -Usage 'Principal' -OpenApps $true -LogPath $logPath -Config $script:TestConfig)

        if ($script:PesterMajorVersion -ge 5) {
            $results.Count | Should -Be 8
            $successes = @($results | Where-Object { $_.Success -eq $true -and [string]::IsNullOrWhiteSpace($_.Error) -and (-not $_.PSObject.Properties['Severity'] -or $_.Severity -ne 'WARNING') })
            $successes.Count | Should -BeGreaterOrEqual 5
            Assert-MockCalled -CommandName 'Open-MinimalApplication' -Times 1 -ParameterFilter { $Path -like '*SoftwareCenter*' }
            Assert-MockCalled -CommandName 'Open-MinimalApplication' -Times 1 -ParameterFilter { $Path -like '*Chrome.lnk' }
            Assert-MockCalled -CommandName 'Get-Process' -Times 1 -ParameterFilter { $Name -eq 'PanGPA_test' }
            Assert-MockCalled -CommandName 'Open-MinimalInExplorer' -Times 1 -ParameterFilter { $FolderPath -like '*MicroFocus*' }
        } else {
            $results.Count | Should Be 8
            Assert-MockCalled 'Open-MinimalApplication' -Times 1 -ParameterFilter { $Path -like '*SoftwareCenter*' }
            Assert-MockCalled 'Open-MinimalApplication' -Times 1 -ParameterFilter { $Path -like '*Chrome.lnk' }
            Assert-MockCalled 'Get-Process' -Times 1 -ParameterFilter { $Name -eq 'PanGPA_test' }
            Assert-MockCalled 'Open-MinimalInExplorer' -Times 1 -ParameterFilter { $FolderPath -like '*MicroFocus*' }
        }
    }

    It 'ignore Micro Focus silencieusement quand non present' {
        $logPath = Join-Path $TestDrive 'log_apps_nomf.txt'

        Mock -CommandName 'Open-MinimalApplication' {}
        Mock -CommandName 'Open-MinimalInExplorer' {}
        Mock -CommandName 'Start-Process' { throw 'introuvable' } -ParameterFilter { $FilePath -eq 'nope.exe' }

        $configNoMF = @{
            Applications = @{
                SoftwareCenter            = (Join-Path $TestDrive 'nonexistent_sc')
                Outlook                   = (Join-Path $TestDrive 'nonexistent_ol')
                ChromePath                = (Join-Path $TestDrive 'nonexistent_chrome')
                TeamsExe                  = 'nope.exe'
                SnipItExe                 = 'nope.exe'
                GlobalProtectProcessNames = @('PanGPA_absent', 'pangps_absent')
                MicroFocus                = (Join-Path $TestDrive 'nonexistent_mf')
                ServiceNowUrl             = 'https://example.com/sn'
            }
        }

        $results = @(Set-MinimalApplicationsConfiguration -Usage 'Secondaire' -OpenApps $true -LogPath $logPath -Config $configNoMF)

        $mfResult = $results | Where-Object { $_.Step -eq 'AppMicroFocus' }

        if ($script:PesterMajorVersion -ge 5) {
            $mfResult | Should -Not -BeNullOrEmpty
            $mfResult.Success | Should -BeTrue
            $mfResult.Severity | Should -Be 'INFO'
            Assert-MockCalled -CommandName 'Open-MinimalInExplorer' -Times 0
        } else {
            $mfResult | Should Not BeNullOrEmpty
            $mfResult.Success | Should Be $true
            Assert-MockCalled 'Open-MinimalInExplorer' 0
        }
    }
}
