Describe 'Module descriptors' {
    BeforeAll {
        $script:SrcDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'src'
        . (Join-Path $script:SrcDir 'WcdHelpers.ps1')

        $script:ModuleFiles = @(Get-ChildItem -Path (Join-Path $script:SrcDir 'Config-*.ps1') | Sort-Object Name)
        foreach ($moduleFile in $script:ModuleFiles) { . $moduleFile.FullName }

        # La table reelle, extraite par l'AST: un descripteur qui nomme une cle
        # de checklist inexistante rendrait une ligne sans libelle, et une table
        # recopiee ici masquerait exactement ce bug.
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $script:SrcDir 'Invoke-WcdConfiguration.ps1'), [ref]$null, [ref]$null)
        $assignment = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $node.Left.Extent.Text -eq '$T'
        }, $false))[0]
        $script:Translations = & ([scriptblock]::Create(('param($ScriptUI) {0}' -f $assignment.Right.Extent.Text))) 'EN'

        $script:Config = @{
            Applications = @(
                @{ Step = 'AppOutlook'; Name = 'Outlook';    Action = 'Launch';      Target = 'outlook.exe' }
                @{ Step = 'AppErp';     Name = 'ERP client'; Action = 'Launch';      Target = 'erp.exe'; Environment = 'Workstation' }
                @{ Step = 'AppCad';     Name = 'CAD viewer'; Action = 'Launch';      Target = 'cad.exe'; Prompt = $true }
                @{ Step = 'AppWinget';  Name = 'Installer';  Action = 'CheckWinget'; Target = 'Microsoft.X' }
            )
            Printers = @(@{ Name = 'Floor-4-Colour'; Connection = '\\srv\Floor-4-Colour' })
            Domain   = @{ Name = 'corp.example.com'; OUPath = 'OU=W,DC=corp' }
        }

        # Chaque combinaison qui change ce qu'un descripteur declare: Form Factor
        # pour Config-Power, Environment pour Config-Applications, OpenApps pour
        # la bascule automatique/manuelle, et l'identite pour le Module saute.
        $script:OptionSets = @(
            @{ FormFactor = 'Laptop';  Environment = 'Workstation'; OpenApps = $true;  OptionalTools = @('CAD viewer'); NewComputerName = 'POSTE-01'; JoinDomain = $true }
            @{ FormFactor = 'Desktop'; Environment = 'Vdi';         OpenApps = $false; OptionalTools = @();             NewComputerName = '';         JoinDomain = $false }
            @{ FormFactor = 'Laptop';  Environment = 'Vdi';         OpenApps = $true;  OptionalTools = @();             NewComputerName = '';         JoinDomain = $true }
        ) | ForEach-Object {
            [pscustomobject]@{
                Language        = 'fr-CA'
                FormFactor      = $_.FormFactor
                Environment     = $_.Environment
                OpenApps        = $_.OpenApps
                OptionalTools   = $_.OptionalTools
                NewComputerName = $_.NewComputerName
                JoinDomain      = $_.JoinDomain
            }
        }

        function Get-TestDescriptorSet {
            param([pscustomobject]$ExecutionOptions, [hashtable]$Config = $script:Config)

            return @($script:ModuleFiles | ForEach-Object {
                & ('Get-Wcd{0}Descriptor' -f ($_.BaseName -replace '^Config-', '')) `
                    -ExecutionOptions $ExecutionOptions -Config $Config -Translations $script:Translations
            })
        }
    }

    It 'trouve les douze Modules' {
        $script:ModuleFiles.Count | Should -Be 12
    }

    It 'expose une fonction descripteur par Module' {
        $missing = @($script:ModuleFiles | Where-Object {
            $name = 'Get-Wcd{0}Descriptor' -f ($_.BaseName -replace '^Config-', '')
            -not (Get-Command -Name $name -ErrorAction SilentlyContinue)
        } | ForEach-Object { $_.Name })

        $missing -join ', ' | Should -BeNullOrEmpty
    }

    It 'respecte le contrat, quel que soit le profil d execution' {
        $problems = @()
        foreach ($options in $script:OptionSets) {
            foreach ($moduleFile in $script:ModuleFiles) {
                $descriptor = & ('Get-Wcd{0}Descriptor' -f ($moduleFile.BaseName -replace '^Config-', '')) `
                    -ExecutionOptions $options -Config $script:Config -Translations $script:Translations
                foreach ($problem in @(Test-WcdModuleDescriptor -Descriptor $descriptor -ExpectedName $moduleFile.BaseName)) {
                    $problems += '{0} [{1}/{2}]: {3}' -f $moduleFile.BaseName, $options.FormFactor, $options.Environment, $problem
                }
            }
        }

        $problems -join ' | ' | Should -BeNullOrEmpty
    }

    It 'tient aussi avec un manifeste vide' {
        $options = $script:OptionSets[0]
        $problems = @()
        foreach ($moduleFile in $script:ModuleFiles) {
            $descriptor = & ('Get-Wcd{0}Descriptor' -f ($moduleFile.BaseName -replace '^Config-', '')) `
                -ExecutionOptions $options -Config @{} -Translations $script:Translations
            $problems += @(Test-WcdModuleDescriptor -Descriptor $descriptor -ExpectedName $moduleFile.BaseName)
        }

        $problems -join ' | ' | Should -BeNullOrEmpty
    }

    It 'donne a chaque Module un Order et un RowOrder uniques' {
        # Deux Modules au meme Order, et l'ordre d'execution depend du tri, donc
        # du hasard. C'est le seul point d'enregistrement qui reste.
        $descriptors = Get-TestDescriptorSet -ExecutionOptions $script:OptionSets[0]

        @($descriptors.Order | Select-Object -Unique).Count | Should -Be $descriptors.Count
        @($descriptors.RowOrder | Select-Object -Unique).Count | Should -Be $descriptors.Count
    }

    It 'ne fait reference qu a des Etapes qu il declare' {
        # Une cle d'Etape mal tapee dans une ligne ne leve rien: la ligne se
        # rend en avertissement "etape technique manquante" et ressemble a un
        # Module qui n a pas tourne.
        $unknown = @()
        foreach ($options in $script:OptionSets) {
            foreach ($descriptor in (Get-TestDescriptorSet -ExecutionOptions $options)) {
                $declared = @($descriptor.Steps | ForEach-Object { [string]$_.Key })
                foreach ($row in @($descriptor.Rows)) {
                    # Une ligne fixe porte Step au singulier et aucune Etape.
                    if ($null -eq $row.Steps) { continue }
                    foreach ($stepKey in @($row.Steps)) {
                        if ($declared -notcontains [string]$stepKey) {
                            $unknown += '{0} -> {1}' -f $descriptor.Name, $stepKey
                        }
                    }
                }
            }
        }

        $unknown -join ', ' | Should -BeNullOrEmpty
    }

    It 'donne un libelle a chaque ligne' {
        # Une ligne sans libelle est exactement le symptome d'une cle $T absente.
        $blank = @()
        foreach ($options in $script:OptionSets) {
            foreach ($descriptor in (Get-TestDescriptorSet -ExecutionOptions $options)) {
                foreach ($row in @($descriptor.Rows)) {
                    if ([string]::IsNullOrWhiteSpace([string]$row.Label)) { $blank += $descriptor.Name }
                }
            }
        }

        $blank -join ', ' | Should -BeNullOrEmpty
    }

    Context 'Test-WcdModuleDescriptor' {
        BeforeAll {
            function script:New-ValidDescriptor {
                [pscustomobject]@{
                    Name     = 'Config-Sample'
                    Order    = 10
                    RowOrder = 10
                    Steps    = @(@{ Key = 'SampleStep'; Label = 'Sample step' })
                    Rows     = @(@{ Label = 'Sample'; Steps = @('SampleStep') })
                    # Un Module valide qui ne produit aucun Resultat.
                    Invoke   = { param($ctx) if ($ctx) { @() } }
                }
            }
        }

        It 'accepte un descripteur valide' {
            @(Test-WcdModuleDescriptor -Descriptor (New-ValidDescriptor)) | Should -BeNullOrEmpty
        }

        It 'accepte des Steps vides: le Module est simplement saute' {
            $descriptor = New-ValidDescriptor
            $descriptor.Steps = @()
            @(Test-WcdModuleDescriptor -Descriptor $descriptor) | Should -BeNullOrEmpty
        }

        It 'refuse un champ obligatoire absent' {
            # Le garde n a de valeur que s il attrape chacun de ces cas: c est
            # exactement la liste de controle de six points qu il remplace.
            foreach ($field in @('Name', 'Order', 'RowOrder', 'Steps', 'Rows', 'Invoke')) {
                $descriptor = New-ValidDescriptor
                $descriptor.PSObject.Properties.Remove($field)

                @(Test-WcdModuleDescriptor -Descriptor $descriptor).Count |
                    Should -BeGreaterThan 0 -Because ('{0} absent doit etre signale' -f $field)
            }
        }

        It 'refuse un nom qui ne correspond pas au fichier' {
            @(Test-WcdModuleDescriptor -Descriptor (New-ValidDescriptor) -ExpectedName 'Config-Other') |
                Should -Not -BeNullOrEmpty
        }

        It 'refuse une Etape sans cle ou sans libelle' {
            $descriptor = New-ValidDescriptor
            $descriptor.Steps = @(@{ Key = 'OnlyKey' })
            @(Test-WcdModuleDescriptor -Descriptor $descriptor) | Should -Not -BeNullOrEmpty

            $descriptor = New-ValidDescriptor
            $descriptor.Steps = @(@{ Label = 'Only label' })
            @(Test-WcdModuleDescriptor -Descriptor $descriptor) | Should -Not -BeNullOrEmpty
        }

        It 'refuse une ligne qui ne dit ni Steps ni Kind' {
            $descriptor = New-ValidDescriptor
            $descriptor.Rows = @(@{ Label = 'Sample' })
            @(Test-WcdModuleDescriptor -Descriptor $descriptor) | Should -Not -BeNullOrEmpty
        }

        It 'refuse une ligne qui dit les deux' {
            $descriptor = New-ValidDescriptor
            $descriptor.Rows = @(@{ Label = 'Sample'; Steps = @('SampleStep'); Kind = 'manual' })
            @(Test-WcdModuleDescriptor -Descriptor $descriptor) | Should -Not -BeNullOrEmpty
        }

        It 'refuse un Kind hors de la liste' {
            $descriptor = New-ValidDescriptor
            $descriptor.Rows = @(@{ Label = 'Sample'; Kind = 'catastrophe' })
            @(Test-WcdModuleDescriptor -Descriptor $descriptor) | Should -Not -BeNullOrEmpty
        }

        It 'refuse un Invoke qui n est pas un scriptblock' {
            $descriptor = New-ValidDescriptor
            $descriptor.Invoke = 'Set-WcdSomething'
            @(Test-WcdModuleDescriptor -Descriptor $descriptor) | Should -Not -BeNullOrEmpty
        }

        It 'refuse un descripteur nul' {
            @(Test-WcdModuleDescriptor -Descriptor $null) | Should -Not -BeNullOrEmpty
        }
    }
}