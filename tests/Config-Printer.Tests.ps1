Describe 'Config-Printer' {
    BeforeAll {
        $helpersPath = Join-Path $PSScriptRoot 'MinimalHelpers.ps1'
        $modulePath  = Join-Path $PSScriptRoot 'Config-Printer.ps1'

        if (-not (Test-Path -LiteralPath $helpersPath)) {
            $helpersPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'tests/MinimalHelpers.ps1'
        }
        if (-not (Test-Path -LiteralPath $modulePath)) {
            $modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'tests/Config-Printer.ps1'
        }

        if (-not (Test-Path -LiteralPath $helpersPath)) { throw 'MinimalHelpers.ps1 introuvable.' }
        if (-not (Test-Path -LiteralPath $modulePath))  { throw 'Config-Printer.ps1 introuvable.' }

        . $helpersPath
        . $modulePath

        $script:PesterMajorVersion = (Get-Module -Name Pester | Select-Object -First 1).Version.Major
    }

    It 'ne fait rien quand AddPrinter est false' {
        $logPath = Join-Path $TestDrive 'log_printer_skip.txt'

        Mock -CommandName 'Open-MinimalPrinterTool' {}

        $result = Set-MinimalPrinterConfiguration -AddPrinter $false -LogPath $logPath

        if ($script:PesterMajorVersion -ge 5) {
            $result.Step | Should -Be 'PrinterSkip'
            $result.Success | Should -BeTrue
            Assert-MockCalled -CommandName 'Open-MinimalPrinterTool' -Times 0
        } else {
            $result.Step | Should Be 'PrinterSkip'
            $result.Success | Should Be $true
            Assert-MockCalled 'Open-MinimalPrinterTool' 0
        }
    }

    It 'ouvre Find and add Printer quand present' {
        $logPath = Join-Path $TestDrive 'log_printer_ok.txt'
        $fakePrinterPath = Join-Path $TestDrive 'Find and add Printer.lnk'
        New-Item -Path $fakePrinterPath -ItemType File -Force | Out-Null

        Mock -CommandName 'Open-MinimalPrinterTool' {}

        $config = @{
            Printer = @{
                PrintManagerPath = $fakePrinterPath
            }
        }

        $result = Set-MinimalPrinterConfiguration -AddPrinter $true -LogPath $logPath -Config $config

        if ($script:PesterMajorVersion -ge 5) {
            $result.Step | Should -Be 'PrinterAdd'
            $result.Success | Should -BeTrue
            Assert-MockCalled -CommandName 'Open-MinimalPrinterTool' -Times 1
        } else {
            $result.Step | Should Be 'PrinterAdd'
            $result.Success | Should Be $true
            Assert-MockCalled 'Open-MinimalPrinterTool' 1
        }
    }

    It 'retourne une erreur quand le raccourci est introuvable' {
        $logPath = Join-Path $TestDrive 'log_printer_missing.txt'

        Mock -CommandName 'Open-MinimalPrinterTool' {}

        $config = @{
            Printer = @{
                PrintManagerPath = (Join-Path $TestDrive 'nonexistent_printer.lnk')
            }
        }

        $result = Set-MinimalPrinterConfiguration -AddPrinter $true -LogPath $logPath -Config $config

        if ($script:PesterMajorVersion -ge 5) {
            $result.Step | Should -Be 'PrinterAdd'
            $result.Success | Should -BeFalse
            $result.Error | Should -Match 'introuvable'
        } else {
            $result.Step | Should Be 'PrinterAdd'
            $result.Success | Should Be $false
            $result.Error | Should Match 'introuvable'
        }
    }

    It 'retourne une erreur quand le lancement echoue' {
        $logPath = Join-Path $TestDrive 'log_printer_error.txt'
        $fakePrinterPath = Join-Path $TestDrive 'FindPrinterError.lnk'
        New-Item -Path $fakePrinterPath -ItemType File -Force | Out-Null

        Mock -CommandName 'Open-MinimalPrinterTool' { throw 'Acces refuse' }

        $config = @{
            Printer = @{
                PrintManagerPath = $fakePrinterPath
            }
        }

        $result = Set-MinimalPrinterConfiguration -AddPrinter $true -LogPath $logPath -Config $config

        if ($script:PesterMajorVersion -ge 5) {
            $result.Success | Should -BeFalse
            $result.Error | Should -Match 'Acces refuse'
        } else {
            $result.Success | Should Be $false
            $result.Error | Should Match 'Acces refuse'
        }
    }
}
