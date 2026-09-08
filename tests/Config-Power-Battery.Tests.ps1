Describe 'Config-Power - sante de la pile' {
    BeforeAll {
        $srcDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'src'
        foreach ($file in @('WcdHelpers.ps1', 'Config-Power.ps1')) {
            $path = Join-Path $srcDir $file
            if (-not (Test-Path -LiteralPath $path)) { throw ('{0} introuvable.' -f $file) }
            . $path
        }

        # La forme reelle du tableau de piles de powercfg /batteryreport. Les
        # libelles sont traduits sur un Windows localise, d ou le francais ici:
        # rien dans l analyseur ne doit dependre d eux.
        function New-TestBatteryHtml {
            param([string]$Design = '52,000', [string]$FullCharge = '48,900', [switch]$French, [switch]$NoBattery)

            $rows = if ($NoBattery) {
                '<tr><td>No battery is installed.</td></tr>'
            } elseif ($French) {
                @(
                    '<tr><td class="tp">CAPACITE NOMINALE</td><td>{0} mWh</td></tr>' -f $Design
                    '<tr><td class="tp">CAPACITE A PLEINE CHARGE</td><td>{0} mWh</td></tr>' -f $FullCharge
                    '<tr><td class="tp">NOMBRE DE CYCLES</td><td>112</td></tr>'
                ) -join ''
            } else {
                @(
                    '<tr><td class="tp">DESIGN CAPACITY</td><td>{0} mWh</td></tr>' -f $Design
                    '<tr><td class="tp">FULL CHARGE CAPACITY</td><td>{0} mWh</td></tr>' -f $FullCharge
                    '<tr><td class="tp">CYCLE COUNT</td><td>112</td></tr>'
                ) -join ''
            }

            return ('<html><head><title>Battery report</title></head><body><table>{0}</table></body></html>' -f $rows)
        }
    }

    BeforeEach {
        $script:LogPath = Join-Path $TestDrive ('log_battery_{0}.txt' -f [guid]::NewGuid())
        Mock -CommandName 'Invoke-WcdPowerCfg' { }
    }

    Context 'analyse du rapport' {
        It 'lit les deux capacites sans toucher aux libelles' {
            $report = ConvertFrom-WcdBatteryReport -Html (New-TestBatteryHtml)

            $report.Parsed | Should -BeTrue
            $report.HasBattery | Should -BeTrue
            $report.DesignCapacity | Should -Be 52000
            $report.FullChargeCapacity | Should -Be 48900
        }

        It 'lit un rapport francais aussi bien qu un anglais' {
            $report = ConvertFrom-WcdBatteryReport -Html (New-TestBatteryHtml -Design '52 000' -FullCharge '48 900' -French)

            $report.DesignCapacity | Should -Be 52000
            $report.FullChargeCapacity | Should -Be 48900
        }

        It 'distingue un rapport illisible d un rapport sans pile' {
            (ConvertFrom-WcdBatteryReport -Html 'powercfg: invalid parameters').Parsed | Should -BeFalse

            $noBattery = ConvertFrom-WcdBatteryReport -Html (New-TestBatteryHtml -NoBattery)
            $noBattery.Parsed | Should -BeTrue
            $noBattery.HasBattery | Should -BeFalse
        }
    }

    Context 'etat rapporte' {
        It 'rapporte OK sur une pile saine' {
            Mock -CommandName 'Get-WcdBatteryReportHtml' { New-TestBatteryHtml -Design '52,000' -FullCharge '48,900' }

            $result = Set-WcdPowerConfiguration -FormFactor 'Laptop' -LogPath $script:LogPath | Where-Object Step -eq 'BatteryHealth'

            $result.Severity | Should -Be 'INFO'
            $result.Error | Should -Match '94%'
        }

        It 'avertit en citant le ratio sur une pile usee' {
            Mock -CommandName 'Get-WcdBatteryReportHtml' { New-TestBatteryHtml -Design '52,000' -FullCharge '31,200' }

            $result = Set-WcdPowerConfiguration -FormFactor 'Laptop' -LogPath $script:LogPath | Where-Object Step -eq 'BatteryHealth'

            $result.Severity | Should -Be 'WARNING'
            $result.RemedyKey | Should -Be 'BatteryWorn'
            $result.Error | Should -Match '60%'
        }

        It 'rapporte Non applicable quand le rapport ne liste aucune pile' {
            # Le technicien choisit le Form Factor, il n est pas detecte:
            # quelqu un choisira Laptop sur un poste fixe compact.
            Mock -CommandName 'Get-WcdBatteryReportHtml' { New-TestBatteryHtml -NoBattery }

            $result = Set-WcdPowerConfiguration -FormFactor 'Laptop' -LogPath $script:LogPath | Where-Object Step -eq 'BatteryHealth'

            $result.Severity | Should -Be 'NA'
            $result.Success | Should -BeTrue
        }

        It 'rapporte un poste sans historique en INFO, pas en avertissement' {
            Mock -CommandName 'Get-WcdBatteryReportHtml' { New-TestBatteryHtml -Design '0' -FullCharge '0' }

            $result = Set-WcdPowerConfiguration -FormFactor 'Laptop' -LogPath $script:LogPath | Where-Object Step -eq 'BatteryHealth'

            $result.Severity | Should -Be 'INFO'
            $result.Error | Should -Match 'charge cycles'
        }

        It 'ne confond pas un rapport illisible avec une pile usee' {
            Mock -CommandName 'Get-WcdBatteryReportHtml' { 'powercfg: the parameter is incorrect.' }

            $result = Set-WcdPowerConfiguration -FormFactor 'Laptop' -LogPath $script:LogPath | Where-Object Step -eq 'BatteryHealth'

            $result.Severity | Should -Be 'WARNING'
            $result.RemedyKey | Should -Be 'BatteryReportUnreadable'
            $result.RemedyKey | Should -Not -Be 'BatteryWorn'
        }

        It 'rapporte proprement quand powercfg refuse de produire le rapport' {
            Mock -CommandName 'Get-WcdBatteryReportHtml' { throw 'powercfg exited with code 1.' }

            $result = Set-WcdPowerConfiguration -FormFactor 'Laptop' -LogPath $script:LogPath | Where-Object Step -eq 'BatteryHealth'

            $result.Severity | Should -Be 'WARNING'
            $result.Success | Should -BeTrue
            $result.RemedyKey | Should -Be 'BatteryReportUnreadable'
        }

        It 'ne produit aucune etape de pile sur un poste fixe' {
            Mock -CommandName 'Get-WcdBatteryReportHtml' { New-TestBatteryHtml }

            $results = @(Set-WcdPowerConfiguration -FormFactor 'Desktop' -LogPath $script:LogPath)

            ($results | Where-Object Step -eq 'BatteryHealth') | Should -BeNullOrEmpty
            Should -Invoke 'Get-WcdBatteryReportHtml' -Times 0
        }

        It 'rapporte le besoin d elevation sans produire de rapport' {
            Mock -CommandName 'Get-WcdBatteryReportHtml' { New-TestBatteryHtml }

            $result = Set-WcdPowerConfiguration -FormFactor 'Laptop' -Elevated $false -LogPath $script:LogPath |
                Where-Object Step -eq 'BatteryHealth'

            $result.Severity | Should -Be 'WARNING'
            $result.RemedyKey | Should -Be 'RequiresAdmin'
            Should -Invoke 'Get-WcdBatteryReportHtml' -Times 0
        }
    }

    Context 'le fichier temporaire' {
        It 'ecrit le rapport dans un chemin temporaire et le supprime' {
            # Le technicien a une liste a lire, pas un second rapport a trouver
            # a cote du journal.
            $script:WrittenPath = $null
            Mock -CommandName 'Invoke-WcdPowerCfg' {
                $script:WrittenPath = $Arguments[2]
                Set-Content -LiteralPath $script:WrittenPath -Value (New-TestBatteryHtml) -Encoding UTF8
            }

            $html = Get-WcdBatteryReportHtml

            $html | Should -Match 'mWh'
            $script:WrittenPath | Should -Not -BeNullOrEmpty
            Test-Path -LiteralPath $script:WrittenPath | Should -BeFalse
        }

        It 'supprime le fichier temporaire meme quand la lecture echoue' {
            $script:WrittenPath = $null
            Mock -CommandName 'Invoke-WcdPowerCfg' { $script:WrittenPath = $Arguments[2] }

            { Get-WcdBatteryReportHtml } | Should -Throw

            Test-Path -LiteralPath $script:WrittenPath | Should -BeFalse
        }
    }
}
