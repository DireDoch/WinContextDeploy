Describe 'WcdHelpers' {
    BeforeAll {
        $srcDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'src'
        $helpersPath = Join-Path $srcDir 'WcdHelpers.ps1'

        if (-not (Test-Path -LiteralPath $helpersPath)) {
            throw 'WcdHelpers.ps1 introuvable.'
        }

        . $helpersPath

        # Les assembleurs ne connaissent plus aucun Module: ils assemblent des
        # descripteurs. On charge donc les vrais Config-*.ps1 et on appelle
        # leurs vrais descripteurs, plutot que d'en recopier une version qui
        # derive du jour ou quelqu'un ajoute une Etape.
        foreach ($module in @('Config-Power', 'Config-Applications', 'Config-Language', 'Config-Network', 'Config-Printer')) {
            . (Join-Path $srcDir ('{0}.ps1' -f $module))
        }

        $script:Translations = @{ Checklist = @{} }

        function New-TestDescriptor {
            param([string[]]$Module, [hashtable]$Config = @{}, [pscustomobject]$ExecutionOptions)

            return @($Module | ForEach-Object {
                & ('Get-Wcd{0}Descriptor' -f ($_ -replace '^Config-', '')) `
                    -ExecutionOptions $ExecutionOptions -Config $Config -Translations $script:Translations
            })
        }

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

        $plan = Get-WcdModuleProgressPlan -Descriptors (New-TestDescriptor `
            -Module @('Config-Power', 'Config-Applications') -Config $config -ExecutionOptions $executionOptions)

        $plan['Config-Power'] | Should -Be @('ScreenTimeoutAc', 'SetActiveSchemeCurrent')
        # les cibles filtrees par environnement ne comptent pas dans la progression
        $plan['Config-Applications'] | Should -Be @('AppEverywhere', 'AppVdiOnly')
    }

    It 'reduit la progression des applications a une seule etape quand OpenApps est false' {
        $config = @{ Applications = @(@{ Step = 'AppOne'; Name = 'One'; Action = 'Launch'; Target = 'a.exe' }) }
        $executionOptions = [pscustomobject]@{
            FormFactor = 'Laptop'; Environment = 'Workstation'; OpenApps = $false; OptionalTools = @()
        }

        $plan = Get-WcdModuleProgressPlan -Descriptors (New-TestDescriptor `
            -Module @('Config-Applications') -Config $config -ExecutionOptions $executionOptions)

        $plan['Config-Applications'] | Should -Be @('ApplicationsSkip')
    }

    It 'nomme les etapes applicatives d apres le manifeste' {
        $config = @{ Applications = @(@{ Step = 'AppCustom'; Name = 'Our LOB app'; Action = 'Launch'; Target = 'lob.exe' }) }
        $executionOptions = [pscustomobject]@{
            FormFactor = 'Laptop'; Environment = 'Workstation'; OpenApps = $true; OptionalTools = @()
        }

        $labels = Get-WcdTechnicalStepLabels -Descriptors (New-TestDescriptor `
            -Module @('Config-Applications', 'Config-Language') -Config $config -ExecutionOptions $executionOptions)

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

    It 'reserialise les chemins en absolu pour la relance elevee' {
        # Un processus eleve demarre dans System32: un chemin relatif ne
        # retrouverait plus ses propres fichiers.
        $bound = @{
            LogPath        = 'logs\run.txt'
            HistoryLogPath = (Join-Path $TestDrive 'history.txt')
            FormFactor     = 'Desktop'
            NonInteractive = [switch]$true
        }

        $arguments = Get-WcdRelaunchArgument -ScriptPath 'src\Invoke-WcdConfiguration.ps1' `
            -BoundParameters $bound -WorkingDirectory $TestDrive

        $arguments[0] | Should -Be '-NoProfile'
        $arguments | Should -Contain '-File'
        # le script et chaque chemin sont absolus
        ($arguments -join ' ') | Should -Match ([regex]::Escape((Join-Path $TestDrive 'src')))
        ($arguments -join ' ') | Should -Match ([regex]::Escape((Join-Path $TestDrive 'logs')))
        $arguments | Should -Not -Contain 'logs\run.txt'
        # les valeurs simples passent telles quelles
        $arguments | Should -Contain '-FormFactor'
        $arguments | Should -Contain 'Desktop'
        # un switch passe nu, sans valeur
        $arguments | Should -Contain '-NonInteractive'
        $arguments | Should -Not -Contain 'True'
    }

    It 'ajoute toujours le garde -Elevated une seule fois' {
        $arguments = Get-WcdRelaunchArgument -ScriptPath 'run.ps1' `
            -BoundParameters @{ Elevated = [switch]$true; ScriptUI = 'EN' } -WorkingDirectory $TestDrive

        @($arguments | Where-Object { $_ -eq '-Elevated' }).Count | Should -Be 1
    }

    It 'reconnait un chemin UNC qui ne survivrait pas a l elevation' {
        Test-WcdUncPath -Path '\\fileserver\logs\history.txt' | Should -BeTrue
        Test-WcdUncPath -Path 'E:\log.txt' | Should -BeFalse
        Test-WcdUncPath -Path '' | Should -BeFalse
    }

    It 'derive une cle d etape stable par imprimante' {
        Get-WcdPrinterStepKey -Name 'Floor-4-Colour' | Should -Be 'PrinterFloor4Colour'
        # une entree sans nom exploitable garde une cle valide
        Get-WcdPrinterStepKey -Name '---' | Should -Be 'PrinterQueue'
    }

    It 'ne retient que les imprimantes completement declarees' {
        $config = @{ Printers = @(
            @{ Name = 'Complete'; Connection = '\\srv\Complete' }
            @{ Name = 'Sans connexion' }
            @{ Connection = '\\srv\Sans-Nom' }
        ) }

        $targets = @(Get-WcdPrinterTarget -Config $config)

        $targets.Count | Should -Be 1
        $targets[0].Name | Should -Be 'Complete'
    }

    It 'produit un rapport JSON qui fait l aller-retour sans aplatir les etapes' {
        $entries = @(
            [pscustomobject]@{ Step = 'AppErpClient'; Label = 'ERP client'; Kind = 'warning'; Detail = 'not found at C:\nope' }
            [pscustomobject]@{ Step = 'DisplayLanguage'; Label = 'Display language'; Kind = 'success'; Detail = '' }
            [pscustomobject]@{ Step = ''; Label = 'Wi-Fi'; Kind = 'manual'; Detail = 'Must be done manually.' }
            [pscustomobject]@{ Step = 'AppCadViewer'; Label = 'CAD viewer'; Kind = 'na'; Detail = 'Not applicable.' }
        )
        $options = [pscustomobject]@{ Language = 'fr-CA'; FormFactor = 'Laptop'; Environment = 'Workstation' }

        $report = New-WcdRunReport -ChecklistEntries $entries -ExecutionOptions $options -Elevated $false
        # Depth 5: la profondeur par defaut de 2 aplatirait steps en noms de type
        $json = $report | ConvertTo-Json -Depth 5
        $parsed = $json | ConvertFrom-Json

        $parsed.schemaVersion | Should -Be 1
        $parsed.timestamp | Should -Not -BeNullOrEmpty
        $parsed.context.formFactor | Should -Be 'Laptop'
        $parsed.context.environment | Should -Be 'Workstation'
        $parsed.context.language | Should -Be 'fr-CA'
        $parsed.context.elevated | Should -BeFalse
        $parsed.summary.ok | Should -Be 1
        $parsed.summary.warning | Should -Be 1
        $parsed.summary.error | Should -Be 0
        $parsed.summary.manual | Should -Be 1
        $parsed.summary.notApplicable | Should -Be 1
        @($parsed.steps).Count | Should -Be 4
        ($parsed.steps | Where-Object step -eq 'AppErpClient').kind | Should -Be 'warning'
        ($parsed.steps | Where-Object step -eq 'AppErpClient').name | Should -Be 'ERP client'
        ($parsed.steps | Where-Object step -eq 'AppErpClient').detail | Should -Match 'not found'
    }

    It 'planifie la progression des modules reseau et imprimante' {
        $config = @{
            Applications = @(@{ Step = 'AppOne'; Name = 'One'; Action = 'Launch'; Target = 'a.exe' })
            Printers     = @(@{ Name = 'Floor-4-Colour'; Connection = '\\srv\Floor-4-Colour' })
        }
        $executionOptions = [pscustomobject]@{
            FormFactor = 'Laptop'; Environment = 'Workstation'; OpenApps = $true; OptionalTools = @()
        }

        $plan = Get-WcdModuleProgressPlan -Descriptors (New-TestDescriptor `
            -Module @('Config-Network', 'Config-Printer') -Config $config -ExecutionOptions $executionOptions)

        $plan['Config-Network'] | Should -Be @('NetworkAdapterStatus', 'NetworkPing8888', 'RefreshNetworkPlaces')
        $plan['Config-Printer'] | Should -Be @('PrinterFloor4Colour')
        # sans imprimante declaree, le module n a rien a faire
        $emptyPlan = Get-WcdModuleProgressPlan -Descriptors (New-TestDescriptor `
            -Module @('Config-Printer') -Config @{ Printers = @() } -ExecutionOptions $executionOptions)
        @($emptyPlan['Config-Printer']).Count | Should -Be 0
    }

    Context 'Invoke-WcdStep' {
        BeforeAll {
            function script:Invoke-TestStep {
                param([hashtable]$Extra = @{}, [scriptblock]$Action)

                $arguments = @{
                    Module           = 'Config-Test'
                    Key              = 'TestStep'
                    LogPath          = (Join-Path $TestDrive ('step_{0}.txt' -f [guid]::NewGuid()))
                    Action           = $Action
                    ProgressCallback = { param($eventData) [void]$script:StepEvents.Add(('{0}/{1}' -f $eventData.Event, $eventData.Kind)) }
                }
                foreach ($name in $Extra.Keys) { $arguments[$name] = $Extra[$name] }

                $script:StepEvents = [System.Collections.ArrayList]::new()
                $result = Invoke-WcdStep @arguments
                return [pscustomobject]@{
                    Result = $result
                    Events = @($script:StepEvents)
                    Log    = if (Test-Path -LiteralPath $arguments.LogPath) { Get-Content -LiteralPath $arguments.LogPath -Raw } else { '' }
                }
            }
        }

        It 'retourne un succes quand l Action ne dit rien' {
            $run = Invoke-TestStep -Extra @{ SuccessLog = 'Test: done.' } -Action { }

            $run.Result.Step | Should -Be 'TestStep'
            $run.Result.Success | Should -BeTrue
            $run.Result.Error | Should -Be ''
            # Un succes nu ne porte que trois proprietes: pas de Severity vide
            # que le Diagnostic devrait ensuite apprendre a ignorer.
            @($run.Result.PSObject.Properties).Count | Should -Be 3
            $run.Log | Should -Match 'Test: done\.'
            $run.Events | Should -Be @('Start/success', 'Finish/success')
        }

        It 'ignore ce que l Action ecrit dans le pipeline' {
            # Une Action qui appelle une commande bavarde veut quand meme dire
            # "ca a marche"; seul un hashtable est un fragment de Resultat.
            $run = Invoke-TestStep -Action { 'du bruit'; 42 }

            $run.Result.Success | Should -BeTrue
            @($run.Result.PSObject.Properties).Count | Should -Be 3
        }

        It 'transforme une exception en echec avec son remede' {
            $run = Invoke-TestStep -Extra @{ FailureLabel = 'Mon etape'; FailureRemedy = 'PowerCfgFailed' } `
                -Action { throw 'powercfg a refuse' }

            $run.Result.Success | Should -BeFalse
            $run.Result.Error | Should -Be 'powercfg a refuse'
            $run.Result.RemedyKey | Should -Be 'PowerCfgFailed'
            $run.Log | Should -Match '\[ERROR\] Mon etape: powercfg a refuse'
            $run.Events | Should -Be @('Start/success', 'Finish/error')
        }

        It 'laisse OnFailure classer l echec' {
            $run = Invoke-TestStep -Extra @{
                FailureLabel  = 'Taskbar align'
                FailureRemedy = 'RegistryWriteFailed'
                OnFailure     = {
                    param($errorRecord)
                    if ($errorRecord.Exception -is [System.UnauthorizedAccessException]) {
                        return @{ Error = 'Registry key locked by GPO or access denied.'; RemedyKey = 'RegistryGpo' }
                    }
                    return @{ Error = $errorRecord.Exception.Message; RemedyKey = 'RegistryWriteFailed' }
                }
            } -Action { throw [System.UnauthorizedAccessException]::new('Operation non autorisee') }

            $run.Result.Success | Should -BeFalse
            $run.Result.Error | Should -Be 'Registry key locked by GPO or access denied.'
            $run.Result.RemedyKey | Should -Be 'RegistryGpo'
        }

        It 'ne laisse pas OnFailure declarer un succes' {
            # Une Etape qui a leve a echoue, quoi qu en dise le classificateur.
            $run = Invoke-TestStep -Extra @{ OnFailure = { param($e) @{ Success = $true; Error = $e.Exception.Message } } } `
                -Action { throw 'ca a casse' }

            $run.Result.Success | Should -BeFalse
            $run.Result.Error | Should -Be 'ca a casse'
        }

        It 'rapporte une Etape qui n a pas tourne sans la faire echouer' {
            $run = Invoke-TestStep -Action {
                @{ Severity = 'WARNING'; Error = 'powercfg requires Administrator.'; RemedyKey = 'RequiresAdmin' }
            }

            $run.Result.Success | Should -BeTrue
            $run.Result.Severity | Should -Be 'WARNING'
            $run.Result.RemedyKey | Should -Be 'RequiresAdmin'
            $run.Events | Should -Be @('Start/success', 'Finish/warning')
        }

        It 'laisse l Action choisir la severite d apres ce que la machine a dit' {
            $run = Invoke-TestStep -Action { @{ Severity = 'ERROR'; Error = 'Le disque signale Unhealthy.' } }

            # Severite choisie par la lecture, pas par un throw: Success reste vrai.
            $run.Result.Success | Should -BeTrue
            $run.Result.Severity | Should -Be 'ERROR'
            $run.Events | Should -Be @('Start/success', 'Finish/error')
        }

        It 'reporte les champs supplementaires que le Diagnostic lit' {
            $run = Invoke-TestStep -Action { @{ Applied = $true; RebootPending = $true } }

            $run.Result.Applied | Should -BeTrue
            $run.Result.RebootPending | Should -BeTrue
        }

        It 'reporte RemedyArgs' {
            $run = Invoke-TestStep -Action {
                @{ Severity = 'WARNING'; RemedyKey = 'DiskUnhealthy'; RemedyArgs = @('C:', 'Samsung SSD') }
            }

            @($run.Result.RemedyArgs) | Should -Be @('C:', 'Samsung SSD')
        }

        It 'ecrit la ligne de log que l Action demande, et ne met pas Log dans le Resultat' {
            $run = Invoke-TestStep -Extra @{ SuccessLog = 'jamais ecrit' } -Action {
                @{ Severity = 'WARNING'; Error = 'requires Administrator.'; Log = 'Mon etape: skipped, needs Administrator.' }
            }

            $run.Log | Should -Match 'Mon etape: skipped, needs Administrator\.'
            $run.Log | Should -Not -Match 'jamais ecrit'
            $run.Result.PSObject.Properties['Log'] | Should -BeNullOrEmpty
        }

        It 'n ecrit rien quand il n y a rien a dire' {
            $run = Invoke-TestStep -Action { }

            $run.Log | Should -BeNullOrEmpty
        }

        It 'garde Step, Success et Error en tete du Resultat' {
            # Le rapport JSON reprend l ordre des proprietes tel quel.
            $run = Invoke-TestStep -Action { [ordered]@{ Severity = 'WARNING'; RemedyKey = 'RequiresAdmin' } }

            @($run.Result.PSObject.Properties | ForEach-Object { $_.Name }) |
                Should -Be @('Step', 'Success', 'Error', 'Severity', 'RemedyKey')
        }
    }
}
