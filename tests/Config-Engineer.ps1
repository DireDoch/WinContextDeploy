<#
.SYNOPSIS
    Ouvre les ressources web pour les ordinateurs d'ingenieur (Nvidia, GPS)
    selon les types selectionnes.

.DESCRIPTION
    Supporte la multi-selection: plusieurs types peuvent etre traites en une
    seule execution. Si le type est 'Non', l'etape est ignoree sans erreur.
    Tente d'ouvrir les URLs dans Chrome; bascule sur le navigateur par defaut
    si Chrome est introuvable.
    Requiert MinimalHelpers.ps1 charge au prealable via dot-source.

.PARAMETER EngineerTypes
    Tableau de types d'ingenieur. Valeurs acceptees: 'Nvidia', 'GPS', 'Non'.
    Defaut: @('Non').

.PARAMETER LogPath
    Chemin complet vers le fichier journal (.txt). Si omis, resolu automatiquement
    par Resolve-MinimalLogPath.

.PARAMETER Config
    Hashtable de configuration importee depuis Config-Paths.psd1.
    Permet de surcharger les URLs et chemins par defaut.

.PARAMETER ProgressCallback
    Scriptblock appele a chaque debut/fin d'etape pour afficher la progression.

.OUTPUTS
    [pscustomobject[]] — tableau de resultats avec Step, Success, Error.
#>

function Open-MinimalUrlInChrome {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url,

        [string]$ChromePath
    )

    if (-not [string]::IsNullOrWhiteSpace($ChromePath) -and (Test-Path -LiteralPath $ChromePath)) {
        Start-Process $ChromePath -ArgumentList $Url -ErrorAction Stop
    } else {
        # Fallback: ouvrir avec le navigateur par defaut
        Start-Process $Url -ErrorAction Stop
    }
}

function Open-MinimalShortcut {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    Start-Process $Path -ErrorAction Stop
}

function Set-MinimalEngineerConfiguration {
    [CmdletBinding()]
    param(
        [string[]]$EngineerTypes = @('Non'),
        [string]$LogPath,
        [hashtable]$Config,
        [scriptblock]$ProgressCallback
    )

    $resolvedLogPath = Resolve-MinimalLogPath -CandidatePath $LogPath
    $moduleName = 'Config-Engineer'

    if ($EngineerTypes.Count -eq 1 -and $EngineerTypes[0] -eq 'Non') {
        Write-MinimalLog -Path $resolvedLogPath -Level 'INFO' -Message 'Ingenieur: aucune configuration requise.'
        Invoke-MinimalProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'EngineerSkip' -Event 'Start'
        Invoke-MinimalProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'EngineerSkip' -Event 'Finish' -Kind 'success'
        return @([pscustomobject]@{ Step = 'EngineerSkip'; Success = $true; Error = '' })
    }

    $engConfig = $null
    if ($null -ne $Config) { $engConfig = $Config.Engineer }

    $chromePath = ''
    if ($null -ne $engConfig -and -not [string]::IsNullOrWhiteSpace($engConfig.ChromePath)) {
        $chromePath = $engConfig.ChromePath
    }

    $results = @()

    foreach ($type in $EngineerTypes) {
        switch ($type) {
            'Nvidia' {
                $url = 'https://www.nvidia.com/en-eu/software/nvidia-app/'
                if ($null -ne $engConfig -and -not [string]::IsNullOrWhiteSpace($engConfig.NvidiaUrl)) {
                    $url = $engConfig.NvidiaUrl
                }
                try {
                    Invoke-MinimalProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'EngineerNvidia' -Event 'Start'
                    Open-MinimalUrlInChrome -Url $url -ChromePath $chromePath
                    Write-MinimalLog -Path $resolvedLogPath -Level 'INFO' -Message ("Ingenieur: Nvidia ouvert ({0})." -f $url)
                    Invoke-MinimalProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'EngineerNvidia' -Event 'Finish' -Kind 'success'
                    $results += [pscustomobject]@{ Step = 'EngineerNvidia'; Success = $true; Error = '' }
                } catch {
                    Write-MinimalLog -Path $resolvedLogPath -Level 'ERROR' -Message ("Ingenieur Nvidia: {0}" -f $_.Exception.Message)
                    Invoke-MinimalProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'EngineerNvidia' -Event 'Finish' -Kind 'error'
                    $results += [pscustomobject]@{ Step = 'EngineerNvidia'; Success = $false; Error = $_.Exception.Message }
                }
            }
            'GPS' {
                $url = 'https://gps.example.com/client/publish.html'
                if ($null -ne $engConfig -and -not [string]::IsNullOrWhiteSpace($engConfig.GPSUrl)) {
                    $url = $engConfig.GPSUrl
                }
                try {
                    Invoke-MinimalProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'EngineerGPS' -Event 'Start'
                    Open-MinimalUrlInChrome -Url $url -ChromePath $chromePath
                    Write-MinimalLog -Path $resolvedLogPath -Level 'INFO' -Message ("Ingenieur: GPS ouvert ({0})." -f $url)
                    Invoke-MinimalProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'EngineerGPS' -Event 'Finish' -Kind 'success'
                    $results += [pscustomobject]@{ Step = 'EngineerGPS'; Success = $true; Error = '' }
                } catch {
                    Write-MinimalLog -Path $resolvedLogPath -Level 'ERROR' -Message ("Ingenieur GPS: {0}" -f $_.Exception.Message)
                    Invoke-MinimalProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'EngineerGPS' -Event 'Finish' -Kind 'error'
                    $results += [pscustomobject]@{ Step = 'EngineerGPS'; Success = $false; Error = $_.Exception.Message }
                }
            }
        }
    }

    return $results
}
