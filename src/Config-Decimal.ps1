<#
.SYNOPSIS
    Force les separateurs decimaux et monetaires a '.' dans les parametres
    regionaux Windows et dans la culture du thread PowerShell courant.

.DESCRIPTION
    Modifie les cles de registre HKCU:\Control Panel\International pour
    appliquer le point comme separateur decimal et la virgule comme separateur
    de milliers, aussi bien pour les nombres que pour les montants.
    Requiert WcdHelpers.ps1 charge au prealable via dot-source.

.PARAMETER LogPath
    Chemin complet vers le fichier journal (.txt). Si omis, resolu automatiquement
    par Resolve-WcdLogPath.

.PARAMETER ProgressCallback
    Scriptblock appele a chaque debut/fin d'etape pour afficher la progression.

.OUTPUTS
    [pscustomobject] — resultat unique avec Step, Success, LogPath, Error.
#>

function Set-WcdDecimalThreadCulture {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DecimalSeparator,

        [Parameter(Mandatory)]
        [string]$ThousandsSeparator
    )

    $culture = [System.Globalization.CultureInfo]::CurrentCulture.Clone()
    $culture.NumberFormat.NumberDecimalSeparator = $DecimalSeparator
    $culture.NumberFormat.CurrencyDecimalSeparator = $DecimalSeparator
    $culture.NumberFormat.NumberGroupSeparator = $ThousandsSeparator
    $culture.NumberFormat.CurrencyGroupSeparator = $ThousandsSeparator

    [System.Threading.Thread]::CurrentThread.CurrentCulture = $culture
    [System.Threading.Thread]::CurrentThread.CurrentUICulture = $culture

    if ([System.Threading.Thread].GetProperty('DefaultThreadCurrentCulture')) {
        [System.Threading.Thread]::DefaultThreadCurrentCulture = $culture
        [System.Threading.Thread]::DefaultThreadCurrentUICulture = $culture
    }
}

function Set-WcdDecimalConfiguration {
    [CmdletBinding()]
    param(
        [string]$LogPath,
        [scriptblock]$ProgressCallback
    )

    $resolvedLogPath = Resolve-WcdLogPath -CandidatePath $LogPath
    $intlPath = 'HKCU:\Control Panel\International'
    $moduleName = 'Config-Decimal'

    try {
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'DecimalAndCurrency' -Event 'Start'
        Set-WcdRegistryValue -Path $intlPath -Name 'sDecimal' -Value '.'
        Set-WcdRegistryValue -Path $intlPath -Name 'sThousandSep' -Value ','
        Set-WcdRegistryValue -Path $intlPath -Name 'sMonDecimalSep' -Value '.'
        Set-WcdRegistryValue -Path $intlPath -Name 'sMonetaryDecimal' -Value '.'
        Set-WcdRegistryValue -Path $intlPath -Name 'sMonThousandSep' -Value ','
        Set-WcdDecimalThreadCulture -DecimalSeparator '.' -ThousandsSeparator ','
        Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'Regional: decimal and currency separators forced to a period.'
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'DecimalAndCurrency' -Event 'Finish' -Kind 'success'

        return [pscustomobject]@{
            Step    = 'DecimalAndCurrency'
            Success = $true
            LogPath = $resolvedLogPath
            Error   = ''
        }
    } catch {
        $note = $_.Exception.Message
        if ($_.Exception -is [System.UnauthorizedAccessException] -or $note -match 'non autorisee|access is denied|unauthorized') {
            $note = 'Registry key locked by GPO or access denied.'
        }
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ("Regional: {0}" -f $note)
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'DecimalAndCurrency' -Event 'Finish' -Kind 'error'

        return [pscustomobject]@{
            Step    = 'DecimalAndCurrency'
            Success = $false
            LogPath = $resolvedLogPath
            Error   = $note
        }
    }
}
