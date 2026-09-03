Describe 'Comment-based help' {
    BeforeAll {
        $script:SrcDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'src'

        # Only top-level functions are part of the surface a reader can call.
        # A function nested inside another one is an implementation detail.
        $script:PublicFunctions = @(Get-ChildItem -Path (Join-Path $script:SrcDir '*.ps1') | ForEach-Object {
            $file = $_.Name
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$null)
            $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
                Where-Object {
                    $null -eq ($_.Parent.Parent.Parent -as [System.Management.Automation.Language.FunctionDefinitionAst])
                } |
                ForEach-Object {
                    [pscustomobject]@{
                        File = $file
                        Name = $_.Name
                        Help = $_.GetHelpContent()
                        Ast  = $_
                    }
                }
        })

        # CONTEXT.md nomme Form Factor, Environment et Optional Tool. L'interface
        # respectait deja ces mots; l'implementation avait derive vers device,
        # usage et engineer, et l'objet $moduleStatus portait les trois seuls
        # identifiants francais du depot.
        #
        # Le motif vise des identifiants precis, pas des sous-chaines:
        # Config-DeviceManager, Get-WcdPnPDevices et Set-WcdDeviceManagerStatus
        # sont corrects, et les chaines affichees 'Echecs: {0}' et
        # 'Avertissements: {0}' sont du francais destine au technicien.
        $script:StalePattern = @(
            'DeviceType', 'Config-Usage', 'Config-Engineer', 'Minimal[A-Z]'
            '\$deviceResult', '\$usageResult', '\$usageLabel', '\$engineer[A-Z]'
            'PromptUsageDesc', 'PromptEngineer'
            'Engineer(BoxTitle|CombineHint|ChoicePrompt|AtLeastOne|InvalidChoice|Selection)'
            '\.(Etapes|Echecs|Avertissements)\b'
            '(?m)^\s*(Etapes|Echecs|Avertissements)\s+='
        ) -join '|'
    }

    It 'trouve les fonctions du projet' {
        $script:PublicFunctions.Count | Should -BeGreaterThan 30
    }

    It 'donne un synopsis a chaque fonction Wcd' {
        $missing = @($script:PublicFunctions |
            Where-Object { $_.Name -match 'Wcd' } |
            Where-Object { $null -eq $_.Help -or [string]::IsNullOrWhiteSpace($_.Help.Synopsis) } |
            ForEach-Object { '{0} :: {1}' -f $_.File, $_.Name })

        $missing -join ', ' | Should -BeNullOrEmpty
    }

    It 'donne au moins un exemple a chaque fonction Wcd' {
        $missing = @($script:PublicFunctions |
            Where-Object { $_.Name -match 'Wcd' } |
            Where-Object { $null -eq $_.Help -or @($_.Help.Examples).Count -eq 0 } |
            ForEach-Object { '{0} :: {1}' -f $_.File, $_.Name })

        $missing -join ', ' | Should -BeNullOrEmpty
    }

    It 'documente chaque parametre declare' {
        $missing = @()
        foreach ($function in ($script:PublicFunctions | Where-Object { $_.Name -match 'Wcd' })) {
            $declared = @($function.Ast.Body.ParamBlock.Parameters |
                ForEach-Object { $_.Name.VariablePath.UserPath })
            if ($declared.Count -eq 0) { continue }

            $documented = if ($null -ne $function.Help) { @($function.Help.Parameters.Keys) } else { @() }
            foreach ($parameter in $declared) {
                if (@($documented) -notcontains $parameter.ToUpperInvariant()) {
                    $missing += '{0} :: {1} -{2}' -f $function.File, $function.Name, $parameter
                }
            }
        }

        $missing -join ', ' | Should -BeNullOrEmpty
    }

    It 'ne mentionne plus les parametres et modules renommes' {
        $stale = @(Get-ChildItem -Path (Join-Path $script:SrcDir '*.ps1') |
            Select-String -Pattern $script:StalePattern |
            ForEach-Object { '{0}:{1}' -f $_.Filename, $_.LineNumber })

        $stale -join ', ' | Should -BeNullOrEmpty
    }

    It 'ne signale pas les noms legitimes qui contiennent Device' {
        # Le motif doit rester ancre sur les identifiants derivants. S'il attrape
        # ceux-ci, il est trop large et sera desactive a la premiere fausse alerte.
        $legitimate = @(
            'Config-DeviceManager.ps1'
            'Set-WcdDeviceManagerStatus -LogPath $logPath'
            'Get-WcdPnPDevices'
            "FailDetails             = 'Echecs: {0}'"
            "WarningDetails          = 'Avertissements: {0}'"
            "DeviceManager  = 'Device Manager'"
        )

        foreach ($line in $legitimate) {
            $line | Should -Not -Match $script:StalePattern -Because ('"{0}" est correct' -f $line)
        }
    }
}
