Describe 'Config-Engineer' {
    BeforeAll {
        $helpersPath = Join-Path $PSScriptRoot 'MinimalHelpers.ps1'
        $modulePath  = Join-Path $PSScriptRoot 'Config-Engineer.ps1'

        if (-not (Test-Path -LiteralPath $helpersPath)) {
            $helpersPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'tests/MinimalHelpers.ps1'
        }
        if (-not (Test-Path -LiteralPath $modulePath)) {
            $modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'tests/Config-Engineer.ps1'
        }

        if (-not (Test-Path -LiteralPath $helpersPath)) { throw 'MinimalHelpers.ps1 introuvable.' }
        if (-not (Test-Path -LiteralPath $modulePath))  { throw 'Config-Engineer.ps1 introuvable.' }

        . $helpersPath
        . $modulePath

        $script:PesterMajorVersion = (Get-Module -Name Pester | Select-Object -First 1).Version.Major

        $script:TestConfig = @{
            Engineer = @{
                NvidiaUrl   = 'https://example.com/nvidia'
                GPSUrl      = 'https://example.com/gps'
                ChromePath  = (Join-Path $TestDrive 'chrome.lnk')
            }
        }
    }

    It 'ne fait rien quand EngineerTypes est Non' {
        $logPath = Join-Path $TestDrive 'log_eng_non.txt'

        Mock -CommandName 'Open-MinimalUrlInChrome' {}
        Mock -CommandName 'Open-MinimalShortcut' {}

        $results = @(Set-MinimalEngineerConfiguration -EngineerTypes @('Non') -LogPath $logPath -Config $script:TestConfig)

        if ($script:PesterMajorVersion -ge 5) {
            $results.Count | Should -Be 1
            $results[0].Step | Should -Be 'EngineerSkip'
            $results[0].Success | Should -BeTrue
            Assert-MockCalled -CommandName 'Open-MinimalUrlInChrome' -Times 0
            Assert-MockCalled -CommandName 'Open-MinimalShortcut' -Times 0
        } else {
            $results.Count | Should Be 1
            $results[0].Step | Should Be 'EngineerSkip'
            $results[0].Success | Should Be $true
            Assert-MockCalled 'Open-MinimalUrlInChrome' 0
            Assert-MockCalled 'Open-MinimalShortcut' 0
        }
    }

    It 'ouvre Nvidia quand EngineerTypes contient Nvidia' {
        $logPath = Join-Path $TestDrive 'log_eng_nvidia.txt'

        Mock -CommandName 'Open-MinimalUrlInChrome' {}

        $results = @(Set-MinimalEngineerConfiguration -EngineerTypes @('Nvidia') -LogPath $logPath -Config $script:TestConfig)

        if ($script:PesterMajorVersion -ge 5) {
            $results.Count | Should -Be 1
            $results[0].Step | Should -Be 'EngineerNvidia'
            $results[0].Success | Should -BeTrue
            Assert-MockCalled -CommandName 'Open-MinimalUrlInChrome' -Times 1 -ParameterFilter { $Url -eq 'https://example.com/nvidia' }
        } else {
            $results.Count | Should Be 1
            $results[0].Step | Should Be 'EngineerNvidia'
            $results[0].Success | Should Be $true
            Assert-MockCalled 'Open-MinimalUrlInChrome' 1
        }
    }

    It 'ouvre GPS quand EngineerTypes contient GPS' {
        $logPath = Join-Path $TestDrive 'log_eng_gps.txt'

        Mock -CommandName 'Open-MinimalUrlInChrome' {}

        $results = @(Set-MinimalEngineerConfiguration -EngineerTypes @('GPS') -LogPath $logPath -Config $script:TestConfig)

        if ($script:PesterMajorVersion -ge 5) {
            $results.Count | Should -Be 1
            $results[0].Step | Should -Be 'EngineerGPS'
            $results[0].Success | Should -BeTrue
            Assert-MockCalled -CommandName 'Open-MinimalUrlInChrome' -Times 1 -ParameterFilter { $Url -eq 'https://example.com/gps' }
        } else {
            $results.Count | Should Be 1
            $results[0].Step | Should Be 'EngineerGPS'
            $results[0].Success | Should Be $true
            Assert-MockCalled 'Open-MinimalUrlInChrome' 1
        }
    }

    It 'ouvre plusieurs options simultanement' {
        $logPath = Join-Path $TestDrive 'log_eng_multi.txt'

        Mock -CommandName 'Open-MinimalUrlInChrome' {}

        $results = @(Set-MinimalEngineerConfiguration -EngineerTypes @('Nvidia', 'GPS') -LogPath $logPath -Config $script:TestConfig)

        if ($script:PesterMajorVersion -ge 5) {
            $results.Count | Should -Be 2
            ($results | Where-Object Step -eq 'EngineerNvidia').Success | Should -BeTrue
            ($results | Where-Object Step -eq 'EngineerGPS').Success | Should -BeTrue
            Assert-MockCalled -CommandName 'Open-MinimalUrlInChrome' -Times 2
        } else {
            $results.Count | Should Be 2
            ($results | Where-Object Step -eq 'EngineerNvidia').Success | Should Be $true
            ($results | Where-Object Step -eq 'EngineerGPS').Success | Should Be $true
            Assert-MockCalled 'Open-MinimalUrlInChrome' 2
        }
    }

    It 'retourne une erreur si le navigateur ne peut pas etre ouvert' {
        $logPath = Join-Path $TestDrive 'log_eng_error.txt'

        Mock -CommandName 'Open-MinimalUrlInChrome' { throw 'Navigateur introuvable' }

        $results = @(Set-MinimalEngineerConfiguration -EngineerTypes @('Nvidia') -LogPath $logPath -Config $script:TestConfig)

        if ($script:PesterMajorVersion -ge 5) {
            $results[0].Success | Should -BeFalse
            $results[0].Error | Should -Match 'Navigateur introuvable'
        } else {
            $results[0].Success | Should Be $false
            $results[0].Error | Should Match 'Navigateur introuvable'
        }
    }
}
