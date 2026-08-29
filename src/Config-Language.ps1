# Config-Language.ps1 - applies the display language and keyboard layout.
# Entry point: Set-WcdLanguageConfiguration. Requires WcdHelpers.ps1.

function Get-WcdLanguageProfile {
    <#
    .SYNOPSIS
        Returns everything that differs between the supported cultures.

    .DESCRIPTION
        One table instead of conditionals scattered through the Module: the
        culture, its fallbacks, the geographic id, the keyboard input tip, and the
        labels used in the log.

    .PARAMETER Culture
        'fr-CA' or 'en-US'.

    .OUTPUTS
        [pscustomobject] with Culture, FallbackCultures, GeoId, KeyboardTip,
        LanguageLabel and KeyboardLabel.

    .EXAMPLE
        (Get-WcdLanguageProfile -Culture 'fr-CA').KeyboardTip   # 0C0C:00001009
    #>
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
    <#
    .SYNOPSIS
        Builds the Windows user language list for a culture and its fallbacks.

    .DESCRIPTION
        fr-CA falls back to fr-FR so applications shipping only European French
        still show a French interface rather than reverting to English.

    .PARAMETER Culture
        Primary culture, first in the resulting list.

    .PARAMETER FallbackCultures
        Cultures appended after the primary one. The primary culture and empty
        entries are ignored.

    .OUTPUTS
        The Windows user language list object. Throws when the language cmdlets are
        unavailable in this session.

    .EXAMPLE
        New-WcdLanguageList -Culture 'fr-CA' -FallbackCultures @('fr-FR')
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Culture,

        [string[]]$FallbackCultures = @()
    )

    $command = Get-Command -Name 'New-WinUserLanguageList' -ErrorAction SilentlyContinue
    if (-not $command) {
        throw 'New-WinUserLanguageList is unavailable in this session.'
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
    <#
    .SYNOPSIS
        Applies a Windows user language list.

    .PARAMETER LanguageList
        The list built by New-WcdLanguageList.

    .OUTPUTS
        None. Throws when the language cmdlets are unavailable in this session.

    .EXAMPLE
        Set-WcdLanguageList -LanguageList (New-WcdLanguageList -Culture 'en-US')
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $LanguageList
    )

    $command = Get-Command -Name 'Set-WinUserLanguageList' -ErrorAction SilentlyContinue
    if (-not $command) {
        throw 'Set-WinUserLanguageList is unavailable in this session.'
    }

    Set-WinUserLanguageList -LanguageList $LanguageList -Force -ErrorAction Stop -WarningAction SilentlyContinue
}

function Set-WcdKeyboardOverride {
    <#
    .SYNOPSIS
        Sets the default keyboard input method.

    .DESCRIPTION
        Separate from the language list on purpose: a fr-CA display language with a
        US keyboard is a common and confusing post-image state, so the layout is
        pinned explicitly.

    .PARAMETER InputTip
        Input method tip, e.g. '0C0C:00001009' for Canadian French.

    .OUTPUTS
        None. Throws when the language cmdlets are unavailable in this session.

    .EXAMPLE
        Set-WcdKeyboardOverride -InputTip '0409:00000409'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InputTip
    )

    $command = Get-Command -Name 'Set-WinDefaultInputMethodOverride' -ErrorAction SilentlyContinue
    if (-not $command) {
        throw 'Set-WinDefaultInputMethodOverride is unavailable in this session.'
    }

    Set-WinDefaultInputMethodOverride -InputTip $InputTip -ErrorAction Stop -WarningAction SilentlyContinue
}

function Set-WcdLocaleOverrides {
    <#
    .SYNOPSIS
        Applies the UI language, user culture, system locale and home region.

    .DESCRIPTION
        Each cmdlet is optional: an older Windows or a locked-down session simply
        logs a warning and the rest still applies. Set-WinSystemLocale and
        Set-WinHomeLocation need Administrator, so an unelevated run logs them as
        not applied instead of failing the Step.

    .PARAMETER Culture
        Culture to apply, e.g. 'fr-CA'.

    .PARAMETER GeoId
        Windows geographic id for the home region, e.g. 39 for Canada.

    .PARAMETER LogPath
        Full path to the log file.

    .OUTPUTS
        None.

    .EXAMPLE
        Set-WcdLocaleOverrides -Culture 'fr-CA' -GeoId 39 -LogPath 'C:\temp\log.txt'
    #>
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
            Write-WcdLog -Path $LogPath -Level 'WARNING' -Message ('Set-WinSystemLocale not applied ({0}). Relaunch elevated if it is needed.' -f $_.Exception.Message)
        }
    } else {
        Write-WcdLog -Path $LogPath -Level 'WARNING' -Message 'Set-WinSystemLocale unavailable: system locale not applied.'
    }

    $setHomeLocationCommand = Get-Command -Name 'Set-WinHomeLocation' -ErrorAction SilentlyContinue
    if ($setHomeLocationCommand) {
        try {
            Set-WinHomeLocation -GeoId $GeoId -ErrorAction Stop
        } catch {
            Write-WcdLog -Path $LogPath -Level 'WARNING' -Message ('Set-WinHomeLocation not applied ({0}).' -f $_.Exception.Message)
        }
    } else {
        Write-WcdLog -Path $LogPath -Level 'WARNING' -Message 'Set-WinHomeLocation unavailable: region not applied.'
    }
}

function Set-WcdLanguageConfiguration {
    <#
    .SYNOPSIS
        Applies the Windows display language and the default keyboard layout.

    .DESCRIPTION
        Applies the language list, the input method and the locale overrides for
        the chosen culture. Everything here writes per-user state, so the Module
        runs unelevated; only the system locale and home region need Administrator
        and are logged as not applied when it is missing.

        Some UWP applications only pick the new language up after a sign-out.

    .PARAMETER Culture
        Target culture: 'fr-CA' or 'en-US'. Defaults to 'fr-CA'.

    .PARAMETER LogPath
        Full path to the log file. Resolved automatically when omitted.

    .PARAMETER ProgressCallback
        Scriptblock invoked at the start and end of each step for progress display.

    .OUTPUTS
        [pscustomobject[]] with Step, Success and Error, for DisplayLanguage and
        KeyboardLayout.

    .EXAMPLE
        Set-WcdLanguageConfiguration -Culture 'en-US' -LogPath 'C:\temp\log.txt'
    #>
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