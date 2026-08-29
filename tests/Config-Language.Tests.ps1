Describe 'Config-Language' {
    BeforeAll {
        $srcDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'src'
        $helpersPath = Join-Path $srcDir 'WcdHelpers.ps1'
        $modulePath  = Join-Path $srcDir 'Config-Language.ps1'

        if (-not (Test-Path -LiteralPath $helpersPath)) { throw 'WcdHelpers.ps1 introuvable.' }
        if (-not (Test-Path -LiteralPath $modulePath))  { throw 'Config-Language.ps1 introuvable.' }

        . $helpersPath
        . $modulePath

        $script:PesterMajorVersion = (Get-Module -Name Pester | Select-Object -First 1).Version.Major
    }

    It 'configure la langue et le clavier francais avec succes' {
        $logPath = Join-Path $TestDrive 'log_language_fr.txt'
        $inputTips = New-Object 'System.Collections.Generic.List[string]'
        [void]$inputTips.Add('0C0C:00001009')

        Mock -CommandName 'New-WcdLanguageList' {
            @([pscustomobject]@{ InputMethodTips = $inputTips })
        }
        Mock -CommandName 'Set-WcdLanguageList' {}
        Mock -CommandName 'Set-WcdLocaleOverrides' {}
        Mock -CommandName 'Set-WcdKeyboardOverride' {}

        $results = @(Set-WcdLanguageConfiguration -Culture 'fr-CA' -LogPath $logPath)

        if ($script:PesterMajorVersion -ge 5) {
            $results.Count | Should -Be 2
            ($results | Where-Object Step -eq 'LangueWindows').Success | Should -BeTrue
            ($results | Where-Object Step -eq 'ClavierWindows').Success | Should -BeTrue
            Assert-MockCalled -CommandName 'Set-WcdLocaleOverrides' -Times 1 -Exactly -ParameterFilter { $Culture -eq 'fr-CA' -and $GeoId -eq 39 }
            Get-Content -Path $logPath -Raw | Should -Match 'Langue: fr-CA appliquee'
            Get-Content -Path $logPath -Raw | Should -Match 'deconnexion/reconnexion'
            Get-Content -Path $logPath -Raw | Should -Match 'Clavier: Canadien francais \(QWERTY\) applique'
        } else {
            $results.Count | Should Be 2
            ($results | Where-Object Step -eq 'LangueWindows').Success | Should Be $true
            ($results | Where-Object Step -eq 'ClavierWindows').Success | Should Be $true
            Assert-MockCalled 'Set-WcdLocaleOverrides' -Times 1 -Exactly -ParameterFilter { $Culture -eq 'fr-CA' -and $GeoId -eq 39 }
            Get-Content -Path $logPath -Raw | Should Match 'Langue: fr-CA appliquee'
            Get-Content -Path $logPath -Raw | Should Match 'deconnexion/reconnexion'
            Get-Content -Path $logPath -Raw | Should Match 'Clavier: Canadien francais \(QWERTY\) applique'
        }
    }

    It 'configure la langue et le clavier anglais avec succes' {
        $logPath = Join-Path $TestDrive 'log_language_en.txt'
        $inputTips = New-Object 'System.Collections.Generic.List[string]'
        [void]$inputTips.Add('0409:00000409')

        Mock -CommandName 'New-WcdLanguageList' {
            @([pscustomobject]@{ InputMethodTips = $inputTips })
        }
        Mock -CommandName 'Set-WcdLanguageList' {}
        Mock -CommandName 'Set-WcdLocaleOverrides' {}
        Mock -CommandName 'Set-WcdKeyboardOverride' {}

        $results = @(Set-WcdLanguageConfiguration -Culture 'en-US' -LogPath $logPath)

        if ($script:PesterMajorVersion -ge 5) {
            $results.Count | Should -Be 2
            ($results | Where-Object Step -eq 'LangueWindows').Success | Should -BeTrue
            ($results | Where-Object Step -eq 'ClavierWindows').Success | Should -BeTrue
            Assert-MockCalled -CommandName 'Set-WcdLocaleOverrides' -Times 1 -Exactly -ParameterFilter { $Culture -eq 'en-US' -and $GeoId -eq 244 }
            Get-Content -Path $logPath -Raw | Should -Match 'Langue: en-US appliquee'
            Get-Content -Path $logPath -Raw | Should -Match 'Clavier: Anglais \(Etats-Unis\) applique'
        } else {
            $results.Count | Should Be 2
            ($results | Where-Object Step -eq 'LangueWindows').Success | Should Be $true
            ($results | Where-Object Step -eq 'ClavierWindows').Success | Should Be $true
            Assert-MockCalled 'Set-WcdLocaleOverrides' -Times 1 -Exactly -ParameterFilter { $Culture -eq 'en-US' -and $GeoId -eq 244 }
            Get-Content -Path $logPath -Raw | Should Match 'Langue: en-US appliquee'
            Get-Content -Path $logPath -Raw | Should Match 'Clavier: Anglais \(Etats-Unis\) applique'
        }
    }

    It 'continue avec le clavier meme si la langue echoue' {
        $logPath = Join-Path $TestDrive 'log_language_partial.txt'

        Mock -CommandName 'New-WcdLanguageList' { throw 'Commande langue indisponible' }
        Mock -CommandName 'Set-WcdKeyboardOverride' {}

        $results = @(Set-WcdLanguageConfiguration -Culture 'fr-CA' -LogPath $logPath)

        if ($script:PesterMajorVersion -ge 5) {
            $results.Count | Should -Be 2
            ($results | Where-Object Step -eq 'LangueWindows').Success | Should -BeFalse
            ($results | Where-Object Step -eq 'ClavierWindows').Success | Should -BeTrue
        } else {
            $results.Count | Should Be 2
            ($results | Where-Object Step -eq 'LangueWindows').Success | Should Be $false
            ($results | Where-Object Step -eq 'ClavierWindows').Success | Should Be $true
        }
    }

    It 'retourne un profil fr-CA avec fallback et region' {
        $profile = Get-WcdLanguageProfile -Culture 'fr-CA'

        if ($script:PesterMajorVersion -ge 5) {
            $profile.Culture | Should -Be 'fr-CA'
            @($profile.FallbackCultures).Count | Should -Be 1
            @($profile.FallbackCultures)[0] | Should -Be 'fr-FR'
            $profile.GeoId | Should -Be 39
        } else {
            $profile.Culture | Should Be 'fr-CA'
            @($profile.FallbackCultures).Count | Should Be 1
            @($profile.FallbackCultures)[0] | Should Be 'fr-FR'
            $profile.GeoId | Should Be 39
        }
    }

    It 'ajoute la langue fallback dans la liste utilisateur' {
        Mock -CommandName 'New-WinUserLanguageList' {
            $tips = New-Object 'System.Collections.Generic.List[string]'
            [void]$tips.Add('0409:00000409')
            $list = New-Object 'System.Collections.Generic.List[object]'
            [void]$list.Add([pscustomobject]@{ LanguageTag = $Language; InputMethodTips = $tips })
            # Operateur virgule: empeche le deroulement (unrolling) du pipeline pour
            # que l'appelant recoive la List intacte, comme le vrai New-WinUserLanguageList.
            return ,$list
        }

        $languageList = New-WcdLanguageList -Culture 'fr-CA' -FallbackCultures @('fr-FR')

        if ($script:PesterMajorVersion -ge 5) {
            @($languageList).Count | Should -Be 2
            @($languageList)[0].LanguageTag | Should -Be 'fr-CA'
            @($languageList)[1].LanguageTag | Should -Be 'fr-FR'
            Assert-MockCalled -CommandName 'New-WinUserLanguageList' -Times 2 -Exactly
        } else {
            @($languageList).Count | Should Be 2
            @($languageList)[0].LanguageTag | Should Be 'fr-CA'
            @($languageList)[1].LanguageTag | Should Be 'fr-FR'
            Assert-MockCalled 'New-WinUserLanguageList' -Times 2 -Exactly
        }
    }
}