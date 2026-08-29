<#
.SYNOPSIS
    Configure la langue d'affichage Windows et le clavier par defaut
    selon la culture cible (fr-CA ou en-US).

.DESCRIPTION
    Applique la liste de langues Windows, remplace la methode de saisie par defaut,
    et configure la culture, la region et les parametres regionaux systeme.
    Certaines commandes (Set-WinSystemLocale, Set-WinHomeLocation) peuvent
    necessiter des privileges administrateur.
    Requiert WcdHelpers.ps1 charge au prealable via dot-source.

.PARAMETER Culture
    Code de culture cible. Valeurs acceptees: 'fr-CA', 'en-US'.
    Defaut: 'fr-CA'.

.PARAMETER LogPath
    Chemin complet vers le fichier journal (.txt). Si omis, resolu automatiquement
    par Resolve-WcdLogPath.

.PARAMETER ProgressCallback
    Scriptblock appele a chaque debut/fin d'etape pour afficher la progression.

.OUTPUTS
    [pscustomobject[]] — tableau de resultats avec Step, Success, Error.
#>

function Get-WcdLanguageProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('fr-CA', 'en-US')]
        [string]$Culture
    )

    switch ($Culture) {
        'fr-CA' {
            return [pscustomobject]@{
                Culture         = 'fr-CA'
                FallbackCultures = @('fr-FR')
                GeoId           = 39
                KeyboardTip     = '0C0C:00001009'
                LanguageLabel   = 'fr-CA'
                KeyboardLabel   = 'Canadian French (QWERTY)'
            }
        }
        'en-US' {
            return [pscustomobject]@{
                Culture         = 'en-US'
                FallbackCultures = @()
                GeoId           = 244
                KeyboardTip     = '0409:00000409'
                LanguageLabel   = 'en-US'
                KeyboardLabel   = 'English (United States)'
            }
        }
    }
}

function New-WcdLanguageList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Culture,

        [string[]]$FallbackCultures = @()
    )

    $command = Get-Command -Name 'New-WinUserLanguageList' -ErrorAction SilentlyContinue
    if (-not $command) {
        throw 'Commande New-WinUserLanguageList indisponible sur cette session.'
    }

    $languageList = New-WinUserLanguageList -Language $Culture -ErrorAction Stop

    foreach ($fallbackCulture in @($FallbackCultures)) {
        if ([string]::IsNullOrWhiteSpace($fallbackCulture)) {
            continue
        }
        if ($fallbackCulture -eq $Culture) {
            continue
        }

        $fallbackList = New-WinUserLanguageList -Language $fallbackCulture -ErrorAction Stop
        if ($fallbackList.Count -gt 0) {
            [void]$languageList.Add($fallbackList[0])
        }
    }

    return $languageList
}

function Set-WcdLanguageList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $LanguageList
    )

    $command = Get-Command -Name 'Set-WinUserLanguageList' -ErrorAction SilentlyContinue
    if (-not $command) {
        throw 'Commande Set-WinUserLanguageList indisponible sur cette session.'
    }

    Set-WinUserLanguageList -LanguageList $LanguageList -Force -ErrorAction Stop -WarningAction SilentlyContinue
}

function Set-WcdKeyboardOverride {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InputTip
    )

    $command = Get-Command -Name 'Set-WinDefaultInputMethodOverride' -ErrorAction SilentlyContinue
    if (-not $command) {
        throw 'Commande Set-WinDefaultInputMethodOverride indisponible sur cette session.'
    }

    Set-WinDefaultInputMethodOverride -InputTip $InputTip -ErrorAction Stop -WarningAction SilentlyContinue
}

function Set-WcdLocaleOverrides {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Culture,

        [Parameter(Mandatory)]
        [int]$GeoId,

        [Parameter(Mandatory)]
        [string]$LogPath
    )

    $setUiLanguageCommand = Get-Command -Name 'Set-WinUILanguageOverride' -ErrorAction SilentlyContinue
    if ($setUiLanguageCommand) {
        Set-WinUILanguageOverride -Language $Culture -ErrorAction Stop -WarningAction SilentlyContinue
    } else {
        Write-WcdLog -Path $LogPath -Level 'WARNING' -Message 'Set-WinUILanguageOverride unavailable: UI override not applied.'
    }

    $setCultureCommand = Get-Command -Name 'Set-Culture' -ErrorAction SilentlyContinue
    if ($setCultureCommand) {
        Set-Culture -CultureInfo $Culture -ErrorAction Stop
    } else {
        Write-WcdLog -Path $LogPath -Level 'WARNING' -Message 'Set-Culture unavailable: user culture not applied.'
    }

    $setSystemLocaleCommand = Get-Command -Name 'Set-WinSystemLocale' -ErrorAction SilentlyContinue
    if ($setSystemLocaleCommand) {
        try {
            Set-WinSystemLocale -SystemLocale $Culture -ErrorAction Stop -WarningAction SilentlyContinue
        } catch {
            Write-WcdLog -Path $LogPath -Level 'WARNING' -Message ('Set-WinSystemLocale non applique ({0}). Executer en administrateur si necessaire.' -f $_.Exception.Message)
        }
    } else {
        Write-WcdLog -Path $LogPath -Level 'WARNING' -Message 'Set-WinSystemLocale unavailable: system locale not applied.'
    }

    $setHomeLocationCommand = Get-Command -Name 'Set-WinHomeLocation' -ErrorAction SilentlyContinue
    if ($setHomeLocationCommand) {
        try {
            Set-WinHomeLocation -GeoId $GeoId -ErrorAction Stop
        } catch {
            Write-WcdLog -Path $LogPath -Level 'WARNING' -Message ('Set-WinHomeLocation non applique ({0}).' -f $_.Exception.Message)
        }
    } else {
        Write-WcdLog -Path $LogPath -Level 'WARNING' -Message 'Set-WinHomeLocation unavailable: region not applied.'
    }
}

function Set-WcdLanguageConfiguration {
    [CmdletBinding()]
    param(
        [ValidateSet('fr-CA', 'en-US')]
        [string]$Culture = 'fr-CA',
        [string]$LogPath,
        [scriptblock]$ProgressCallback
    )

    $resolvedLogPath = Resolve-WcdLogPath -CandidatePath $LogPath
    $profile = Get-WcdLanguageProfile -Culture $Culture
    $results = @()
    $moduleName = 'Config-Language'

    try {
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'DisplayLanguage' -Event 'Start'
        $languageList = New-WcdLanguageList -Culture $profile.Culture -FallbackCultures $profile.FallbackCultures
        if ($languageList.Count -gt 0 -and $null -ne $languageList[0].PSObject.Properties['InputMethodTips']) {
            $languageList[0].InputMethodTips.Clear()
            [void]$languageList[0].InputMethodTips.Add($profile.KeyboardTip)
        }

        Set-WcdLanguageList -LanguageList $languageList
        Set-WcdLocaleOverrides -Culture $profile.Culture -GeoId $profile.GeoId -LogPath $resolvedLogPath
        Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('Display language: {0} applied.' -f $profile.LanguageLabel)
        Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'Some UWP apps may need a sign-out and sign-in before the new language shows.'
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'DisplayLanguage' -Event 'Finish' -Kind 'success'
        $results += [pscustomobject]@{ Step = 'DisplayLanguage'; Success = $true; Error = '' }
    } catch {
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ('Display language: {0}' -f $_.Exception.Message)
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'DisplayLanguage' -Event 'Finish' -Kind 'error'
        $results += [pscustomobject]@{ Step = 'DisplayLanguage'; Success = $false; Error = $_.Exception.Message }
    }

    try {
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'KeyboardLayout' -Event 'Start'
        Set-WcdKeyboardOverride -InputTip $profile.KeyboardTip
        Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('Keyboard: {0} applied.' -f $profile.KeyboardLabel)
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'KeyboardLayout' -Event 'Finish' -Kind 'success'
        $results += [pscustomobject]@{ Step = 'KeyboardLayout'; Success = $true; Error = '' }
    } catch {
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ('Keyboard: {0}' -f $_.Exception.Message)
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'KeyboardLayout' -Event 'Finish' -Kind 'error'
        $results += [pscustomobject]@{ Step = 'KeyboardLayout'; Success = $false; Error = $_.Exception.Message }
    }

    return $results
}