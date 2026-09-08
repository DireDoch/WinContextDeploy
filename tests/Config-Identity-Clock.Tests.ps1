Describe 'Config-Identity - horloge' {
    BeforeAll {
        $srcDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'src'
        foreach ($file in @('WcdHelpers.ps1', 'Config-Identity.ps1')) {
            $path = Join-Path $srcDir $file
            if (-not (Test-Path -LiteralPath $path)) { throw ('{0} introuvable.' -f $file) }
            . $path
        }

        # La sortie reelle de w32tm /query /status, en anglais et en francais.
        # Les libelles sont traduits, l ordre des champs ne l est pas: c est
        # exactement l hypothese que l analyseur repose dessus.
        $script:StatusEN = @(
            'Leap Indicator: 0(no warning)'
            'Stratum: 3 (secondary reference - syncd by (S)NTP)'
            'Precision: -23 (119.209ns per tick)'
            'Root Delay: 0.0304726s'
            'Root Dispersion: 7.7757617s'
            'ReferenceId: 0x0A0A0A0A (source IP:  10.10.10.10)'
            'Last Successful Sync Time: 2026-09-08 10:15:02'
            'Source: dc01.corp.example.com'
            'Poll Interval: 10 (1024s)'
        )
        $script:StatusFR = @(
            'Indicateur de saut : 0(aucun avertissement)'
            'Strate : 3 (reference secondaire - synchronisee par (S)NTP)'
            'Precision : -23 (119.209ns par graduation)'
            'Delai de la racine : 0.0304726s'
            'Dispersion de la racine : 7.7757617s'
            'Reference : 0x0A0A0A0A (adresse IP source :  10.10.10.10)'
            'Heure de la derniere synchronisation reussie : 2026-09-08 10:15:02'
            'Source : dc01.corp.example.com'
            'Intervalle d interrogation : 10 (1024s)'
        )
        $script:Now = [datetime]'2026-09-08 12:00:00'

        function New-TestStatusLines {
            param([string]$Source, [string]$LastSync = '2026-09-08 10:15:02', [switch]$French)
            $lines = if ($French) { @($script:StatusFR) } else { @($script:StatusEN) }
            $lines[6] = ($lines[6] -replace ':\s*2026.*$', (': {0}' -f $LastSync))
            $lines[7] = if ($French) { 'Source : {0}' -f $Source } else { 'Source: {0}' -f $Source }
            return $lines
        }
    }

    BeforeEach {
        $script:LogPath = Join-Path $TestDrive ('log_clock_{0}.txt' -f [guid]::NewGuid())
    }

    Context 'fuseau horaire' {
        It 'rapporte OK quand le fuseau correspond au manifeste' {
            Mock -CommandName 'Get-WcdMachineTimeZone' { [pscustomobject]@{ Id = 'Eastern Standard Time'; DisplayName = '(UTC-05:00) Eastern Time' } }
            Mock -CommandName 'Get-WcdTimeStatusOutput' { $script:StatusEN }
            Mock -CommandName 'Test-WcdDomainJoined' { $false }

            $result = Set-WcdClockStatus -ExpectedTimeZone 'Eastern Standard Time' -LogPath $script:LogPath | Where-Object Step -eq 'TimeZone'

            $result.Severity | Should -Be 'INFO'
        }

        It 'nomme les deux fuseaux quand ils different' {
            Mock -CommandName 'Get-WcdMachineTimeZone' { [pscustomobject]@{ Id = 'Pacific Standard Time'; DisplayName = '(UTC-08:00) Pacific Time' } }
            Mock -CommandName 'Get-WcdTimeStatusOutput' { $script:StatusEN }
            Mock -CommandName 'Test-WcdDomainJoined' { $false }

            $result = Set-WcdClockStatus -ExpectedTimeZone 'Eastern Standard Time' -LogPath $script:LogPath | Where-Object Step -eq 'TimeZone'

            $result.Severity | Should -Be 'WARNING'
            $result.Error | Should -Match 'Pacific Standard Time'
            $result.Error | Should -Match 'Eastern Standard Time'
            $result.RemedyKey | Should -Be 'TimeZoneMismatch'
        }

        It 'ne juge rien quand le manifeste ne declare aucun fuseau' {
            # Un parc etale sur plusieurs fuseaux ne doit pas recolter un faux
            # avertissement sur chaque poste hors du siege social.
            Mock -CommandName 'Get-WcdMachineTimeZone' { [pscustomobject]@{ Id = 'Pacific Standard Time'; DisplayName = '(UTC-08:00) Pacific Time' } }
            Mock -CommandName 'Get-WcdTimeStatusOutput' { $script:StatusEN }
            Mock -CommandName 'Test-WcdDomainJoined' { $false }

            $result = Set-WcdClockStatus -ExpectedTimeZone '' -LogPath $script:LogPath | Where-Object Step -eq 'TimeZone'

            $result.Severity | Should -Be 'INFO'
            $result.Error | Should -Match 'Pacific Standard Time'
        }
    }

    Context 'analyse de w32tm' {
        It 'lit une sortie anglaise' {
            $status = ConvertFrom-WcdTimeStatus -Lines $script:StatusEN

            $status.Parsed | Should -BeTrue
            $status.Source | Should -Be 'dc01.corp.example.com'
            $status.NeverSynced | Should -BeFalse
        }

        It 'lit une sortie francaise sans jamais toucher aux libelles' {
            # C est la partie fragile de la question: sur un Windows francais
            # les libelles sont traduits, donc rien ne doit les matcher.
            $status = ConvertFrom-WcdTimeStatus -Lines $script:StatusFR

            $status.Parsed | Should -BeTrue
            $status.Source | Should -Be 'dc01.corp.example.com'
            $status.LastSync | Should -Be ([datetime]'2026-09-08 10:15:02')
        }

        It 'ne cherche aucun libelle anglais dans le source' {
            $source = Get-Content -Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'src/Config-Identity.ps1') -Raw
            $source | Should -Not -Match "match 'Source|match 'Last Successful|-like '\*Source"
        }

        It 'signale une sortie illisible comme son propre etat' {
            $status = ConvertFrom-WcdTimeStatus -Lines @('The following error occurred: The service has not been started.')

            $status.Parsed | Should -BeFalse
        }
    }

    Context 'synchronisation' {
        It 'rapporte OK sur une source de domaine synchronisee recemment' {
            Mock -CommandName 'Get-WcdMachineTimeZone' { [pscustomobject]@{ Id = 'Eastern Standard Time'; DisplayName = 'ET' } }
            Mock -CommandName 'Get-WcdTimeStatusOutput' { New-TestStatusLines -Source 'dc01.corp.example.com' -LastSync ([datetime]::Now.ToString('yyyy-MM-dd HH:mm:ss')) }
            Mock -CommandName 'Test-WcdDomainJoined' { $true }

            $result = Set-WcdClockStatus -LogPath $script:LogPath | Where-Object Step -eq 'TimeSync'

            $result.Severity | Should -Be 'INFO'
            $result.Error | Should -Match 'dc01.corp.example.com'
        }

        It 'avertit sur une horloge CMOS quand le poste est sur le domaine' {
            Mock -CommandName 'Get-WcdMachineTimeZone' { [pscustomobject]@{ Id = 'Eastern Standard Time'; DisplayName = 'ET' } }
            Mock -CommandName 'Get-WcdTimeStatusOutput' { New-TestStatusLines -Source 'Local CMOS Clock' }
            Mock -CommandName 'Test-WcdDomainJoined' { $true }

            $result = Set-WcdClockStatus -LogPath $script:LogPath | Where-Object Step -eq 'TimeSync'

            $result.Severity | Should -Be 'WARNING'
            $result.RemedyKey | Should -Be 'TimeSourceCmos'
        }

        It 'avertit sur une horloge CMOS quand le domaine est sur le point d etre joint' {
            Mock -CommandName 'Get-WcdMachineTimeZone' { [pscustomobject]@{ Id = 'Eastern Standard Time'; DisplayName = 'ET' } }
            Mock -CommandName 'Get-WcdTimeStatusOutput' { New-TestStatusLines -Source 'Local CMOS Clock' }
            Mock -CommandName 'Test-WcdDomainJoined' { $false }

            $result = Set-WcdClockStatus -JoinDomain $true -LogPath $script:LogPath | Where-Object Step -eq 'TimeSync'

            $result.Severity | Should -Be 'WARNING'
            $result.RemedyKey | Should -Be 'TimeSourceCmos'
        }

        It 'ne juge pas une horloge CMOS sur un poste autonome' {
            Mock -CommandName 'Get-WcdMachineTimeZone' { [pscustomobject]@{ Id = 'Eastern Standard Time'; DisplayName = 'ET' } }
            Mock -CommandName 'Get-WcdTimeStatusOutput' { New-TestStatusLines -Source 'Local CMOS Clock' }
            Mock -CommandName 'Test-WcdDomainJoined' { $false }

            $result = Set-WcdClockStatus -LogPath $script:LogPath | Where-Object Step -eq 'TimeSync'

            $result.Severity | Should -Be 'INFO'
        }

        It 'reconnait une horloge CMOS localisee' {
            # Le nom de la source est traduit sur un Windows localise; le motif
            # vise CMOS, un acronyme qui survit a la traduction.
            $status = ConvertFrom-WcdTimeStatus -Lines (New-TestStatusLines -Source 'Horloge CMOS locale' -French)
            $info = Get-WcdTimeSyncInfo -Status $status -DomainJoined $true

            $info.Severity | Should -Be 'WARNING'
            $info.RemedyKey | Should -Be 'TimeSourceCmos'
        }

        It 'avertit quand le poste ne s est jamais synchronise' {
            $status = ConvertFrom-WcdTimeStatus -Lines (New-TestStatusLines -Source 'dc01.corp.example.com' -LastSync 'unspecified')
            $info = Get-WcdTimeSyncInfo -Status $status -DomainJoined $true -Now $script:Now

            $status.NeverSynced | Should -BeTrue
            $info.Severity | Should -Be 'WARNING'
            $info.RemedyKey | Should -Be 'TimeNeverSynced'
        }

        It 'avertit en nommant l age quand la derniere synchronisation est vieille' {
            $status = ConvertFrom-WcdTimeStatus -Lines (New-TestStatusLines -Source 'dc01.corp.example.com' -LastSync '2026-07-01 10:15:02')
            $info = Get-WcdTimeSyncInfo -Status $status -DomainJoined $true -Now $script:Now

            $info.Severity | Should -Be 'WARNING'
            $info.Label | Should -Match '69 days ago'
        }

        It 'ne confond pas une sortie illisible avec une mauvaise horloge' {
            Mock -CommandName 'Get-WcdMachineTimeZone' { [pscustomobject]@{ Id = 'Eastern Standard Time'; DisplayName = 'ET' } }
            Mock -CommandName 'Get-WcdTimeStatusOutput' { @('The service has not been started.') }
            Mock -CommandName 'Test-WcdDomainJoined' { $true }

            $result = Set-WcdClockStatus -LogPath $script:LogPath | Where-Object Step -eq 'TimeSync'

            $result.Severity | Should -Be 'WARNING'
            $result.RemedyKey | Should -Be 'TimeSyncUnparseable'
            $result.RemedyKey | Should -Not -Be 'TimeSourceCmos'
        }
    }

    Context 'contrat du module' {
        It 'ne lance jamais de resync' {
            # Un correctif, pas une verification, et il echoue bruyamment sur le
            # poste meme que cette etape existe pour trouver.
            $source = Get-Content -Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'src/Config-Identity.ps1') -Raw
            $source | Should -Not -Match "'/resync'|Set-TimeZone"
        }
    }
}
