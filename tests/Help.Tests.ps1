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
        # -DeviceType -> -FormFactor, -Usage -> -Environment, Minimal* -> Wcd*,
        # Config-Usage et Config-Engineer ont disparu.
        $stale = @(Get-ChildItem -Path (Join-Path $script:SrcDir '*.ps1') |
            Select-String -Pattern 'DeviceType|Config-Usage|Config-Engineer|Minimal[A-Z]' |
            ForEach-Object { '{0}:{1}' -f $_.Filename, $_.LineNumber })

        $stale -join ', ' | Should -BeNullOrEmpty
    }
}
