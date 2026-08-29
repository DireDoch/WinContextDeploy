<#
.SYNOPSIS
    Configure le mode d'utilisation du poste: ouvre SAP Front End (Principal)
    ou la page de telechargement Citrix Workspace (Secondaire).

.DESCRIPTION
    En mode Principal, ouvre le dossier SAP Front End dans l'Explorateur Windows.
    En mode Secondaire, ouvre la page de telechargement Citrix dans le navigateur
    par defaut.
    Requiert WcdHelpers.ps1 charge au prealable via dot-source.

.PARAMETER Usage
    Mode d'utilisation. Valeurs acceptees: 'Workstation', 'Vdi'.
    Defaut: 'Principal'.

.PARAMETER LogPath
    Chemin complet vers le fichier journal (.txt). Si omis, resolu automatiquement
    par Resolve-WcdLogPath.

.PARAMETER Config
    Hashtable de configuration importee depuis WinContextDeploy.psd1.
    Permet de surcharger les chemins et URLs par defaut.

.PARAMETER ProgressCallback
    Scriptblock appele a chaque debut/fin d'etape pour afficher la progression.

.OUTPUTS
    [pscustomobject[]] — tableau de resultats avec Step, Success, Error.
#>

function Open-WcdUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url
    )

    Start-Process $Url -ErrorAction Stop
}

function Open-WcdExplorer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FolderPath
    )

    Start-Process 'explorer.exe' -ArgumentList $FolderPath -ErrorAction Stop
}

function Set-WcdUsageConfiguration {
    [CmdletBinding()]
    param(
        [ValidateSet('Workstation', 'Vdi')]
        [string]$Environment = 'Workstation',
        [string]$LogPath,
        [hashtable]$Config,
        [scriptblock]$ProgressCallback
    )

    $resolvedLogPath = Resolve-WcdLogPath -CandidatePath $LogPath
    $results = @()
    $moduleName = 'Config-Usage'

    if ($Environment -eq 'Vdi') {
        # --- Citrix: ouvrir la page de telechargement ---
        $citrixUrl = 'https://www.citrix.com/downloads/workspace-app/'
        if ($null -ne $Config -and $null -ne $Config.Citrix) {
            $citrixUrl = $Config.Citrix.DownloadUrl
        }

        try {
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'VdiWorkspace' -Event 'Start'
            Open-WcdUrl -Url $citrixUrl
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'Environment: VDI endpoint, workspace download page opened.'
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'VdiWorkspace' -Event 'Finish' -Kind 'success'
            $results += [pscustomobject]@{ Step = 'VdiWorkspace'; Success = $true; Error = '' }
        } catch {
            Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ('VDI workspace: {0}' -f $_.Exception.Message)
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'VdiWorkspace' -Event 'Finish' -Kind 'error'
            $results += [pscustomobject]@{ Step = 'VdiWorkspace'; Success = $false; Error = $_.Exception.Message }
        }

        return $results
    }

    # --- Principal: SAP ---
    $sapPath = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\SAP Front End'
    if ($null -ne $Config -and $null -ne $Config.Principal) {
        $sapPath = $Config.Principal.SAPPath
    }

    try {
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'SAPFrontEnd' -Event 'Start'
        if (Test-Path -LiteralPath $sapPath) {
            Open-WcdExplorer -FolderPath $sapPath
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'ERP client: folder opened in Explorer.'
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'SAPFrontEnd' -Event 'Finish' -Kind 'success'
            $results += [pscustomobject]@{ Step = 'SAPFrontEnd'; Success = $true; Error = '' }
        } else {
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'ERP client: folder not found.'
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'SAPFrontEnd' -Event 'Finish' -Kind 'warning'
            $results += [pscustomobject]@{ Step = 'SAPFrontEnd'; Success = $true; Error = 'SAP Front End introuvable sur ce poste.'; Severity = 'WARNING' }
        }
    } catch {
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ('ERP client: {0}' -f $_.Exception.Message)
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'SAPFrontEnd' -Event 'Finish' -Kind 'error'
        $results += [pscustomobject]@{ Step = 'SAPFrontEnd'; Success = $false; Error = $_.Exception.Message }
    }

    return $results
}