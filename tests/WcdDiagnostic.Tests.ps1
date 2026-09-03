Describe 'WcdDiagnostic' {
    BeforeAll {
        $srcDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'src'

        $helpersPath = Join-Path $srcDir 'WcdHelpers.ps1'
        $diagnosticPath = Join-Path $srcDir 'WcdDiagnostic.ps1'
        foreach ($required in @($helpersPath, $diagnosticPath)) {
            if (-not (Test-Path -LiteralPath $required)) { throw ('{0} introuvable.' -f (Split-Path $required -Leaf)) }
        }

        . $helpersPath

        # Le Diagnostic lit $T depuis la portee script, comme dans l'orchestrateur.
        # On extrait l'affectation reelle par l'AST plutot que d'en recopier une
        # version qui derive: point-sourcer l'orchestrateur lancerait toute une
        # execution (banniere, invites, modules, exit).
        $orchestratorPath = Join-Path $srcDir 'Invoke-WcdConfiguration.ps1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($orchestratorPath, [ref]$null, [ref]$null)
        $assignment = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $node.Left.Extent.Text -eq '$T'
        }, $false)) | Select-Object -First 1
        if ($null -eq $assignment) { throw 'Table $T introuvable dans Invoke-WcdConfiguration.ps1.' }

        # L'affectation est un if sur $ScriptUI: on le passe en parametre plutot
        # que de compter sur la portee dynamique.
        $tableBuilder = [scriptblock]::Create(('param($ScriptUI) {0}' -f $assignment.Right.Extent.Text))
        $script:T = & $tableBuilder 'EN'

        . $diagnosticPath

        # La checklist assemble des descripteurs. On charge le vrai
        # Config-Applications plutot que d'en simuler un.
        . (Join-Path $srcDir 'Config-Applications.ps1')

        function New-TestDescriptor {
            param([hashtable]$Config, [pscustomobject]$ExecutionOptions)
            return @(Get-WcdApplicationsDescriptor -ExecutionOptions $ExecutionOptions `
                -Config $Config -Translations $script:T)
        }

        $script:StepLabels = @{
            ScreenTimeoutAc        = 'Screen timeout (AC)'
            SetActiveSchemeCurrent = 'Apply power scheme'
            AppErp                 = 'ERP client'
        }

        function New-TestExecutionOptions {
            param(
                [string]$Environment = 'Workstation',
                [string]$FormFactor = 'Desktop',
                [string[]]$OptionalTools = @(),
                [bool]$OpenApps = $true
            )

            return [pscustomobject]@{
                Language        = 'FR'
                FormFactor      = $FormFactor
                Environment     = $Environment
                OpenApps        = $OpenApps
                OptionalTools   = $OptionalTools
                NewComputerName = ''
                JoinDomain      = $false
            }
        }

        function Get-TestEntry {
            param([object[]]$Entries, [string]$Label)
            return @($Entries | Where-Object { $_.Label -eq $Label }) | Select-Object -First 1
        }
    }

    Context 'Le triple sens de "skip"' {
        It 'transforme une invite refusee en etape manuelle' {
            $config = @{
                Applications = @(
                    @{ Step = 'AppErp'; Name = 'ERP client'; Action = 'Start'; Target = 'C:\erp.exe' }
                )
            }
            # ApplicationsSkip: le technicien a repondu Non a l'ouverture des
            # applications. C'est OpenApps = $false qui produit ce Resultat, et
            # le descripteur lit la meme option: les deux ne peuvent plus
            # diverger comme le faisait cette fixture.
            $results = @([pscustomobject]@{ Step = 'ApplicationsSkip'; Success = $true; Error = ''; Severity = 'INFO' })

            $options = New-TestExecutionOptions -OpenApps $false
            $entries = @(Get-WcdFinalChecklistEntries -AllResults $results `
                -Descriptors (New-TestDescriptor -Config $config -ExecutionOptions $options) `
                -StepLabels $script:StepLabels -Config $config)
            $entry = Get-TestEntry -Entries $entries -Label 'ERP client'

            $entry.Kind | Should -Be 'manual'
            $entry.Detail | Should -Be $script:T.ApplicationManualDetail
        }

        It 'transforme une etape filtree par l usage en non applicable, pas en avertissement' {
            $config = @{
                Applications = @(
                    @{ Step = 'AppErp'; Name = 'ERP client'; Action = 'Start'; Target = 'C:\erp.exe'; Environment = 'Workstation' }
                )
            }

            $options = New-TestExecutionOptions -Environment 'Vdi'
            $entries = @(Get-WcdFinalChecklistEntries -AllResults @() `
                -Descriptors (New-TestDescriptor -Config $config -ExecutionOptions $options) `
                -StepLabels $script:StepLabels -Config $config)
            $entry = Get-TestEntry -Entries $entries -Label 'ERP client'

            $entry.Kind | Should -Be 'na'
            $entry.Kind | Should -Not -Be 'warning'
            $entry.Detail | Should -Be $script:T.SecondaryNA
        }

        It 'transforme une etape qui n a pas pu s executer en echec' {
            $lookup = @{
                ScreenTimeoutAc = @([pscustomobject]@{
                    Step = 'ScreenTimeoutAc'; Success = $false; Error = 'powercfg a refuse'
                    Severity = 'ERROR'; RemedyKey = 'PowerCfgFailed'
                })
            }

            $entry = Resolve-WcdAutomaticEntry -Label 'Power options' -ResultLookup $lookup `
                -StepKeys @('ScreenTimeoutAc') -StepLabels $script:StepLabels

            $entry.Kind | Should -Be 'error'
            $entry.Detail | Should -Match 'powercfg a refuse'
            $entry.Detail | Should -Match ([regex]::Escape($script:T.Remedy['PowerCfgFailed']))
        }

        It 'transforme une etape rendue au technicien en etape manuelle, pas en echec' {
            $lookup = @{
                AppErp = @([pscustomobject]@{
                    Step = 'AppErp'; Success = $true; Error = 'Verification manuelle requise'; Severity = 'MANUAL'
                })
            }

            $entry = Resolve-WcdAutomaticEntry -Label 'ERP client' -ResultLookup $lookup `
                -StepKeys @('AppErp') -StepLabels $script:StepLabels

            $entry.Kind | Should -Be 'manual'
        }
    }

    Context 'Optionnel et donnees partielles' {
        It 'rend une cible applicative optionnelle absente comme une note, pas un avertissement' {
            # Ce que Config-Applications produit pour une entree Optional absente:
            # INFO, un detail a lire, et aucune remediation.
            $lookup = @{
                AppErp = @([pscustomobject]@{
                    Step = 'AppErp'; Success = $true; Error = 'Absent (optionnel)'; Severity = 'INFO'; RemedyKey = ''
                })
            }

            $entry = Resolve-WcdAutomaticEntry -Label 'ERP client' -ResultLookup $lookup `
                -StepKeys @('AppErp') -StepLabels $script:StepLabels

            $entry.Kind | Should -Be 'success'
            $entry.Detail | Should -Match 'Absent \(optionnel\)'
        }

        It 'avertit quand un module a rapporte une partie seulement de ses etapes prevues' {
            $lookup = @{
                ScreenTimeoutAc = @([pscustomobject]@{
                    Step = 'ScreenTimeoutAc'; Success = $true; Error = ''; Severity = 'INFO'
                })
            }

            $entry = Resolve-WcdAutomaticEntry -Label 'Power options' -ResultLookup $lookup `
                -StepKeys @('ScreenTimeoutAc', 'SetActiveSchemeCurrent') -StepLabels $script:StepLabels

            $entry.Kind | Should -Be 'warning'
            $entry.Detail | Should -Be ($script:T.MissingStepTech -f 'Apply power scheme')
        }

        It 'utilise le genre demande quand le module n a rien rapporte du tout' {
            $entry = Resolve-WcdAutomaticEntry -Label 'Computer name' -ResultLookup @{} `
                -StepKeys @('ComputerName') -StepLabels $script:StepLabels `
                -MissingKind 'manual' -MissingDetail 'A faire a la main.'

            $entry.Kind | Should -Be 'manual'
            $entry.Detail | Should -Be 'A faire a la main.'
        }
    }

    Context 'Format-WcdRemedy' {
        It 'ne rend rien pour une cle absente de $T.Remedy' {
            $remedy = Format-WcdRemedy -Result ([pscustomobject]@{ RemedyKey = 'CleQuiNExistePas' })
            $remedy | Should -BeNullOrEmpty
        }

        It 'ne rend rien pour un resultat sans RemedyKey' {
            $remedy = Format-WcdRemedy -Result ([pscustomobject]@{ Step = 'AppErp'; Success = $true })
            $remedy | Should -BeNullOrEmpty
        }

        It 'retourne le gabarit plutot qu une exception quand RemedyArgs ne correspond pas' {
            # TargetMissing attend deux arguments; on n en donne qu un.
            $remedy = Format-WcdRemedy -Result ([pscustomobject]@{
                RemedyKey = 'TargetMissing'; RemedyArgs = @('C:\absent.exe')
            })

            $remedy | Should -Be $script:T.Remedy['TargetMissing']
        }

        It 'remplit le gabarit quand les arguments correspondent' {
            $remedy = Format-WcdRemedy -Result ([pscustomobject]@{
                RemedyKey = 'TargetMissing'; RemedyArgs = @('C:\absent.exe', 'AppErp')
            })

            $remedy | Should -Be ($script:T.Remedy['TargetMissing'] -f 'C:\absent.exe', 'AppErp')
        }
    }

    Context 'Severite et agregation' {
        It 'classe ERROR au-dessus de WARNING, lui-meme au-dessus du reste' {
            (Get-WcdSeverityRank -Severity 'error') | Should -BeGreaterThan (Get-WcdSeverityRank -Severity 'WARNING')
            (Get-WcdSeverityRank -Severity 'WARNING') | Should -BeGreaterThan (Get-WcdSeverityRank -Severity 'MANUAL')
        }

        It 'prend la couleur de la pire etape d une ligne qui en couvre plusieurs' {
            $lookup = @{
                ScreenTimeoutAc        = @([pscustomobject]@{ Step = 'ScreenTimeoutAc'; Success = $true; Error = ''; Severity = 'INFO' })
                SetActiveSchemeCurrent = @([pscustomobject]@{ Step = 'SetActiveSchemeCurrent'; Success = $false; Error = 'echec'; Severity = 'ERROR' })
            }

            $entry = Resolve-WcdAutomaticEntry -Label 'Power options' -ResultLookup $lookup `
                -StepKeys @('ScreenTimeoutAc', 'SetActiveSchemeCurrent') -StepLabels $script:StepLabels

            $entry.Kind | Should -Be 'error'
        }

        It 'laisse hors du detail une etape informative qui n a rien a dire' {
            $results = @(
                [pscustomobject]@{ Step = 'ScreenTimeoutAc'; Success = $true; Error = ''; Severity = 'INFO' },
                [pscustomobject]@{ Step = 'SetActiveSchemeCurrent'; Success = $true; Error = 'note'; Severity = 'INFO' }
            )

            $detail = Get-WcdAggregateDetail -Results $results -StepLabels $script:StepLabels

            $detail | Should -Be 'Apply power scheme: note'
        }
    }

    Context 'Rendu du Diagnostic' {
        It 'rend les deux sections et la ligne de resume dans le texte de l historique' {
            $moduleStatus = @([pscustomobject]@{ Module = 'Config-Power'; Status = 'OK'; Steps = 2; Detail = '' })
            $entries = @(New-WcdDiagnosticEntry -Label 'Power options' -Kind 'success' -Step 'ScreenTimeoutAc')

            $lines = @(Get-WcdFinalDiagnosticLines -ModuleStatus $moduleStatus -ChecklistEntries $entries -SummaryLine '1 OK')

            $lines | Should -Contain $script:T.DiagFinalByModule
            $lines | Should -Contain $script:T.DiagFinalByStep
            $lines[-1] | Should -Be '1 OK'
            ($lines -join "`n") | Should -Match 'Config-Power'
            ($lines -join "`n") | Should -Match 'Power options'
        }

        It 'traduit le mot d etat d un module en genre de diagnostic' {
            (Get-WcdModuleStatusKind -Status 'OK') | Should -Be 'success'
            (Get-WcdModuleStatusKind -Status 'WARNING') | Should -Be 'warning'
            (Get-WcdModuleStatusKind -Status 'ERREUR') | Should -Be 'error'
        }
    }
}
