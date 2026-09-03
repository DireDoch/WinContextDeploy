Describe 'Translations' {
    BeforeAll {
        $orchestrator = Join-Path (Split-Path $PSScriptRoot -Parent) 'src/Invoke-WcdConfiguration.ps1'
        if (-not (Test-Path -LiteralPath $orchestrator)) { throw 'Invoke-WcdConfiguration.ps1 introuvable.' }

        # L'orchestrateur ne peut pas etre dot-source: il executerait toute
        # l'execution puis appellerait exit. On extrait donc la seule
        # affectation de $T avec l'AST, comme Help.Tests.ps1 extrait les
        # definitions de fonctions, et on la rejoue pour chaque langue.
        #
        # Les deux tables sont des litteraux purs - aucune expression, aucun
        # appel - donc les rejouer ne fait rien d'autre que construire deux
        # hashtables.
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($orchestrator, [ref]$null, [ref]$null)
        $assignment = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $node.Left.Extent.Text -eq '$T'
        }, $true))

        if ($assignment.Count -ne 1) {
            throw ('Attendu une seule affectation de $T dans Invoke-WcdConfiguration.ps1, trouve {0}.' -f $assignment.Count)
        }

        $builder = [scriptblock]::Create(
            "param([string]`$ScriptUI)`n" + $assignment[0].Extent.Text + "`nreturn `$T")

        $script:TableEN = & $builder 'EN'
        $script:TableFR = & $builder 'FR'

        # Une comparaison plate de .Keys manquerait exactement les cas qui font
        # mal: Checklist, Labels, Remedy et ComputerNameRejected sont imbriques.
        function Get-WcdTranslationKeyPath {
            param($Table, [string]$Prefix = '')

            foreach ($key in $Table.Keys) {
                $path = if ($Prefix) { '{0}.{1}' -f $Prefix, $key } else { [string]$key }
                $path
                if ($Table[$key] -is [hashtable]) {
                    Get-WcdTranslationKeyPath -Table $Table[$key] -Prefix $path
                }
            }
        }

        $script:KeysEN = @(Get-WcdTranslationKeyPath -Table $script:TableEN | Sort-Object)
        $script:KeysFR = @(Get-WcdTranslationKeyPath -Table $script:TableFR | Sort-Object)
    }

    It 'extrait bien les deux tables' {
        $script:KeysEN.Count | Should -BeGreaterThan 100
        $script:KeysFR.Count | Should -BeGreaterThan 100
    }

    It 'descend dans les tables imbriquees' {
        # Si la recursion casse, la parite passerait a plat sans rien verifier.
        $script:KeysEN | Should -Contain 'Checklist.Taskbar'
        $script:KeysEN | Should -Contain 'Labels.Laptop'
        $script:KeysEN | Should -Contain 'Remedy.RequiresAdmin'
        $script:KeysEN | Should -Contain 'ComputerNameRejected.Length'
    }

    It 'expose les memes cles en EN et en FR' {
        # Une cle presente d'un seul cote ne leve rien: PowerShell rend $null et
        # la ligne s'affiche sans libelle, dans une seule langue. Personne ne le
        # voit avant qu'un technicien lance l'outil en francais.
        $missingInFR = @($script:KeysEN | Where-Object { $script:KeysFR -notcontains $_ })
        $missingInEN = @($script:KeysFR | Where-Object { $script:KeysEN -notcontains $_ })

        $missingInFR -join ', ' | Should -BeNullOrEmpty -Because 'ces cles EN manquent en FR'
        $missingInEN -join ', ' | Should -BeNullOrEmpty -Because 'ces cles FR manquent en EN'
    }

    It 'ne laisse aucune valeur vide' {
        # Une cle presente mais vide rend la meme ligne blanche qu'une cle absente.
        $empty = @()
        foreach ($table in @(@{ Name = 'EN'; Value = $script:TableEN }, @{ Name = 'FR'; Value = $script:TableFR })) {
            foreach ($path in @(Get-WcdTranslationKeyPath -Table $table.Value)) {
                $node = $table.Value
                foreach ($segment in $path.Split('.')) { $node = $node[$segment] }
                if ($node -is [hashtable]) { continue }
                if ([string]::IsNullOrWhiteSpace([string]$node)) { $empty += '{0}:{1}' -f $table.Name, $path }
            }
        }

        $empty -join ', ' | Should -BeNullOrEmpty
    }
}