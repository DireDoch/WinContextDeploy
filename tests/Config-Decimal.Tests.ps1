Describe 'Config-Decimal' {
    BeforeAll {
        $helpersPath = Join-Path $PSScriptRoot 'MinimalHelpers.ps1'
        $modulePath  = Join-Path $PSScriptRoot 'Config-Decimal.ps1'

        if (-not (Test-Path -LiteralPath $helpersPath)) {
            $helpersPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'tests/MinimalHelpers.ps1'
        }
        if (-not (Test-Path -LiteralPath $modulePath)) {
            $modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'tests/Config-Decimal.ps1'
        }

        if (-not (Test-Path -LiteralPath $helpersPath)) { throw 'MinimalHelpers.ps1 introuvable.' }
        if (-not (Test-Path -LiteralPath $modulePath))  { throw 'Config-Decimal.ps1 introuvable.' }

        . $helpersPath
        . $modulePath

        $script:PesterMajorVersion = (Get-Module -Name Pester | Select-Object -First 1).Version.Major
    }

    It 'configure les decimales avec succes' {
        $logPath = Join-Path $TestDrive 'log_decimal.txt'

        Mock -CommandName 'Set-MinimalRegistryValue' {}

        $result = Set-MinimalDecimalConfiguration -LogPath $logPath

        if ($script:PesterMajorVersion -ge 5) {
            $result.Success | Should -BeTrue
            $result.Step | Should -Be 'DecimalEtMonetaire'
            Get-Content -Path $logPath -Raw | Should -Match 'symboles numeriques et monetaires forces a un point'
            Assert-MockCalled -CommandName 'Set-MinimalRegistryValue' -Times 5
            Assert-MockCalled -CommandName 'Set-MinimalRegistryValue' -Times 1 -ParameterFilter { $Path -eq 'HKCU:\Control Panel\International' -and $Name -eq 'sDecimal' -and $Value -eq '.' }
            Assert-MockCalled -CommandName 'Set-MinimalRegistryValue' -Times 1 -ParameterFilter { $Path -eq 'HKCU:\Control Panel\International' -and $Name -eq 'sThousandSep' -and $Value -eq ',' }
            Assert-MockCalled -CommandName 'Set-MinimalRegistryValue' -Times 1 -ParameterFilter { $Path -eq 'HKCU:\Control Panel\International' -and $Name -eq 'sMonDecimalSep' -and $Value -eq '.' }
            Assert-MockCalled -CommandName 'Set-MinimalRegistryValue' -Times 1 -ParameterFilter { $Path -eq 'HKCU:\Control Panel\International' -and $Name -eq 'sMonetaryDecimal' -and $Value -eq '.' }
            Assert-MockCalled -CommandName 'Set-MinimalRegistryValue' -Times 1 -ParameterFilter { $Path -eq 'HKCU:\Control Panel\International' -and $Name -eq 'sMonThousandSep' -and $Value -eq ',' }
        } else {
            $result.Success | Should Be $true
            $result.Step | Should Be 'DecimalEtMonetaire'
            Get-Content -Path $logPath -Raw | Should Match 'symboles numeriques et monetaires forces a un point'
            Assert-MockCalled 'Set-MinimalRegistryValue' 5
        }
    }

    It 'retourne echec si registre bloque par GPO' {
        $logPath = Join-Path $TestDrive 'log_decimal_gpo.txt'

        Mock -CommandName 'Set-MinimalRegistryValue' { throw [System.UnauthorizedAccessException]::new('Operation non autorisee') }

        $result = Set-MinimalDecimalConfiguration -LogPath $logPath

        if ($script:PesterMajorVersion -ge 5) {
            $result.Success | Should -BeFalse
            $result.Error | Should -Match 'GPO|acces refuse'
            Get-Content -Path $logPath -Raw | Should -Match 'Decimales'
        } else {
            $result.Success | Should Be $false
            $result.Error | Should Match 'GPO|acces refuse'
            Get-Content -Path $logPath -Raw | Should Match 'Decimales'
        }
    }
}
