<#
.SYNOPSIS
    Configure les parametres d'alimentation Windows: timeout ecran (batterie et
    secteur), action fermeture capot, et activation du profil actif.

.DESCRIPTION
    Utilise powercfg.exe pour appliquer les timeouts ecran et les actions sur
    fermeture du capot. Les etapes de veille (standby-timeout) sont volontairement
    desactivees car bloquees par GPO dans l'environnement cible.
    Requiert WcdHelpers.ps1 charge au prealable via dot-source.

.PARAMETER DeviceType
    Type de machine. Valeurs acceptees: 'Portable', 'Bureau'.
    Les etapes batterie et capot sont ignorees pour les postes de type 'Bureau'.
    Defaut: 'Portable'.

.PARAMETER LogPath
    Chemin complet vers le fichier journal (.txt). Si omis, resolu automatiquement
    par Resolve-WcdLogPath.

.PARAMETER ProgressCallback
    Scriptblock appele a chaque debut/fin d'etape pour afficher la progression.

.OUTPUTS
    [pscustomobject[]] — tableau de resultats avec Step, Success, Error.
#>

function Set-WcdPowerConfiguration {
    [CmdletBinding()]
    param(
        [ValidateSet('Portable', 'Bureau')]
        [string]$DeviceType = 'Portable',
        [string]$LogPath,
        [scriptblock]$ProgressCallback
    )

    $resolvedLogPath = Resolve-WcdLogPath -CandidatePath $LogPath
    $results = @()
    $moduleName = 'Config-Power'

    if ($DeviceType -eq 'Portable') {
        # 1. Ecran sur batterie: 10 min
        try {
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'EcranBatterie10min' -Event 'Start'
            Invoke-WcdPowerCfg '/change' 'monitor-timeout-dc' 10
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'Alimentation: ecran batterie 10 min.'
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'EcranBatterie10min' -Event 'Finish' -Kind 'success'
            $results += [pscustomobject]@{ Step = 'EcranBatterie10min'; Success = $true; Error = '' }
        } catch {
            Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ("Ecran batterie: {0}" -f $_.Exception.Message)
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'EcranBatterie10min' -Event 'Finish' -Kind 'error'
            $results += [pscustomobject]@{ Step = 'EcranBatterie10min'; Success = $false; Error = $_.Exception.Message }
        }
    }

    # 2. Ecran sur secteur: 15 min
    try {
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'EcranSecteur15min' -Event 'Start'
        Invoke-WcdPowerCfg '/change' 'monitor-timeout-ac' 15
        Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'Alimentation: ecran secteur 15 min.'
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'EcranSecteur15min' -Event 'Finish' -Kind 'success'
        $results += [pscustomobject]@{ Step = 'EcranSecteur15min'; Success = $true; Error = '' }
    } catch {
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ("Ecran secteur: {0}" -f $_.Exception.Message)
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'EcranSecteur15min' -Event 'Finish' -Kind 'error'
        $results += [pscustomobject]@{ Step = 'EcranSecteur15min'; Success = $false; Error = $_.Exception.Message }
    }

    # BLOQUE PAR GPO: steps standby-timeout-* desactives volontairement.
    # Pour reactivation future, decommenter les blocs VeillePCSecteurJamais/VeillePCBatterieJamais ci-dessous.
    #
    # # 3. Veille PC sur secteur: Jamais (0)
    # try {
    #     Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'VeillePCSecteurJamais' -Event 'Start'
    #     Invoke-WcdPowerCfg '/change' 'standby-timeout-ac' 0
    #     Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'Alimentation: veille PC secteur jamais.'
    #     Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'VeillePCSecteurJamais' -Event 'Finish' -Kind 'success'
    #     $results += [pscustomobject]@{ Step = 'VeillePCSecteurJamais'; Success = $true; Error = '' }
    # } catch {
    #     Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ("Veille PC secteur: {0}" -f $_.Exception.Message)
    #     Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'VeillePCSecteurJamais' -Event 'Finish' -Kind 'error'
    #     $results += [pscustomobject]@{ Step = 'VeillePCSecteurJamais'; Success = $false; Error = $_.Exception.Message }
    # }
    #
    # if ($DeviceType -eq 'Portable') {
    #     # 4. Veille PC sur batterie: Jamais (0)
    #     try {
    #         Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'VeillePCBatterieJamais' -Event 'Start'
    #         Invoke-WcdPowerCfg '/change' 'standby-timeout-dc' 0
    #         Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'Alimentation: veille PC batterie jamais.'
    #         Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'VeillePCBatterieJamais' -Event 'Finish' -Kind 'success'
    #         $results += [pscustomobject]@{ Step = 'VeillePCBatterieJamais'; Success = $true; Error = '' }
    #     } catch {
    #         Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ("Veille PC batterie: {0}" -f $_.Exception.Message)
    #         Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'VeillePCBatterieJamais' -Event 'Finish' -Kind 'error'
    #         $results += [pscustomobject]@{ Step = 'VeillePCBatterieJamais'; Success = $false; Error = $_.Exception.Message }
    #     }
    # }

    # 5. Fermeture capot: Ne rien faire (seulement si Portable)
    if ($DeviceType -eq 'Portable') {
        try { # Sur secteur
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'CapotSecteurNeRienFaire' -Event 'Start'
            Invoke-WcdPowerCfg '/setacvalueindex' 'SCHEME_CURRENT' 'SUB_BUTTONS' 'LIDACTION' '0'
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'Alimentation: fermeture capot secteur ne rien faire.'
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'CapotSecteurNeRienFaire' -Event 'Finish' -Kind 'success'
            $results += [pscustomobject]@{ Step = 'CapotSecteurNeRienFaire'; Success = $true; Error = '' }
        } catch {
            Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ("Capot secteur: {0}" -f $_.Exception.Message)
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'CapotSecteurNeRienFaire' -Event 'Finish' -Kind 'error'
            $results += [pscustomobject]@{ Step = 'CapotSecteurNeRienFaire'; Success = $false; Error = $_.Exception.Message }
        }
        try { # Sur batterie
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'CapotBatterieNeRienFaire' -Event 'Start'
            Invoke-WcdPowerCfg '/setdcvalueindex' 'SCHEME_CURRENT' 'SUB_BUTTONS' 'LIDACTION' '0'
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'Alimentation: fermeture capot batterie ne rien faire.'
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'CapotBatterieNeRienFaire' -Event 'Finish' -Kind 'success'
            $results += [pscustomobject]@{ Step = 'CapotBatterieNeRienFaire'; Success = $true; Error = '' }
        } catch {
            Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ("Capot batterie: {0}" -f $_.Exception.Message)
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'CapotBatterieNeRienFaire' -Event 'Finish' -Kind 'error'
            $results += [pscustomobject]@{ Step = 'CapotBatterieNeRienFaire'; Success = $false; Error = $_.Exception.Message }
        }
    }

    # 6. Appliquer le profil actif
    try {
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'SetActiveSchemeCurrent' -Event 'Start'
        Invoke-WcdPowerCfg '/setactive' 'SCHEME_CURRENT'
        Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'Alimentation: profil actif applique.'
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'SetActiveSchemeCurrent' -Event 'Finish' -Kind 'success'
        $results += [pscustomobject]@{ Step = 'SetActiveSchemeCurrent'; Success = $true; Error = '' }
    } catch {
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ("SetActive: {0}" -f $_.Exception.Message)
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'SetActiveSchemeCurrent' -Event 'Finish' -Kind 'error'
        $results += [pscustomobject]@{ Step = 'SetActiveSchemeCurrent'; Success = $false; Error = $_.Exception.Message }
    }

    return $results
}
