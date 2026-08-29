Describe 'Config-Usage' {
    BeforeAll {
        $srcDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'src'
        $helpersPath = Join-Path $srcDir 'WcdHelpers.ps1'
        $modulePath  = Join-Path $srcDir 'Config-Usage.ps1'

        if (-not (Test-Path -LiteralPath $helpersPath)) { throw 'WcdHelpers.ps1 introuvable.' }
        if (-not (Test-Path -LiteralPath $modulePath))  { throw 'Config-Usage.ps1 introuvable.' }

        . $helpersPath
        . $modulePath

        $script:PesterMajorVersion = (Get-Module -Name Pester | Select-Object -First 1).Version.Major

        $script:TestConfig = @{
            Principal = @{
                SAPPath = (Join-Path $TestDrive 'SAP')
            }
            Citrix = @{
                DownloadUrl = 'https://example.com/citrix'
            }
        }
    }

    It 'retourne 1 etape pour un poste principal (SAP)' {
        $logPath = Join-Path $TestDrive 'log_usage_principal.txt'

        Mock -CommandName 'Open-WcdExplorer' {}
        Mock -CommandName 'Open-WcdUrl' {}

        # Creer le dossier SAP de test
        New-Item -Path (Join-Path $TestDrive 'SAP') -ItemType Directory -Force | Out-Null

        $results = @(Set-WcdUsageConfiguration -Environment 'Workstation' -LogPath $logPath -Config $script:TestConfig)

        if ($script:PesterMajorVersion -ge 5) {
            $results.Count | Should -Be 1
            $results[0].Step | Should -Be 'SAPFrontEnd'
            $results[0].Success | Should -BeTrue
            Assert-MockCalled -CommandName 'Open-WcdExplorer' -Times 1
        } else {
            $results.Count | Should Be 1
            $results[0].Step | Should Be 'SAPFrontEnd'
            Assert-MockCalled 'Open-WcdExplorer' 1
        }
    }

    It 'avertit quand SAP est introuvable sur un poste principal' {
        $logPath = Join-Path $TestDrive 'log_usage_nosap.txt'

        Mock -CommandName 'Open-WcdExplorer' {}

        $noSapConfig = @{
            Principal = @{
                SAPPath = (Join-Path $TestDrive 'nonexistent_sap')
            }
        }

        $results = @(Set-WcdUsageConfiguration -Environment 'Workstation' -LogPath $logPath -Config $noSapConfig)
        $sapResult = $results | Where-Object { $_.Step -eq 'SAPFrontEnd' }

        if ($script:PesterMajorVersion -ge 5) {
            $sapResult | Should -Not -BeNullOrEmpty
            $sapResult.Success | Should -BeTrue
            $sapResult.Severity | Should -Be 'WARNING'
            $sapResult.Error | Should -Match 'introuvable'
        } else {
            $sapResult | Should Not BeNullOrEmpty
            $sapResult.Success | Should Be $true
            $sapResult.Error | Should Match 'introuvable'
        }
    }

    It 'ouvre Citrix pour un poste secondaire' {
        $logPath = Join-Path $TestDrive 'log_usage_secondaire.txt'

        Mock -CommandName 'Open-WcdUrl' {}

        $results = @(Set-WcdUsageConfiguration -Environment 'Vdi' -LogPath $logPath -Config $script:TestConfig)

        if ($script:PesterMajorVersion -ge 5) {
            $results.Count | Should -Be 1
            $results[0].Step | Should -Be 'UsageCitrix'
            $results[0].Success | Should -BeTrue
            Assert-MockCalled -CommandName 'Open-WcdUrl' -Times 1 -ParameterFilter { $Url -eq 'https://example.com/citrix' }
        } else {
            $results.Count | Should Be 1
            $results[0].Step | Should Be 'UsageCitrix'
            $results[0].Success | Should Be $true
            Assert-MockCalled 'Open-WcdUrl' 1
        }
    }

    It 'retourne une erreur si Citrix ne peut pas etre ouvert' {
        $logPath = Join-Path $TestDrive 'log_usage_error.txt'

        Mock -CommandName 'Open-WcdUrl' { throw 'Navigation bloquee' }

        $results = @(Set-WcdUsageConfiguration -Environment 'Vdi' -LogPath $logPath -Config $script:TestConfig)

        if ($script:PesterMajorVersion -ge 5) {
            $results[0].Success | Should -BeFalse
            $results[0].Error | Should -Match 'Navigation bloquee'
        } else {
            $results[0].Success | Should Be $false
            $results[0].Error | Should Match 'Navigation bloquee'
        }
    }
}