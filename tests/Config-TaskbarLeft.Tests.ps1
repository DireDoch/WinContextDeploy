Describe 'Config-TaskbarLeft' {
    BeforeAll {
        $srcDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'src'
        $helpersPath = Join-Path $srcDir 'WcdHelpers.ps1'
        $modulePath  = Join-Path $srcDir 'Config-TaskbarLeft.ps1'

        if (-not (Test-Path -LiteralPath $helpersPath)) { throw 'WcdHelpers.ps1 introuvable.' }
        if (-not (Test-Path -LiteralPath $modulePath))  { throw 'Config-TaskbarLeft.ps1 introuvable.' }

        . $helpersPath
        . $modulePath

        $script:PesterMajorVersion = (Get-Module -Name Pester | Select-Object -First 1).Version.Major
    }

    It 'configure la barre des taches complete avec succes' {
        $logPath = Join-Path $TestDrive 'log_taskbar.txt'

        Mock -CommandName 'Set-WcdRegistryValue' {}

        $results = Set-WcdTaskbarLeft -LogPath $logPath

        if ($script:PesterMajorVersion -ge 5) {
            $results.Count | Should -Be 2
            ($results | Where-Object Step -eq 'TaskbarAlignementGauche').Success | Should -BeTrue
            ($results | Where-Object Step -eq 'DesactiverVueTaches').Success | Should -BeTrue
            Get-Content -Path $logPath -Raw | Should -Match 'alignement a gauche'
            Get-Content -Path $logPath -Raw | Should -Match 'vue des taches desactivee'
            Assert-MockCalled -CommandName 'Set-WcdRegistryValue' -Times 2
        } else {
            $results.Count | Should Be 2
            ($results | Where-Object Step -eq 'TaskbarAlignementGauche').Success | Should Be $true
            ($results | Where-Object Step -eq 'DesactiverVueTaches').Success | Should Be $true
            Get-Content -Path $logPath -Raw | Should Match 'alignement a gauche'
            Get-Content -Path $logPath -Raw | Should Match 'vue des taches desactivee'
            Assert-MockCalled 'Set-WcdRegistryValue' 2
        }
    }

    It 'retourne echec si registre bloque par GPO' {
        $logPath = Join-Path $TestDrive 'log_taskbar_gpo.txt'

        Mock -CommandName 'Set-WcdRegistryValue' { throw [System.UnauthorizedAccessException]::new('Operation non autorisee') }

        $results = Set-WcdTaskbarLeft -LogPath $logPath

        if ($script:PesterMajorVersion -ge 5) {
            $results.Count | Should -Be 2
            ($results | Where-Object { -not $_.Success }).Count | Should -Be 2
            ($results | Where-Object Step -eq 'TaskbarAlignementGauche').Error | Should -Match 'GPO|acces refuse'
            ($results | Where-Object Step -eq 'DesactiverVueTaches').Error | Should -Match 'GPO|acces refuse'
            Get-Content -Path $logPath -Raw | Should -Match 'Barre des taches'
        } else {
            $results.Count | Should Be 2
            ($results | Where-Object { -not $_.Success }).Count | Should Be 2
            ($results | Where-Object Step -eq 'TaskbarAlignementGauche').Error | Should Match 'GPO|acces refuse'
            ($results | Where-Object Step -eq 'DesactiverVueTaches').Error | Should Match 'GPO|acces refuse'
            Get-Content -Path $logPath -Raw | Should Match 'Barre des taches'
        }
    }
}
