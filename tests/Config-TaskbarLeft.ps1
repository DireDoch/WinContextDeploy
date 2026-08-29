<#
.SYNOPSIS
    Aligne la barre des taches a gauche et desactive le bouton "Vue des taches"
    via le registre Windows.

.DESCRIPTION
    Modifie HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced:
    - TaskbarAl = 0 (alignement gauche)
    - ShowTaskViewButton = 0 (bouton vue des taches masque)
    La desactivation des Widgets (TaskbarDa) est commentee car bloquee par GPO
    dans certains environnements gérés par GPO.
    Requiert MinimalHelpers.ps1 charge au prealable via dot-source.

.PARAMETER LogPath
    Chemin complet vers le fichier journal (.txt). Si omis, resolu automatiquement
    par Resolve-MinimalLogPath.

.PARAMETER ProgressCallback
    Scriptblock appele a chaque debut/fin d'etape pour afficher la progression.

.OUTPUTS
    [pscustomobject[]] — tableau de resultats avec Step, Success, Error.
#>

function Set-MinimalTaskbarLeft {
    [CmdletBinding()]
    param(
        [string]$LogPath,
        [scriptblock]$ProgressCallback
    )

    $resolvedLogPath = Resolve-MinimalLogPath -CandidatePath $LogPath
    $registryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    $results = @()
    $moduleName = 'Config-TaskbarLeft'

    # 1. Alignement a gauche
    try {
        Invoke-MinimalProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'TaskbarAlignementGauche' -Event 'Start'
        Set-MinimalRegistryValue -Path $registryPath -Name 'TaskbarAl' -Value 0 -PropertyType DWord
        Write-MinimalLog -Path $resolvedLogPath -Level 'INFO' -Message 'Barre des taches: alignement a gauche.'
        Invoke-MinimalProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'TaskbarAlignementGauche' -Event 'Finish' -Kind 'success'
        $results += [pscustomobject]@{ Step = 'TaskbarAlignementGauche'; Success = $true; Error = '' }
    } catch {
        $note = $_.Exception.Message
        if ($_.Exception -is [System.UnauthorizedAccessException] -or $note -match 'non autorisee|access is denied|unauthorized') {
            $note = 'Cle verrouillee par GPO ou acces refuse.'
        }
        Write-MinimalLog -Path $resolvedLogPath -Level 'ERROR' -Message ("Barre des taches alignement: {0}" -f $note)
        Invoke-MinimalProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'TaskbarAlignementGauche' -Event 'Finish' -Kind 'error'
        $results += [pscustomobject]@{ Step = 'TaskbarAlignementGauche'; Success = $false; Error = $note }
    }

    # 2. Desactiver les Widgets (commente: bloque par GPO dans certains environnements)
    # try {
    #     Set-MinimalRegistryValue -Path $registryPath -Name 'TaskbarDa' -Value 0 -PropertyType DWord
    #     Write-MinimalLog -Path $resolvedLogPath -Level 'INFO' -Message 'Barre des taches: widgets desactives.'
    #     $results += [pscustomobject]@{ Step = 'DesactiverWidgets'; Success = $true; Error = '' }
    # } catch {
    #     $note = $_.Exception.Message
    #     if ($_.Exception -is [System.UnauthorizedAccessException] -or $note -match 'non autorisee|access is denied|unauthorized') {
    #         $note = 'Cle verrouillee par GPO ou acces refuse.'
    #     }
    #     Write-MinimalLog -Path $resolvedLogPath -Level 'ERROR' -Message ("Barre des taches widgets: {0}" -f $note)
    #     $results += [pscustomobject]@{ Step = 'DesactiverWidgets'; Success = $false; Error = $note }
    # }

    # 3. Desactiver la Vue des taches
    try {
        Invoke-MinimalProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'DesactiverVueTaches' -Event 'Start'
        Set-MinimalRegistryValue -Path $registryPath -Name 'ShowTaskViewButton' -Value 0 -PropertyType DWord
        Write-MinimalLog -Path $resolvedLogPath -Level 'INFO' -Message 'Barre des taches: vue des taches desactivee.'
        Invoke-MinimalProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'DesactiverVueTaches' -Event 'Finish' -Kind 'success'
        $results += [pscustomobject]@{ Step = 'DesactiverVueTaches'; Success = $true; Error = '' }
    } catch {
        $note = $_.Exception.Message
        if ($_.Exception -is [System.UnauthorizedAccessException] -or $note -match 'non autorisee|access is denied|unauthorized') {
            $note = 'Cle verrouillee par GPO ou acces refuse.'
        }
        Write-MinimalLog -Path $resolvedLogPath -Level 'ERROR' -Message ("Barre des taches vue taches: {0}" -f $note)
        Invoke-MinimalProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'DesactiverVueTaches' -Event 'Finish' -Kind 'error'
        $results += [pscustomobject]@{ Step = 'DesactiverVueTaches'; Success = $false; Error = $note }
    }

    return $results
}
