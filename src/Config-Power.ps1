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
    Type de machine. Valeurs acceptees: 'Laptop', 'Desktop'.
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
        [ValidateSet('Laptop', 'Desktop')]
        [string]$FormFactor = 'Laptop',
        [string]$LogPath,
        [scriptblock]$ProgressCallback
    )

    $resolvedLogPath = Resolve-WcdLogPath -CandidatePath $LogPath
    $results = @()
    $moduleName = 'Config-Power'

    if ($FormFactor -eq 'Laptop') {
        # 1. Ecran sur batterie: 10 min
        try {
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'ScreenTimeoutBattery' -Event 'Start'
            Invoke-WcdPowerCfg '/change' 'monitor-timeout-dc' 10
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'Power: screen timeout on battery set to 10 min.'
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'ScreenTimeoutBattery' -Event 'Finish' -Kind 'success'
            $results += [pscustomobject]@{ Step = 'ScreenTimeoutBattery'; Success = $true; Error = '' }
        } catch {
            Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ("Screen timeout on battery: {0}" -f $_.Exception.Message)
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'ScreenTimeoutBattery' -Event 'Finish' -Kind 'error'
            $results += [pscustomobject]@{ Step = 'ScreenTimeoutBattery'; Success = $false; Error = $_.Exception.Message }
        }
    }

    # 2. Ecran sur secteur: 15 min
    try {
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'ScreenTimeoutAc' -Event 'Start'
        Invoke-WcdPowerCfg '/change' 'monitor-timeout-ac' 15
        Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'Power: screen timeout on AC set to 15 min.'
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'ScreenTimeoutAc' -Event 'Finish' -Kind 'success'
        $results += [pscustomobject]@{ Step = 'ScreenTimeoutAc'; Success = $true; Error = '' }
    } catch {
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ("Screen timeout on AC: {0}" -f $_.Exception.Message)
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'ScreenTimeoutAc' -Event 'Finish' -Kind 'error'
        $results += [pscustomobject]@{ Step = 'ScreenTimeoutAc'; Success = $false; Error = $_.Exception.Message }
    }

    # BLOQUE PAR GPO: steps standby-timeout-* desactives volontairement.
    # Pour reactivation future, decommenter les blocs SleepAcNever/SleepBatteryNever ci-dessous.
    #
    # # 3. Veille PC sur secteur: Jamais (0)
    # try {
    #     Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'SleepAcNever' -Event 'Start'
    #     Invoke-WcdPowerCfg '/change' 'standby-timeout-ac' 0
    #     Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'Power: sleep on AC set to never.'
    #     Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'SleepAcNever' -Event 'Finish' -Kind 'success'
    #     $results += [pscustomobject]@{ Step = 'SleepAcNever'; Success = $true; Error = '' }
    # } catch {
    #     Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ("Sleep on AC: {0}" -f $_.Exception.Message)
    #     Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'SleepAcNever' -Event 'Finish' -Kind 'error'
    #     $results += [pscustomobject]@{ Step = 'SleepAcNever'; Success = $false; Error = $_.Exception.Message }
    # }
    #
    # if ($FormFactor -eq 'Laptop') {
    #     # 4. Veille PC sur batterie: Jamais (0)
    #     try {
    #         Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'SleepBatteryNever' -Event 'Start'
    #         Invoke-WcdPowerCfg '/change' 'standby-timeout-dc' 0
    #         Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'Power: sleep on battery set to never.'
    #         Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'SleepBatteryNever' -Event 'Finish' -Kind 'success'
    #         $results += [pscustomobject]@{ Step = 'SleepBatteryNever'; Success = $true; Error = '' }
    #     } catch {
    #         Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ("Sleep on battery: {0}" -f $_.Exception.Message)
    #         Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'SleepBatteryNever' -Event 'Finish' -Kind 'error'
    #         $results += [pscustomobject]@{ Step = 'SleepBatteryNever'; Success = $false; Error = $_.Exception.Message }
    #     }
    # }

    # 5. Fermeture capot: Ne rien faire (seulement si Portable)
    if ($FormFactor -eq 'Laptop') {
        try { # Sur secteur
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'LidActionAcNone' -Event 'Start'
            Invoke-WcdPowerCfg '/setacvalueindex' 'SCHEME_CURRENT' 'SUB_BUTTONS' 'LIDACTION' '0'
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'Power: lid close on AC set to do nothing.'
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'LidActionAcNone' -Event 'Finish' -Kind 'success'
            $results += [pscustomobject]@{ Step = 'LidActionAcNone'; Success = $true; Error = '' }
        } catch {
            Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ("Lid close on AC: {0}" -f $_.Exception.Message)
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'LidActionAcNone' -Event 'Finish' -Kind 'error'
            $results += [pscustomobject]@{ Step = 'LidActionAcNone'; Success = $false; Error = $_.Exception.Message }
        }
        try { # Sur batterie
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'LidActionBatteryNone' -Event 'Start'
            Invoke-WcdPowerCfg '/setdcvalueindex' 'SCHEME_CURRENT' 'SUB_BUTTONS' 'LIDACTION' '0'
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'Power: lid close on battery set to do nothing.'
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'LidActionBatteryNone' -Event 'Finish' -Kind 'success'
            $results += [pscustomobject]@{ Step = 'LidActionBatteryNone'; Success = $true; Error = '' }
        } catch {
            Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ("Lid close on battery: {0}" -f $_.Exception.Message)
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'LidActionBatteryNone' -Event 'Finish' -Kind 'error'
            $results += [pscustomobject]@{ Step = 'LidActionBatteryNone'; Success = $false; Error = $_.Exception.Message }
        }
    }

    # 6. Appliquer le profil actif
    try {
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'SetActiveSchemeCurrent' -Event 'Start'
        Invoke-WcdPowerCfg '/setactive' 'SCHEME_CURRENT'
        Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'Power: active scheme applied.'
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'SetActiveSchemeCurrent' -Event 'Finish' -Kind 'success'
        $results += [pscustomobject]@{ Step = 'SetActiveSchemeCurrent'; Success = $true; Error = '' }
    } catch {
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ("Apply active scheme: {0}" -f $_.Exception.Message)
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'SetActiveSchemeCurrent' -Event 'Finish' -Kind 'error'
        $results += [pscustomobject]@{ Step = 'SetActiveSchemeCurrent'; Success = $false; Error = $_.Exception.Message }
    }

    return $results
}
