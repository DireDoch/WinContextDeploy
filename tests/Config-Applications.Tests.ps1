Describe 'Config-Applications' {
    BeforeAll {
        $srcDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'src'
        $helpersPath = Join-Path $srcDir 'WcdHelpers.ps1'
        $modulePath  = Join-Path $srcDir 'Config-Applications.ps1'

        if (-not (Test-Path -LiteralPath $helpersPath)) { throw 'WcdHelpers.ps1 introuvable.' }
        if (-not (Test-Path -LiteralPath $modulePath))  { throw 'Config-Applications.ps1 introuvable.' }

        . $helpersPath
        . $modulePath

        $script:TestConfig = @{
            Applications = @(
                @{ Step = 'AppLaunch';    Name = 'Launcher';   Action = 'Launch';       Target = 'someapp.exe' }
                @{ Step = 'AppUrl';       Name = 'Portal';     Action = 'OpenUrl';      Target = 'https://example.com/portal' }
                @{ Step = 'AppProc';      Name = 'VPN client'; Action = 'CheckProcess'; Target = @('nosuchprocess') }
                @{ Step = 'AppLocalOnly'; Name = 'ERP client'; Action = 'OpenFolder';   Target = 'C:\nope\erp'; Environment = 'Workstation'; Optional = $true }
                @{ Step = 'AppVdiOnly';   Name = 'Workspace';  Action = 'OpenUrl';      Target = 'https://example.com/vdi'; Environment = 'Vdi' }
                @{ Step = 'AppExtra';     Name = 'GPU tool';   Action = 'OpenUrl';      Target = 'https://example.com/gpu'; Prompt = $true }
            )
        }
    }

    It 'ne retient que les cibles applicables a l environnement choisi' {
        $ws = @(Get-WcdApplicationTarget -Config $script:TestConfig -Environment 'Workstation')

        @($ws | ForEach-Object { $_.Step }) | Should -Contain 'AppLocalOnly'
        @($ws | ForEach-Object { $_.Step }) | Should -Not -Contain 'AppVdiOnly'

        $vdi = @(Get-WcdApplicationTarget -Config $script:TestConfig -Environment 'Vdi')
        @($vdi | ForEach-Object { $_.Step }) | Should -Contain 'AppVdiOnly'
        @($vdi | ForEach-Object { $_.Step }) | Should -Not -Contain 'AppLocalOnly'
    }

    It 'exclut les outils optionnels non selectionnes' {
        $without = @(Get-WcdApplicationTarget -Config $script:TestConfig -Environment 'Workstation')
        @($without | ForEach-Object { $_.Step }) | Should -Not -Contain 'AppExtra'

        $with = @(Get-WcdApplicationTarget -Config $script:TestConfig -Environment 'Workstation' -OptionalTools @('GPU tool'))
        @($with | ForEach-Object { $_.Step }) | Should -Contain 'AppExtra'
    }

    It 'liste les cibles proposables dans le menu des outils optionnels' {
        $prompted = @(Get-WcdPromptedApplicationTarget -Config $script:TestConfig)

        $prompted.Count | Should -Be 1
        $prompted[0].Name | Should -Be 'GPU tool'
    }

    It 'ignore toutes les cibles quand OpenApps est false' {
        $logPath = Join-Path $TestDrive 'log_apps_skip.txt'
        $targets = @(Get-WcdApplicationTarget -Config $script:TestConfig -Environment 'Workstation')

        $results = @(Set-WcdApplicationsConfiguration -Targets $targets -OpenApps $false -LogPath $logPath)

        $results.Count | Should -Be 1
        $results[0].Step | Should -Be 'ApplicationsSkip'
        $results[0].Success | Should -BeTrue
    }

    It 'lance chaque action et produit un resultat par cible' {
        $logPath = Join-Path $TestDrive 'log_apps_run.txt'
        Mock -CommandName 'Start-Process' {}
        Mock -CommandName 'Open-WcdUrl' {}

        $targets = @(Get-WcdApplicationTarget -Config $script:TestConfig -Environment 'Workstation')
        $results = @(Set-WcdApplicationsConfiguration -Targets $targets -OpenApps $true -LogPath $logPath)

        $results.Count | Should -Be $targets.Count
        ($results | Where-Object Step -eq 'AppLaunch').Success | Should -BeTrue
        ($results | Where-Object Step -eq 'AppUrl').Success | Should -BeTrue
    }

    It 'signale un avertissement quand un processus surveille est absent' {
        $logPath = Join-Path $TestDrive 'log_apps_proc.txt'
        Mock -CommandName 'Start-Process' {}
        Mock -CommandName 'Open-WcdUrl' {}

        $targets = @($script:TestConfig.Applications | Where-Object Step -eq 'AppProc')
        $results = @(Set-WcdApplicationsConfiguration -Targets $targets -OpenApps $true -LogPath $logPath)

        $results[0].Severity | Should -Be 'WARNING'
        # un processus absent n'est pas une etape cassee
        $results[0].Success | Should -BeTrue
    }

    It 'traite une cible optionnelle absente comme une note et non un avertissement' {
        $logPath = Join-Path $TestDrive 'log_apps_optional.txt'

        $targets = @($script:TestConfig.Applications | Where-Object Step -eq 'AppLocalOnly')
        $results = @(Set-WcdApplicationsConfiguration -Targets $targets -OpenApps $true -LogPath $logPath)

        $results[0].Severity | Should -Be 'INFO'
        $results[0].Success | Should -BeTrue
        $results[0].Error | Should -Match 'not found'
    }
}
