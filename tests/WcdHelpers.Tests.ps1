Describe 'WcdHelpers' {
    BeforeAll {
        $srcDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'src'
        $helpersPath = Join-Path $srcDir 'WcdHelpers.ps1'

        if (-not (Test-Path -LiteralPath $helpersPath)) {
            throw 'WcdHelpers.ps1 introuvable.'
        }

        . $helpersPath
        $script:PesterMajorVersion = (Get-Module -Name Pester | Select-Object -First 1).Version.Major
    }

    It 'reinitialise le log local a chaque execution' {
        $logPath = Join-Path $TestDrive 'local-log.txt'
        Set-Content -Path $logPath -Value 'ancien contenu' -Encoding UTF8

        Initialize-WcdLog -Path $logPath
        $content = Get-Content -Path $logPath -Raw

        if ($script:PesterMajorVersion -ge 5) {
            $content | Should -BeNullOrEmpty
        } else {
            $content | Should BeNullOrEmpty
        }
    }

    It 'ajoute un bloc historique a la fin du log cumule avec le diagnostic final' {
        $localLogPath = Join-Path $TestDrive 'run-log.txt'
        $historyLogPath = Join-Path $TestDrive 'history-log.txt'
        $diagnosticLines = @(
            '===============================================',
            '         DIAGNOSTIC FINAL - PAR ETAPE          ',
            '===============================================',
            '  [x]  Taskbar a gauche         OK'
        )

        Set-Content -Path $localLogPath -Value @('ligne 1', 'ligne 2') -Encoding UTF8
        Set-Content -Path $historyLogPath -Value 'bloc precedent' -Encoding UTF8

        Mock -CommandName 'Get-CimInstance' { [pscustomobject]@{ CSName = 'PC-TEST' } } -ParameterFilter { $ClassName -eq 'Win32_OperatingSystem' }
        Mock -CommandName 'Get-CimInstance' { [pscustomobject]@{ SerialNumber = 'CCMP234' } } -ParameterFilter { $ClassName -eq 'Win32_Bios' }
        Mock -CommandName 'Get-CimInstance' { [pscustomobject]@{ Model = 'Latitude 5550' } } -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' }

        $resultPath = Export-WcdHistoryLog -LocalLogPath $localLogPath -HistoryLogPath $historyLogPath -DiagnosticLines $diagnosticLines
        $content = Get-Content -Path $historyLogPath -Raw

        if ($script:PesterMajorVersion -ge 5) {
            $resultPath | Should -Be $historyLogPath
            $content | Should -Match 'bloc precedent'
            $content | Should -Match 'PCname\s+: PC-TEST'
            $content | Should -Match 'SerialNumber\s+: CCMP234'
            $content | Should -Match 'Model\s+: Latitude 5550'
            $content | Should -Match 'User\s+: '
            $content | Should -Match 'Username\s+: '
            $content | Should -Match 'DateTime\s+: '
            $content | Should -Match 'SECTION LOG'
            $content | Should -Match 'SECTION DIAGNOSTIC FINAL'
            $content | Should -Match 'Taskbar a gauche'
            $content | Should -Match '\| ligne 1'
            $content | Should -Match '\| ligne 2'
            $content | Should -Match '\+============================================================\+'
        } else {
            $resultPath | Should Be $historyLogPath
            $content | Should Match 'bloc precedent'
            $content | Should Match 'PCname\s+: PC-TEST'
            $content | Should Match 'SerialNumber\s+: CCMP234'
            $content | Should Match 'Model\s+: Latitude 5550'
            $content | Should Match 'User\s+: '
            $content | Should Match 'Username\s+: '
            $content | Should Match 'DateTime\s+: '
            $content | Should Match 'SECTION LOG'
            $content | Should Match 'SECTION DIAGNOSTIC FINAL'
            $content | Should Match 'Taskbar a gauche'
            $content | Should Match '\| ligne 1'
            $content | Should Match '\| ligne 2'
            $content | Should Match '\+============================================================\+'
        }
    }

    It 'construit une barre de progression ASCII lisible' {
        $bar = Format-WcdAsciiProgressBar -CompletedSteps 3 -TotalSteps 10

        if ($script:PesterMajorVersion -ge 5) {
            $bar | Should -Match '\[.*\]'
            $bar | Should -Match '30%'
            $bar | Should -Match '#'
            $bar | Should -Match '-'
        } else {
            $bar | Should Match '\[.*\]'
            $bar | Should Match '30%'
            $bar | Should Match '#'
            $bar | Should Match '-'
        }
    }

    It 'retourne le bon plan de progression selon le profil d execution' {
        $config = @{
            Applications = @(
                @{ Step = 'AppEverywhere'; Name = 'Everywhere'; Action = 'Launch';  Target = 'a.exe' }
                @{ Step = 'AppVdiOnly';    Name = 'Workspace';  Action = 'OpenUrl'; Target = 'https://example.com'; Environment = 'Vdi' }
                @{ Step = 'AppWsOnly';     Name = 'ERP';        Action = 'OpenUrl'; Target = 'https://example.com'; Environment = 'Workstation' }
            )
        }
        $executionOptions = [pscustomobject]@{
            FormFactor    = 'Desktop'
            Environment   = 'Vdi'
            OpenApps      = $true
            OptionalTools = @()
        }

        $plan = Get-WcdModuleProgressPlan -ExecutionOptions $executionOptions -Config $config

        $plan['Config-Power'] | Should -Be @('ScreenTimeoutAc', 'SetActiveSchemeCurrent')
        # les cibles filtrees par environnement ne comptent pas dans la progression
        $plan['Config-Applications'] | Should -Be @('AppEverywhere', 'AppVdiOnly')
    }

    It 'reduit la progression des applications a une seule etape quand OpenApps est false' {
        $config = @{ Applications = @(@{ Step = 'AppOne'; Name = 'One'; Action = 'Launch'; Target = 'a.exe' }) }
        $executionOptions = [pscustomobject]@{
            FormFactor = 'Laptop'; Environment = 'Workstation'; OpenApps = $false; OptionalTools = @()
        }

        $plan = Get-WcdModuleProgressPlan -ExecutionOptions $executionOptions -Config $config

        $plan['Config-Applications'] | Should -Be @('ApplicationsSkip')
    }

    It 'nomme les etapes applicatives d apres le manifeste' {
        $config = @{ Applications = @(@{ Step = 'AppCustom'; Name = 'Our LOB app'; Action = 'Launch'; Target = 'lob.exe' }) }

        $labels = Get-WcdTechnicalStepLabels -Config $config

        $labels['AppCustom'] | Should -Be 'Our LOB app'
        # les etapes systeme gardent leurs libelles integres
        $labels['DisplayLanguage'] | Should -Be 'Display language'
    }

    It 'localise les libelles de choix sans changer les valeurs canoniques' {
        $fr = @{ Laptop = 'Portable'; Vdi = 'Citrix' }

        Get-WcdChoiceLabel -Value 'Laptop' -Labels $fr | Should -Be 'Portable'
        Get-WcdChoiceLabel -Value 'Vdi'    -Labels $fr | Should -Be 'Citrix'
        # valeur sans traduction: retournee telle quelle
        Get-WcdChoiceLabel -Value 'Desktop' -Labels $fr | Should -Be 'Desktop'
        # aucune table fournie: retournee telle quelle
        Get-WcdChoiceLabel -Value 'Laptop' | Should -Be 'Laptop'
    }
}