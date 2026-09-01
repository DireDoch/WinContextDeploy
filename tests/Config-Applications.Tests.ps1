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

    Context 'CheckWinget' {
        BeforeAll {
            # Hors du manifeste partage: les autres tests lancent toutes les
            # cibles, et aucune ne doit appeler winget pour de vrai.
            $script:WingetTargets = @(
                @{ Step = 'AppWinget'; Name = 'PowerToys'; Action = 'CheckWinget'; Target = 'Microsoft.PowerToys' }
            )
            $script:WingetOptionalTargets = @(
                @{ Step = 'AppWingetOpt'; Name = 'Fancy tool'; Action = 'CheckWinget'; Target = 'Vendor.FancyTool'; Optional = $true }
            )
        }

        It 'rapporte un paquet installe comme reussi' {
            $logPath = Join-Path $TestDrive 'log_winget_ok.txt'
            Mock -CommandName 'Test-WcdWingetAvailable' { $true }
            Mock -CommandName 'Test-WcdWingetPackageInstalled' { $true }

            $results = @(Set-WcdApplicationsConfiguration -Targets $script:WingetTargets -OpenApps $true -LogPath $logPath)

            $results.Count | Should -Be 1
            $results[0].Step | Should -Be 'AppWinget'
            $results[0].Success | Should -BeTrue
            $results[0].Error | Should -BeNullOrEmpty
        }

        It 'avertit quand le paquet n est pas installe' {
            $logPath = Join-Path $TestDrive 'log_winget_absent.txt'
            Mock -CommandName 'Test-WcdWingetAvailable' { $true }
            Mock -CommandName 'Test-WcdWingetPackageInstalled' { $false }

            $results = @(Set-WcdApplicationsConfiguration -Targets $script:WingetTargets -OpenApps $true -LogPath $logPath)

            $results[0].Severity | Should -Be 'WARNING'
            $results[0].Success | Should -BeTrue
            $results[0].RemedyKey | Should -Be 'WingetPackageMissing'
        }

        It 'traite un paquet optionnel absent comme une note' {
            $logPath = Join-Path $TestDrive 'log_winget_optional.txt'
            Mock -CommandName 'Test-WcdWingetAvailable' { $true }
            Mock -CommandName 'Test-WcdWingetPackageInstalled' { $false }

            $results = @(Set-WcdApplicationsConfiguration -Targets $script:WingetOptionalTargets -OpenApps $true -LogPath $logPath)

            $results[0].Severity | Should -Be 'INFO'
            $results[0].RemedyKey | Should -Be ''
        }

        It 'signale une seule cause et passe les entrees en MANUAL quand winget est absent' {
            $logPath = Join-Path $TestDrive 'log_winget_missing.txt'
            Mock -CommandName 'Test-WcdWingetAvailable' { $false }
            Mock -CommandName 'Test-WcdWingetPackageInstalled' { throw 'winget ne doit pas etre appele.' }

            $targets = @($script:WingetTargets + $script:WingetOptionalTargets)
            $results = @(Set-WcdApplicationsConfiguration -Targets $targets -OpenApps $true -LogPath $logPath)

            $probe = @($results | Where-Object Step -eq 'WingetUnavailable')
            $probe.Count | Should -Be 1
            $probe[0].Severity | Should -Be 'WARNING'
            $probe[0].RemedyKey | Should -Be 'WingetMissing'

            # une cause honnete, et une ligne actionnable par paquet
            @($results | Where-Object { $_.Step -like 'AppWinget*' }).Severity | Should -Be @('MANUAL', 'MANUAL')
            Should -Invoke -CommandName 'Test-WcdWingetAvailable' -Times 1 -Exactly
        }

        It 'traite un echec de winget comme une erreur, pas comme un paquet absent' {
            $logPath = Join-Path $TestDrive 'log_winget_broken.txt'
            Mock -CommandName 'Test-WcdWingetAvailable' { $true }
            Mock -CommandName 'Test-WcdWingetPackageInstalled' { throw 'winget list failed for Microsoft.PowerToys (exit 5).' }

            $results = @(Set-WcdApplicationsConfiguration -Targets $script:WingetTargets -OpenApps $true -LogPath $logPath)

            $results[0].Severity | Should -Be 'ERROR'
            $results[0].Success | Should -BeFalse
            $results[0].RemedyKey | Should -Be 'WingetCheckFailed'
        }

        It 'lit le code de sortie de winget: 0 installe, code introuvable absent, autre erreur' {
            # -Scope 1 pose LASTEXITCODE dans le scope appelant, la ou
            # Test-WcdWingetPackageInstalled le relit.
            function winget.exe {
                Set-Variable -Name 'LASTEXITCODE' -Value $script:WingetExit -Scope 1
                'sortie winget'
            }

            $script:WingetExit = 0
            Test-WcdWingetPackageInstalled -Id 'Microsoft.PowerToys' | Should -BeTrue

            # APPINSTALLER_CLI_ERROR_NO_APPLICATIONS_FOUND
            $script:WingetExit = -1978335212
            Test-WcdWingetPackageInstalled -Id 'Microsoft.PowerToys' | Should -BeFalse

            $script:WingetExit = 5
            { Test-WcdWingetPackageInstalled -Id 'Microsoft.PowerToys' } | Should -Throw
        }
    }
}
