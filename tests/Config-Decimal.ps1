<#
.SYNOPSIS
    Force les separateurs decimaux et monetaires a '.' dans les parametres
    regionaux Windows et dans la culture du thread PowerShell courant.

.DESCRIPTION
    Modifie les cles de registre HKCU:\Control Panel\International pour
    appliquer le point comme separateur decimal et la virgule comme separateur
    de milliers, aussi bien pour les nombres que pour les montants.
    Requiert MinimalHelpers.ps1 charge au prealable via dot-source.

.PARAMETER LogPath
    Chemin complet vers le fichier journal (.txt). Si omis, resolu automatiquement
    par Resolve-MinimalLogPath.

.PARAMETER ProgressCallback
    Scriptblock appele a chaque debut/fin d'etape pour afficher la progression.

.OUTPUTS
    [pscustomobject] — resultat unique avec Step, Success, LogPath, Error.
#>

function Set-MinimalDecimalThreadCulture {
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

function Set-MinimalDecimalConfiguration {
    [CmdletBinding()]
    param(
        [string]$LogPath,
        [scriptblock]$ProgressCallback
    )

    $resolvedLogPath = Resolve-MinimalLogPath -CandidatePath $LogPath
    $intlPath = 'HKCU:\Control Panel\International'
    $moduleName = 'Config-Decimal'

    try {
        Invoke-MinimalProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'DecimalEtMonetaire' -Event 'Start'
        Set-MinimalRegistryValue -Path $intlPath -Name 'sDecimal' -Value '.'
        Set-MinimalRegistryValue -Path $intlPath -Name 'sThousandSep' -Value ','
        Set-MinimalRegistryValue -Path $intlPath -Name 'sMonDecimalSep' -Value '.'
        Set-MinimalRegistryValue -Path $intlPath -Name 'sMonetaryDecimal' -Value '.'
        Set-MinimalRegistryValue -Path $intlPath -Name 'sMonThousandSep' -Value ','
        Set-MinimalDecimalThreadCulture -DecimalSeparator '.' -ThousandsSeparator ','
        Write-MinimalLog -Path $resolvedLogPath -Level 'INFO' -Message 'Decimales: symboles numeriques et monetaires forces a un point.'
        Invoke-MinimalProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'DecimalEtMonetaire' -Event 'Finish' -Kind 'success'

        return [pscustomobject]@{
            Step    = 'DecimalEtMonetaire'
            Success = $true
            LogPath = $resolvedLogPath
            Error   = ''
        }
    } catch {
        $note = $_.Exception.Message
        if ($_.Exception -is [System.UnauthorizedAccessException] -or $note -match 'non autorisee|access is denied|unauthorized') {
            $note = 'Cle verrouillee par GPO ou acces refuse.'
        }
        Write-MinimalLog -Path $resolvedLogPath -Level 'ERROR' -Message ("Decimales: {0}" -f $note)
        Invoke-MinimalProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'DecimalEtMonetaire' -Event 'Finish' -Kind 'error'

        return [pscustomobject]@{
            Step    = 'DecimalEtMonetaire'
            Success = $false
            LogPath = $resolvedLogPath
            Error   = $note
        }
    }
}
