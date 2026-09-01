Describe 'Config-Identity' {
    BeforeAll {
        $srcDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'src'
        $helpersPath = Join-Path $srcDir 'WcdHelpers.ps1'
        $modulePath  = Join-Path $srcDir 'Config-Identity.ps1'

        if (-not (Test-Path -LiteralPath $helpersPath)) { throw 'WcdHelpers.ps1 introuvable.' }
        if (-not (Test-Path -LiteralPath $modulePath))  { throw 'Config-Identity.ps1 introuvable.' }

        . $helpersPath
        . $modulePath

        # Un identifiant bidon: jamais envoye nulle part, seulement mocke.
        # Construit caractere par caractere plutot qu avec ConvertTo-SecureString
        # -AsPlainText, que PSScriptAnalyzer refuse a juste titre.
        function script:New-TestCredential {
            param([string]$Secret = 'MotDePasseSecret123')
            $secure = New-Object System.Security.SecureString
            foreach ($char in $Secret.ToCharArray()) { $secure.AppendChar($char) }
            $secure.MakeReadOnly()
            return (New-Object System.Management.Automation.PSCredential('CORP\tech', $secure))
        }
    }

    Context 'Test-WcdComputerName' {
        It 'accepte un nom valide' {
            Test-WcdComputerName -Name 'POSTE-01' -CurrentName 'WIN-ABC' | Should -Be ''
        }

        It 'refuse un nom vide ou trop long' {
            Test-WcdComputerName -Name '' -CurrentName 'WIN-ABC' | Should -Be 'Length'
            Test-WcdComputerName -Name ('A' * 16) -CurrentName 'WIN-ABC' | Should -Be 'Length'
            Test-WcdComputerName -Name ('A' * 15) -CurrentName 'WIN-ABC' | Should -Be ''
        }

        It 'refuse les espaces et les caracteres interdits' {
            foreach ($name in @('POSTE 01', 'POSTE_01', 'POSTE.01', 'POSTE\01', 'POSTE!01', 'POSTE,01')) {
                Test-WcdComputerName -Name $name -CurrentName 'WIN-ABC' | Should -Be 'Characters'
            }
        }

        It 'refuse un nom entierement numerique' {
            Test-WcdComputerName -Name '12345' -CurrentName 'WIN-ABC' | Should -Be 'AllDigits'
        }

        It 'signale un nom identique a l actuel, sans casse' {
            Test-WcdComputerName -Name 'POSTE-01' -CurrentName 'poste-01' | Should -Be 'Unchanged'
        }
    }

    Context 'Get-WcdDomainTarget' {
        It 'retourne null quand le manifeste ne declare pas de domaine' {
            Get-WcdDomainTarget | Should -BeNullOrEmpty
            Get-WcdDomainTarget -Config @{} | Should -BeNullOrEmpty
            Get-WcdDomainTarget -Config @{ Domain = @{} } | Should -BeNullOrEmpty
            Get-WcdDomainTarget -Config @{ Domain = @{ Name = '  ' } } | Should -BeNullOrEmpty
        }

        It 'retourne le nom et l unite d organisation quand ils sont declares' {
            $target = Get-WcdDomainTarget -Config @{ Domain = @{ Name = 'corp.example.com'; OUPath = 'OU=Workstations,DC=corp' } }

            $target.Name | Should -Be 'corp.example.com'
            $target.OUPath | Should -Be 'OU=Workstations,DC=corp'
        }
    }

    Context 'Get-WcdModuleProgressPlan' {
        BeforeAll {
            function script:New-TestOptions {
                param([string]$NewComputerName = '', [bool]$JoinDomain = $false)
                return [pscustomobject]@{
                    Language        = 'fr-CA'
                    FormFactor      = 'Laptop'
                    Environment     = 'Workstation'
                    OpenApps        = $false
                    OptionalTools   = @()
                    NewComputerName = $NewComputerName
                    JoinDomain      = $JoinDomain
                }
            }
        }

        It 'ne planifie aucune etape en -NonInteractive, donc le Module est saute' {
            # -NonInteractive ne demande rien, donc ni nom ni jonction: le plan
            # est vide, la boucle de modules saute Config-Identity, et la
            # checklist rapporte les deux lignes comme MANUAL.
            $plan = Get-WcdModuleProgressPlan -ExecutionOptions (New-TestOptions) -Config @{}

            @($plan['Config-Identity']).Count | Should -Be 0
        }

        It 'ne planifie que les etapes demandees' {
            $plan = Get-WcdModuleProgressPlan -ExecutionOptions (New-TestOptions -NewComputerName 'POSTE-01') -Config @{}
            @($plan['Config-Identity']) | Should -Be @('ComputerName')

            $plan = Get-WcdModuleProgressPlan -ExecutionOptions (New-TestOptions -JoinDomain $true) -Config @{}
            @($plan['Config-Identity']) | Should -Be @('DomainJoin')

            $plan = Get-WcdModuleProgressPlan -ExecutionOptions (New-TestOptions -NewComputerName 'POSTE-01' -JoinDomain $true) -Config @{}
            @($plan['Config-Identity']) | Should -Be @('ComputerName', 'DomainJoin')
        }
    }

    Context 'Set-WcdMachineIdentity' {
        BeforeAll {
            Mock -CommandName 'Invoke-WcdRenameComputer' { }
            Mock -CommandName 'Invoke-WcdAddComputer' { }
            Mock -CommandName 'Get-WcdJoinCredential' { New-TestCredential }
        }

        It 'ne fait rien et ne rapporte rien quand ni l un ni l autre n est demande' {
            $logPath = Join-Path $TestDrive 'log_id_neither.txt'

            $results = @(Set-WcdMachineIdentity -LogPath $logPath)

            $results.Count | Should -Be 0
            Should -Invoke -CommandName 'Invoke-WcdRenameComputer' -Times 0
            Should -Invoke -CommandName 'Invoke-WcdAddComputer' -Times 0
        }

        It 'renomme seulement, sans toucher au domaine' {
            $logPath = Join-Path $TestDrive 'log_id_rename.txt'

            $results = @(Set-WcdMachineIdentity -NewComputerName 'POSTE-01' -CurrentName 'WIN-ABC' -LogPath $logPath)

            $results.Count | Should -Be 1
            $results[0].Step | Should -Be 'ComputerName'
            $results[0].Success | Should -BeTrue
            $results[0].Severity | Should -Be 'INFO'
            Should -Invoke -CommandName 'Invoke-WcdRenameComputer' -Times 1 -ParameterFilter { $NewName -eq 'POSTE-01' }
            Should -Invoke -CommandName 'Invoke-WcdAddComputer' -Times 0
            Should -Invoke -CommandName 'Get-WcdJoinCredential' -Times 0
        }

        It 'joint le domaine seulement, sans renommer' {
            $logPath = Join-Path $TestDrive 'log_id_join.txt'

            $results = @(Set-WcdMachineIdentity -JoinDomain $true -DomainName 'corp.example.com' -CurrentName 'WIN-ABC' -LogPath $logPath)

            $results.Count | Should -Be 1
            $results[0].Step | Should -Be 'DomainJoin'
            $results[0].Severity | Should -Be 'INFO'
            Should -Invoke -CommandName 'Invoke-WcdAddComputer' -Times 1 -ParameterFilter {
                $DomainName -eq 'corp.example.com' -and [string]::IsNullOrEmpty($NewName)
            }
            Should -Invoke -CommandName 'Invoke-WcdRenameComputer' -Times 0
        }

        It 'renomme et joint en un seul appel quand les deux sont demandes' {
            $logPath = Join-Path $TestDrive 'log_id_both.txt'

            $results = @(Set-WcdMachineIdentity -NewComputerName 'POSTE-01' -JoinDomain $true `
                -DomainName 'corp.example.com' -OUPath 'OU=Workstations,DC=corp' -CurrentName 'WIN-ABC' -LogPath $logPath)

            # Un seul appel, donc un seul redemarrage.
            Should -Invoke -CommandName 'Invoke-WcdAddComputer' -Times 1 -ParameterFilter {
                $DomainName -eq 'corp.example.com' -and $NewName -eq 'POSTE-01' -and $OUPath -eq 'OU=Workstations,DC=corp'
            }
            Should -Invoke -CommandName 'Invoke-WcdRenameComputer' -Times 0

            $results.Count | Should -Be 2
            @($results | Where-Object { $_.Severity -ne 'INFO' }).Count | Should -Be 0
            @($results | ForEach-Object { $_.Step }) | Should -Contain 'ComputerName'
            @($results | ForEach-Object { $_.Step }) | Should -Contain 'DomainJoin'
        }

        It 'traite un nom identique comme un no-op, sans appeler quoi que ce soit' {
            $logPath = Join-Path $TestDrive 'log_id_same.txt'

            $results = @(Set-WcdMachineIdentity -NewComputerName 'WIN-ABC' -CurrentName 'win-abc' -LogPath $logPath)

            $results[0].Step | Should -Be 'ComputerName'
            $results[0].Success | Should -BeTrue
            $results[0].Severity | Should -Be 'INFO'
            $results[0].Error | Should -Match 'WIN-ABC'
            Should -Invoke -CommandName 'Invoke-WcdRenameComputer' -Times 0
        }

        It 'refuse un nom invalide avant tout appel' {
            $logPath = Join-Path $TestDrive 'log_id_invalid.txt'

            $results = @(Set-WcdMachineIdentity -NewComputerName 'POSTE 01' -CurrentName 'WIN-ABC' -LogPath $logPath)

            $results[0].Success | Should -BeFalse
            $results[0].Severity | Should -Be 'ERROR'
            $results[0].RemedyKey | Should -Be 'ComputerNameInvalid'
            Should -Invoke -CommandName 'Invoke-WcdRenameComputer' -Times 0
        }

        It 'rapporte un echec quand la fenetre d identifiants est annulee' {
            $logPath = Join-Path $TestDrive 'log_id_cancel.txt'

            Mock -CommandName 'Get-WcdJoinCredential' { $null }

            $results = @(Set-WcdMachineIdentity -JoinDomain $true -DomainName 'corp.example.com' -CurrentName 'WIN-ABC' -LogPath $logPath)

            $results.Count | Should -Be 1
            $results[0].Step | Should -Be 'DomainJoin'
            $results[0].Success | Should -BeFalse
            $results[0].Severity | Should -Be 'ERROR'
            $results[0].RemedyKey | Should -Be 'JoinCancelled'
            Should -Invoke -CommandName 'Invoke-WcdAddComputer' -Times 0
        }

        It 'renomme quand meme si les identifiants sont annules et que les deux etaient demandes' {
            $logPath = Join-Path $TestDrive 'log_id_cancel_both.txt'

            Mock -CommandName 'Get-WcdJoinCredential' { $null }

            $results = @(Set-WcdMachineIdentity -NewComputerName 'POSTE-01' -JoinDomain $true `
                -DomainName 'corp.example.com' -CurrentName 'WIN-ABC' -LogPath $logPath)

            # Le nom demande ne doit pas disparaitre avec la jonction annulee.
            Should -Invoke -CommandName 'Invoke-WcdRenameComputer' -Times 1 -ParameterFilter { $NewName -eq 'POSTE-01' }

            $name = @($results | Where-Object { $_.Step -eq 'ComputerName' })[0]
            $join = @($results | Where-Object { $_.Step -eq 'DomainJoin' })[0]
            $name.Severity | Should -Be 'INFO'
            $join.Severity | Should -Be 'ERROR'
            $join.RemedyKey | Should -Be 'JoinCancelled'
        }

        It 'rapporte un echec de jonction sans faire planter la run' {
            $logPath = Join-Path $TestDrive 'log_id_joinfail.txt'

            Mock -CommandName 'Invoke-WcdAddComputer' { throw 'Le domaine est injoignable' }

            $results = @(Set-WcdMachineIdentity -JoinDomain $true -DomainName 'corp.example.com' -CurrentName 'WIN-ABC' -LogPath $logPath)

            $results[0].Success | Should -BeFalse
            $results[0].Severity | Should -Be 'ERROR'
            $results[0].Error | Should -Match 'injoignable'
            $results[0].RemedyKey | Should -Be 'DomainJoinFailed'
        }

        It 'rapporte un echec de renommage sans faire planter la run' {
            $logPath = Join-Path $TestDrive 'log_id_renamefail.txt'

            Mock -CommandName 'Invoke-WcdRenameComputer' { throw 'Acces refuse' }

            $results = @(Set-WcdMachineIdentity -NewComputerName 'POSTE-01' -CurrentName 'WIN-ABC' -LogPath $logPath)

            $results[0].Success | Should -BeFalse
            $results[0].Severity | Should -Be 'ERROR'
            $results[0].RemedyKey | Should -Be 'ComputerNameFailed'
        }

        It 'signale les etapes demandees comme exigeant une elevation, sans rien tenter' {
            $logPath = Join-Path $TestDrive 'log_id_notelevated.txt'

            $results = @(Set-WcdMachineIdentity -NewComputerName 'POSTE-01' -JoinDomain $true `
                -DomainName 'corp.example.com' -CurrentName 'WIN-ABC' -Elevated $false -LogPath $logPath)

            $results.Count | Should -Be 2
            foreach ($result in $results) {
                $result.Success | Should -BeTrue
                $result.Severity | Should -Be 'WARNING'
                $result.RemedyKey | Should -Be 'RequiresAdmin'
            }

            # Rien tente, et surtout aucune fenetre d identifiants ouverte pour
            # une jonction qui ne peut pas aboutir.
            Should -Invoke -CommandName 'Invoke-WcdRenameComputer' -Times 0
            Should -Invoke -CommandName 'Invoke-WcdAddComputer' -Times 0
            Should -Invoke -CommandName 'Get-WcdJoinCredential' -Times 0
        }

        It 'ne marque Applied que sur une etape qui a vraiment change la machine' {
            $logPath = Join-Path $TestDrive 'log_id_applied.txt'

            # Un vrai renommage: le redemarrage est reellement en attente.
            $applied = @(Set-WcdMachineIdentity -NewComputerName 'POSTE-01' -CurrentName 'WIN-ABC' -LogPath $logPath)
            $applied[0].Applied | Should -BeTrue

            # Un nom identique: rien n a change, donc rien a redemarrer. C est
            # ce que la ligne "Redemarrage requis" de la checklist lit.
            $noop = @(Set-WcdMachineIdentity -NewComputerName 'WIN-ABC' -CurrentName 'WIN-ABC' -LogPath $logPath)
            $noop[0].Applied | Should -Not -BeTrue

            # Un echec non plus.
            Mock -CommandName 'Invoke-WcdRenameComputer' { throw 'Acces refuse' }
            $failed = @(Set-WcdMachineIdentity -NewComputerName 'POSTE-02' -CurrentName 'WIN-ABC' -LogPath $logPath)
            $failed[0].Applied | Should -Not -BeTrue
        }

        It 'ne laisse jamais un identifiant atteindre le journal' {
            $logPath = Join-Path $TestDrive 'log_id_secret.txt'
            $password = 'MotDePasseSecret123'

            Mock -CommandName 'Get-WcdJoinCredential' { New-TestCredential -Secret $password }

            $results = @(Set-WcdMachineIdentity -NewComputerName 'POSTE-01' -JoinDomain $true `
                -DomainName 'corp.example.com' -CurrentName 'WIN-ABC' -LogPath $logPath)

            $logContent = Get-Content -Path $logPath -Raw
            $logContent | Should -Not -Match $password
            $logContent | Should -Not -Match 'CORP\\tech'

            # Ni le Result, qui finit dans le diagnostic et le rapport JSON.
            foreach ($result in $results) {
                ($result | Out-String) | Should -Not -Match $password
            }
        }
    }
}
