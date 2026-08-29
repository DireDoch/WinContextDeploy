Describe 'Config-Decimal' {
    BeforeAll {
        $srcDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'src'
        $helpersPath = Join-Path $srcDir 'WcdHelpers.ps1'
        $modulePath  = Join-Path $srcDir 'Config-Decimal.ps1'

        if (-not (Test-Path -LiteralPath $helpersPath)) { throw 'WcdHelpers.ps1 introuvable.' }
        if (-not (Test-Path -LiteralPath $modulePath))  { throw 'Config-Decimal.ps1 introuvable.' }

        . $helpersPath
        . $modulePath

        $script:PesterMajorVersion = (Get-Module -Name Pester | Select-Object -First 1).Version.Major
    }

    It 'configure les decimales avec succes' {
        $logPath = Join-Path $TestDrive 'log_decimal.txt'

        Mock -CommandName 'Set-WcdRegistryValue' {}

        $result = Set-WcdDecimalConfiguration -LogPath $logPath

        if ($script:PesterMajorVersion -ge 5) {
            $result.Success | Should -BeTrue
            $result.Step | Should -Be 'DecimalAndCurrency'
            Get-Content -Path $logPath -Raw | Should -Match 'decimal and currency separators forced to a period'
            Assert-MockCalled -CommandName 'Set-WcdRegistryValue' -Times 5
            Assert-MockCalled -CommandName 'Set-WcdRegistryValue' -Times 1 -ParameterFilter { $Path -eq 'HKCU:\Control Panel\International' -and $Name -eq 'sDecimal' -and $Value -eq '.' }
            Assert-MockCalled -CommandName 'Set-WcdRegistryValue' -Times 1 -ParameterFilter { $Path -eq 'HKCU:\Control Panel\International' -and $Name -eq 'sThousandSep' -and $Value -eq ',' }
            Assert-MockCalled -CommandName 'Set-WcdRegistryValue' -Times 1 -ParameterFilter { $Path -eq 'HKCU:\Control Panel\International' -and $Name -eq 'sMonDecimalSep' -and $Value -eq '.' }
            Assert-MockCalled -CommandName 'Set-WcdRegistryValue' -Times 1 -ParameterFilter { $Path -eq 'HKCU:\Control Panel\International' -and $Name -eq 'sMonetaryDecimal' -and $Value -eq '.' }
            Assert-MockCalled -CommandName 'Set-WcdRegistryValue' -Times 1 -ParameterFilter { $Path -eq 'HKCU:\Control Panel\International' -and $Name -eq 'sMonThousandSep' -and $Value -eq ',' }
        } else {
            $result.Success | Should Be $true
            $result.Step | Should Be 'DecimalAndCurrency'
            Get-Content -Path $logPath -Raw | Should Match 'decimal and currency separators forced to a period'
            Assert-MockCalled 'Set-WcdRegistryValue' 5
        }
    }

    It 'retourne echec si registre bloque par GPO' {
        $logPath = Join-Path $TestDrive 'log_decimal_gpo.txt'

        Mock -CommandName 'Set-WcdRegistryValue' { throw [System.UnauthorizedAccessException]::new('Operation non autorisee') }

        $result = Set-WcdDecimalConfiguration -LogPath $logPath

        if ($script:PesterMajorVersion -ge 5) {
            $result.Success | Should -BeFalse
            $result.Error | Should -Match 'GPO|acces refuse'
            Get-Content -Path $logPath -Raw | Should -Match 'Regional'
        } else {
            $result.Success | Should Be $false
            $result.Error | Should Match 'GPO|acces refuse'
            Get-Content -Path $logPath -Raw | Should Match 'Decimales'
        }
    }
}
