Describe 'Config-Printer' {
    BeforeAll {
        $srcDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'src'
        $helpersPath = Join-Path $srcDir 'WcdHelpers.ps1'
        $modulePath  = Join-Path $srcDir 'Config-Printer.ps1'

        if (-not (Test-Path -LiteralPath $helpersPath)) { throw 'WcdHelpers.ps1 introuvable.' }
        if (-not (Test-Path -LiteralPath $modulePath))  { throw 'Config-Printer.ps1 introuvable.' }

        . $helpersPath
        . $modulePath

        $script:PesterMajorVersion = (Get-Module -Name Pester | Select-Object -First 1).Version.Major
    }

    It 'ne fait rien quand aucune imprimante n est declaree' {
        $logPath = Join-Path $TestDrive 'log_printer_empty.txt'

        Mock -CommandName 'Get-WcdPrinter' {}
        Mock -CommandName 'Add-WcdPrinterConnection' {}

        $results = @(Set-WcdPrinterConfiguration -Config @{ Printers = @() } -LogPath $logPath)

        $results.Count | Should -Be 0
        Assert-MockCalled -CommandName 'Add-WcdPrinterConnection' -Times 0
    }

    It 'connecte une file partagee absente du poste' {
        $logPath = Join-Path $TestDrive 'log_printer_add.txt'

        Mock -CommandName 'Get-WcdPrinter' { $null }
        Mock -CommandName 'Add-WcdPrinterConnection' {}

        $config = @{ Printers = @(@{ Name = 'Floor-4-Colour'; Connection = '\\printserver\Floor-4-Colour' }) }
        $results = @(Set-WcdPrinterConfiguration -Config $config -LogPath $logPath)

        $results.Count | Should -Be 1
        $results[0].Step | Should -Be 'PrinterFloor4Colour'
        $results[0].Success | Should -BeTrue
        $results[0].Severity | Should -Be 'INFO'
        Assert-MockCalled -CommandName 'Add-WcdPrinterConnection' -Times 1 -ParameterFilter { $ConnectionName -eq '\\printserver\Floor-4-Colour' }
        Get-Content -Path $logPath -Raw | Should -Match 'connected via'
    }

    It 'est idempotent: une imprimante deja connectee n est pas reconnectee' {
        $logPath = Join-Path $TestDrive 'log_printer_idempotent.txt'

        Mock -CommandName 'Get-WcdPrinter' { [pscustomobject]@{ Name = 'Floor-4-Colour' } }
        Mock -CommandName 'Add-WcdPrinterConnection' {}

        $config = @{ Printers = @(@{ Name = 'Floor-4-Colour'; Connection = '\\printserver\Floor-4-Colour' }) }
        $results = @(Set-WcdPrinterConfiguration -Config $config -LogPath $logPath)

        $results[0].Success | Should -BeTrue
        $results[0].Severity | Should -Be 'INFO'
        Assert-MockCalled -CommandName 'Add-WcdPrinterConnection' -Times 0
        Get-Content -Path $logPath -Raw | Should -Match 'already connected'
    }

    It 'avertit sans planter quand le serveur d impression est injoignable' {
        $logPath = Join-Path $TestDrive 'log_printer_unreachable.txt'

        Mock -CommandName 'Get-WcdPrinter' { $null }
        Mock -CommandName 'Add-WcdPrinterConnection' { throw 'The network path was not found.' }

        $config = @{ Printers = @(@{ Name = 'Floor-4-Colour'; Connection = '\\printserver\Floor-4-Colour' }) }
        $results = @(Set-WcdPrinterConfiguration -Config $config -LogPath $logPath)

        $results.Count | Should -Be 1
        $results[0].Severity | Should -Be 'WARNING'
        # un serveur injoignable est un avertissement actionnable, pas un echec dur
        $results[0].Success | Should -BeTrue
        $results[0].RemedyKey | Should -Be 'PrinterUnreachable'
        $results[0].Error | Should -Match 'network path'
    }

    It 'ignore une entree de manifeste incomplete' {
        $logPath = Join-Path $TestDrive 'log_printer_incomplete.txt'

        Mock -CommandName 'Get-WcdPrinter' { $null }
        Mock -CommandName 'Add-WcdPrinterConnection' {}

        $config = @{ Printers = @(
            @{ Name = 'Sans connexion' }
            @{ Connection = '\\printserver\Sans-Nom' }
            @{ Name = 'Floor-4-Colour'; Connection = '\\printserver\Floor-4-Colour' }
        ) }
        $results = @(Set-WcdPrinterConfiguration -Config $config -LogPath $logPath)

        $results.Count | Should -Be 1
        $results[0].Step | Should -Be 'PrinterFloor4Colour'
    }

    It 'rapporte chaque file separement' {
        $logPath = Join-Path $TestDrive 'log_printer_multiple.txt'

        Mock -CommandName 'Get-WcdPrinter' { $null }
        Mock -CommandName 'Add-WcdPrinterConnection' {
            if ($ConnectionName -match 'Broken') { throw 'The network path was not found.' }
        }

        $config = @{ Printers = @(
            @{ Name = 'Floor-4-Colour'; Connection = '\\printserver\Floor-4-Colour' }
            @{ Name = 'Broken-Queue';   Connection = '\\printserver\Broken-Queue' }
        ) }
        $results = @(Set-WcdPrinterConfiguration -Config $config -LogPath $logPath)

        $results.Count | Should -Be 2
        ($results | Where-Object Step -eq 'PrinterFloor4Colour').Severity | Should -Be 'INFO'
        ($results | Where-Object Step -eq 'PrinterBrokenQueue').Severity | Should -Be 'WARNING'
    }

    It 'signale la progression pour chaque file' {
        $logPath = Join-Path $TestDrive 'log_printer_progress.txt'

        Mock -CommandName 'Get-WcdPrinter' { $null }
        Mock -CommandName 'Add-WcdPrinterConnection' {}

        $events = [System.Collections.ArrayList]::new()
        $callback = { param($eventData) [void]$events.Add(('{0}:{1}' -f $eventData.Step, $eventData.Event)) }.GetNewClosure()

        $config = @{ Printers = @(@{ Name = 'Floor-4-Colour'; Connection = '\\printserver\Floor-4-Colour' }) }
        Set-WcdPrinterConfiguration -Config $config -LogPath $logPath -ProgressCallback $callback | Out-Null

        $events | Should -Contain 'PrinterFloor4Colour:Start'
        $events | Should -Contain 'PrinterFloor4Colour:Finish'
    }
}
