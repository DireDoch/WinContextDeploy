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
    Requiert WcdHelpers.ps1 charge au prealable via dot-source.

.PARAMETER LogPath
    Chemin complet vers le fichier journal (.txt). Si omis, resolu automatiquement
    par Resolve-WcdLogPath.

.PARAMETER ProgressCallback
    Scriptblock appele a chaque debut/fin d'etape pour afficher la progression.

.OUTPUTS
    [pscustomobject[]] — tableau de resultats avec Step, Success, Error.
#>

function Set-WcdTaskbarLeft {
    [CmdletBinding()]
    param(
        [string]$LogPath,
        [scriptblock]$ProgressCallback
    )

    $resolvedLogPath = Resolve-WcdLogPath -CandidatePath $LogPath
    $registryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    $results = @()
    $moduleName = 'Config-TaskbarLeft'

    # 1. Alignement a gauche
    try {
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'TaskbarAlignLeft' -Event 'Start'
        Set-WcdRegistryValue -Path $registryPath -Name 'TaskbarAl' -Value 0 -PropertyType DWord
        Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'Taskbar: aligned left.'
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'TaskbarAlignLeft' -Event 'Finish' -Kind 'success'
        $results += [pscustomobject]@{ Step = 'TaskbarAlignLeft'; Success = $true; Error = '' }
    } catch {
        $note = $_.Exception.Message
        if ($_.Exception -is [System.UnauthorizedAccessException] -or $note -match 'non autorisee|access is denied|unauthorized') {
            $note = 'Registry key locked by GPO or access denied.'
        }
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ("Taskbar align: {0}" -f $note)
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'TaskbarAlignLeft' -Event 'Finish' -Kind 'error'
        $results += [pscustomobject]@{ Step = 'TaskbarAlignLeft'; Success = $false; Error = $note }
    }

    # 2. Desactiver les Widgets (commente: bloque par GPO dans certains environnements)
    # try {
    #     Set-WcdRegistryValue -Path $registryPath -Name 'TaskbarDa' -Value 0 -PropertyType DWord
    #     Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'Taskbar: widgets disabled.'
    #     $results += [pscustomobject]@{ Step = 'DisableWidgets'; Success = $true; Error = '' }
    # } catch {
    #     $note = $_.Exception.Message
    #     if ($_.Exception -is [System.UnauthorizedAccessException] -or $note -match 'non autorisee|access is denied|unauthorized') {
    #         $note = 'Registry key locked by GPO or access denied.'
    #     }
    #     Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ("Taskbar widgets: {0}" -f $note)
    #     $results += [pscustomobject]@{ Step = 'DisableWidgets'; Success = $false; Error = $note }
    # }

    # 3. Desactiver la Vue des taches
    try {
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'DisableTaskView' -Event 'Start'
        Set-WcdRegistryValue -Path $registryPath -Name 'ShowTaskViewButton' -Value 0 -PropertyType DWord
        Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'Taskbar: task view disabled.'
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'DisableTaskView' -Event 'Finish' -Kind 'success'
        $results += [pscustomobject]@{ Step = 'DisableTaskView'; Success = $true; Error = '' }
    } catch {
        $note = $_.Exception.Message
        if ($_.Exception -is [System.UnauthorizedAccessException] -or $note -match 'non autorisee|access is denied|unauthorized') {
            $note = 'Registry key locked by GPO or access denied.'
        }
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ("Taskbar task view: {0}" -f $note)
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'DisableTaskView' -Event 'Finish' -Kind 'error'
        $results += [pscustomobject]@{ Step = 'DisableTaskView'; Success = $false; Error = $note }
    }

    return $results
}
