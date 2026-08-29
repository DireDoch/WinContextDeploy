Describe 'Config-Applications' {
    BeforeAll {
        $srcDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'src'
        $helpersPath = Join-Path $srcDir 'WcdHelpers.ps1'
        $modulePath  = Join-Path $srcDir 'Config-Applications.ps1'

        if (-not (Test-Path -LiteralPath $helpersPath)) { throw 'WcdHelpers.ps1 introuvable.' }
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

        Mock -CommandName 'Open-WcdApplication' {}
        Mock -CommandName 'Open-WcdInExplorer' {}

        $results = @(Set-WcdApplicationsConfiguration -Usage 'Principal' -OpenApps $false -LogPath $logPath -Config $script:TestConfig)

        if ($script:PesterMajorVersion -ge 5) {
            $results.Count | Should -Be 1
            $results[0].Step | Should -Be 'ApplicationsSkip'
            $results[0].Success | Should -BeTrue
            Assert-MockCalled -CommandName 'Open-WcdApplication' -Times 0
        } else {
            $results.Count | Should Be 1
            $results[0].Step | Should Be 'ApplicationsSkip'
            $results[0].Success | Should Be $true
            Assert-MockCalled 'Open-WcdApplication' 0
        }
    }

    It 'retourne des avertissements pour les applications introuvables' {
        $logPath = Join-Path $TestDrive 'log_apps_missing.txt'

        Mock -CommandName 'Open-WcdApplication' {}
        Mock -CommandName 'Open-WcdInExplorer' {}
        Mock -CommandName 'Start-Process' { throw 'introuvable' } -ParameterFilter { $FilePath -eq 'ms-teams.exe' -or $FilePath -eq 'snippingtool' }
        Mock -CommandName 'Test-Path' { return $false } -ParameterFilter { $LiteralPath -and $LiteralPath -ne $logPath -and $LiteralPath -notlike '*log*' }
        Mock -CommandName 'Get-Process' { return $null } -ParameterFilter { $Name -in @('PanGPA_test', 'pangps_test') }

        $results = @(Set-WcdApplicationsConfiguration -Usage 'Principal' -OpenApps $true -LogPath $logPath -Config $script:TestConfig)

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

        Mock -CommandName 'Open-WcdApplication' {}
        Mock -CommandName 'Open-WcdInExplorer' {}
        Mock -CommandName 'Start-Process' {} -ParameterFilter { $FilePath -eq 'ms-teams.exe' -or $FilePath -eq 'snippingtool' }
        # GlobalProtect detecte via Get-Process (PanGPA_test simule un processus actif)
        Mock -CommandName 'Get-Process' { return [pscustomobject]@{ Name = $Name; Id = 99999 } } -ParameterFilter { $Name -eq 'PanGPA_test' }

        $results = @(Set-WcdApplicationsConfiguration -Usage 'Principal' -OpenApps $true -LogPath $logPath -Config $script:TestConfig)

        if ($script:PesterMajorVersion -ge 5) {
            $results.Count | Should -Be 8
            $successes = @($results | Where-Object { $_.Success -eq $true -and [string]::IsNullOrWhiteSpace($_.Error) -and (-not $_.PSObject.Properties['Severity'] -or $_.Severity -ne 'WARNING') })
            $successes.Count | Should -BeGreaterOrEqual 5
            Assert-MockCalled -CommandName 'Open-WcdApplication' -Times 1 -ParameterFilter { $Path -like '*SoftwareCenter*' }
            Assert-MockCalled -CommandName 'Open-WcdApplication' -Times 1 -ParameterFilter { $Path -like '*Chrome.lnk' }
            Assert-MockCalled -CommandName 'Get-Process' -Times 1 -ParameterFilter { $Name -eq 'PanGPA_test' }
            Assert-MockCalled -CommandName 'Open-WcdInExplorer' -Times 1 -ParameterFilter { $FolderPath -like '*MicroFocus*' }
        } else {
            $results.Count | Should Be 8
            Assert-MockCalled 'Open-WcdApplication' -Times 1 -ParameterFilter { $Path -like '*SoftwareCenter*' }
            Assert-MockCalled 'Open-WcdApplication' -Times 1 -ParameterFilter { $Path -like '*Chrome.lnk' }
            Assert-MockCalled 'Get-Process' -Times 1 -ParameterFilter { $Name -eq 'PanGPA_test' }
            Assert-MockCalled 'Open-WcdInExplorer' -Times 1 -ParameterFilter { $FolderPath -like '*MicroFocus*' }
        }
    }

    It 'ignore Micro Focus silencieusement quand non present' {
        $logPath = Join-Path $TestDrive 'log_apps_nomf.txt'

        Mock -CommandName 'Open-WcdApplication' {}
        Mock -CommandName 'Open-WcdInExplorer' {}
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

        $results = @(Set-WcdApplicationsConfiguration -Usage 'Secondaire' -OpenApps $true -LogPath $logPath -Config $configNoMF)

        $mfResult = $results | Where-Object { $_.Step -eq 'AppMicroFocus' }

        if ($script:PesterMajorVersion -ge 5) {
            $mfResult | Should -Not -BeNullOrEmpty
            $mfResult.Success | Should -BeTrue
            $mfResult.Severity | Should -Be 'INFO'
            Assert-MockCalled -CommandName 'Open-WcdInExplorer' -Times 0
        } else {
            $mfResult | Should Not BeNullOrEmpty
            $mfResult.Success | Should Be $true
            Assert-MockCalled 'Open-WcdInExplorer' 0
        }
    }
}
