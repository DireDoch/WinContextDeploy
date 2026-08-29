<#
.SYNOPSIS
    Configure la langue d'affichage Windows et le clavier par defaut
    selon la culture cible (fr-CA ou en-US).

.DESCRIPTION
    Applique la liste de langues Windows, remplace la methode de saisie par defaut,
    et configure la culture, la region et les parametres regionaux systeme.
    Certaines commandes (Set-WinSystemLocale, Set-WinHomeLocation) peuvent
    necessiter des privileges administrateur.
    Requiert MinimalHelpers.ps1 charge au prealable via dot-source.

.PARAMETER Culture
    Code de culture cible. Valeurs acceptees: 'fr-CA', 'en-US'.
    Defaut: 'fr-CA'.

.PARAMETER LogPath
    Chemin complet vers le fichier journal (.txt). Si omis, resolu automatiquement
    par Resolve-MinimalLogPath.

.PARAMETER ProgressCallback
    Scriptblock appele a chaque debut/fin d'etape pour afficher la progression.

.OUTPUTS
    [pscustomobject[]] — tableau de resultats avec Step, Success, Error.
#>

function Get-MinimalLanguageProfile {
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
                KeyboardLabel   = 'Canadien francais (QWERTY)'
            }
        }
        'en-US' {
            return [pscustomobject]@{
                Culture         = 'en-US'
                FallbackCultures = @()
                GeoId           = 244
                KeyboardTip     = '0409:00000409'
                LanguageLabel   = 'en-US'
                KeyboardLabel   = 'Anglais (Etats-Unis)'
            }
        }
    }
}

function New-MinimalLanguageList {
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

function Set-MinimalLanguageList {
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

function Set-MinimalKeyboardOverride {
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

function Set-MinimalLocaleOverrides {
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
        Write-MinimalLog -Path $LogPath -Level 'WARNING' -Message 'Set-WinUILanguageOverride indisponible: override UI non applique.'
    }

    $setCultureCommand = Get-Command -Name 'Set-Culture' -ErrorAction SilentlyContinue
    if ($setCultureCommand) {
        Set-Culture -CultureInfo $Culture -ErrorAction Stop
    } else {
        Write-MinimalLog -Path $LogPath -Level 'WARNING' -Message 'Set-Culture indisponible: culture utilisateur non appliquee.'
    }

    $setSystemLocaleCommand = Get-Command -Name 'Set-WinSystemLocale' -ErrorAction SilentlyContinue
    if ($setSystemLocaleCommand) {
        try {
            Set-WinSystemLocale -SystemLocale $Culture -ErrorAction Stop -WarningAction SilentlyContinue
        } catch {
            Write-MinimalLog -Path $LogPath -Level 'WARNING' -Message ('Set-WinSystemLocale non applique ({0}). Executer en administrateur si necessaire.' -f $_.Exception.Message)
        }
    } else {
        Write-MinimalLog -Path $LogPath -Level 'WARNING' -Message 'Set-WinSystemLocale indisponible: locale systeme non appliquee.'
    }

    $setHomeLocationCommand = Get-Command -Name 'Set-WinHomeLocation' -ErrorAction SilentlyContinue
    if ($setHomeLocationCommand) {
        try {
            Set-WinHomeLocation -GeoId $GeoId -ErrorAction Stop
        } catch {
            Write-MinimalLog -Path $LogPath -Level 'WARNING' -Message ('Set-WinHomeLocation non applique ({0}).' -f $_.Exception.Message)
        }
    } else {
        Write-MinimalLog -Path $LogPath -Level 'WARNING' -Message 'Set-WinHomeLocation indisponible: region non appliquee.'
    }
}

function Set-MinimalLanguageConfiguration {
    [CmdletBinding()]
    param(
        [ValidateSet('fr-CA', 'en-US')]
        [string]$Culture = 'fr-CA',
        [string]$LogPath,
        [scriptblock]$ProgressCallback
    )

    $resolvedLogPath = Resolve-MinimalLogPath -CandidatePath $LogPath
    $profile = Get-MinimalLanguageProfile -Culture $Culture
    $results = @()
    $moduleName = 'Config-Language'

    try {
        Invoke-MinimalProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'LangueWindows' -Event 'Start'
        $languageList = New-MinimalLanguageList -Culture $profile.Culture -FallbackCultures $profile.FallbackCultures
        if ($languageList.Count -gt 0 -and $null -ne $languageList[0].PSObject.Properties['InputMethodTips']) {
            $languageList[0].InputMethodTips.Clear()
            [void]$languageList[0].InputMethodTips.Add($profile.KeyboardTip)
        }

        Set-MinimalLanguageList -LanguageList $languageList
        Set-MinimalLocaleOverrides -Culture $profile.Culture -GeoId $profile.GeoId -LogPath $resolvedLogPath
        Write-MinimalLog -Path $resolvedLogPath -Level 'INFO' -Message ('Langue: {0} appliquee.' -f $profile.LanguageLabel)
        Write-MinimalLog -Path $resolvedLogPath -Level 'INFO' -Message 'Certaines applications UWP peuvent necessiter une deconnexion/reconnexion pour afficher la nouvelle langue.'
        Invoke-MinimalProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'LangueWindows' -Event 'Finish' -Kind 'success'
        $results += [pscustomobject]@{ Step = 'LangueWindows'; Success = $true; Error = '' }
    } catch {
        Write-MinimalLog -Path $resolvedLogPath -Level 'ERROR' -Message ('Langue Windows: {0}' -f $_.Exception.Message)
        Invoke-MinimalProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'LangueWindows' -Event 'Finish' -Kind 'error'
        $results += [pscustomobject]@{ Step = 'LangueWindows'; Success = $false; Error = $_.Exception.Message }
    }

    try {
        Invoke-MinimalProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'ClavierWindows' -Event 'Start'
        Set-MinimalKeyboardOverride -InputTip $profile.KeyboardTip
        Write-MinimalLog -Path $resolvedLogPath -Level 'INFO' -Message ('Clavier: {0} applique.' -f $profile.KeyboardLabel)
        Invoke-MinimalProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'ClavierWindows' -Event 'Finish' -Kind 'success'
        $results += [pscustomobject]@{ Step = 'ClavierWindows'; Success = $true; Error = '' }
    } catch {
        Write-MinimalLog -Path $resolvedLogPath -Level 'ERROR' -Message ('Clavier Windows: {0}' -f $_.Exception.Message)
        Invoke-MinimalProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'ClavierWindows' -Event 'Finish' -Kind 'error'
        $results += [pscustomobject]@{ Step = 'ClavierWindows'; Success = $false; Error = $_.Exception.Message }
    }

    return $results
}