<#
.SYNOPSIS
    Ouvre les applications communes (Software Center, Outlook, Chrome, Teams, etc.)
    selon le mode d'utilisation choisi (Principal ou Secondaire).

.DESCRIPTION
    Gere l'ouverture sequentielle des applications de configuration sur un poste
    Principal ou Secondaire. Chaque application produit un resultat avec un
    indicateur de succes et un niveau de severite.
    Requiert WcdHelpers.ps1 charge au prealable via dot-source.

.PARAMETER Usage
    Mode d'utilisation du poste. Valeurs acceptees: 'Workstation', 'Vdi'.
    Defaut: 'Principal'.

.PARAMETER OpenApps
    Si $false, toutes les ouvertures d'applications sont ignorees.
    Defaut: $true.

.PARAMETER LogPath
    Chemin complet vers le fichier journal (.txt). Si omis, resolu automatiquement
    par Resolve-WcdLogPath.

.PARAMETER Config
    Hashtable de configuration importee depuis WinContextDeploy.psd1.
    Permet de surcharger les chemins par defaut des applications.

.PARAMETER ProgressCallback
    Scriptblock appele a chaque debut/fin d'etape pour afficher la progression.

.OUTPUTS
    [pscustomobject[]] — tableau de resultats avec Step, Success, Error, Severity.
#>

function Open-WcdApplication {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    Start-Process $Path -ErrorAction Stop
}

function Open-WcdInExplorer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FolderPath
    )

    Start-Process 'explorer.exe' -ArgumentList $FolderPath -ErrorAction Stop
}

function Set-WcdApplicationsConfiguration {
    [CmdletBinding()]
    param(
        [ValidateSet('Workstation', 'Vdi')]
        [string]$Environment = 'Workstation',
        [bool]$OpenApps = $true,
        [string]$LogPath,
        [hashtable]$Config,
        [scriptblock]$ProgressCallback
    )

    $resolvedLogPath = Resolve-WcdLogPath -CandidatePath $LogPath
    $results = @()
    $moduleName = 'Config-Applications'

    if (-not $OpenApps) {
        Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message "Applications: ouverture refusee par l utilisateur (type: $Environment)."
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'ApplicationsSkip' -Event 'Start'
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'ApplicationsSkip' -Event 'Finish' -Kind 'success'
        $results += [pscustomobject]@{ Step = 'ApplicationsSkip'; Success = $true; Error = ''; Severity = 'INFO' }
        return $results
    }

    Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message "Applications: ouverture des liens de configuration (type: $Environment)."

    $apps = $null
    if ($null -ne $Config) { $apps = $Config.Applications }

    # 1. Software Center
    $scPath = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Microsoft Configuration Manager\Configuration Manager\Software Center'
    if ($null -ne $apps -and -not [string]::IsNullOrWhiteSpace($apps.SoftwareCenter)) {
        $scPath = $apps.SoftwareCenter
    }
    try {
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'AppSoftwareCenter' -Event 'Start'
        if (Test-Path -LiteralPath $scPath) {
            Open-WcdApplication -Path $scPath
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'Software Center ouvert.'
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'AppSoftwareCenter' -Event 'Finish' -Kind 'success'
            $results += [pscustomobject]@{ Step = 'AppSoftwareCenter'; Success = $true; Error = '' }
        } else {
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'Software Center introuvable.'
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'AppSoftwareCenter' -Event 'Finish' -Kind 'warning'
            $results += [pscustomobject]@{ Step = 'AppSoftwareCenter'; Success = $true; Error = 'Software Center introuvable.'; Severity = 'WARNING' }
        }
    } catch {
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ('Software Center: {0}' -f $_.Exception.Message)
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'AppSoftwareCenter' -Event 'Finish' -Kind 'error'
        $results += [pscustomobject]@{ Step = 'AppSoftwareCenter'; Success = $false; Error = $_.Exception.Message }
    }

    # 2. Outlook
    $outlookPath = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Outlook (classic)'
    if ($null -ne $apps -and -not [string]::IsNullOrWhiteSpace($apps.Outlook)) {
        $outlookPath = $apps.Outlook
    }
    try {
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'AppOutlook' -Event 'Start'
        if (Test-Path -LiteralPath $outlookPath) {
            Open-WcdApplication -Path $outlookPath
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'Outlook ouvert.'
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'AppOutlook' -Event 'Finish' -Kind 'success'
            $results += [pscustomobject]@{ Step = 'AppOutlook'; Success = $true; Error = '' }
        } else {
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'Outlook introuvable.'
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'AppOutlook' -Event 'Finish' -Kind 'warning'
            $results += [pscustomobject]@{ Step = 'AppOutlook'; Success = $true; Error = 'Outlook introuvable.'; Severity = 'WARNING' }
        }
    } catch {
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ('Outlook: {0}' -f $_.Exception.Message)
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'AppOutlook' -Event 'Finish' -Kind 'error'
        $results += [pscustomobject]@{ Step = 'AppOutlook'; Success = $false; Error = $_.Exception.Message }
    }

    # 3. Chrome
    $chromePath = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Google Chrome.lnk'
    if ($null -ne $apps -and -not [string]::IsNullOrWhiteSpace($apps.ChromePath)) {
        $chromePath = $apps.ChromePath
    }
    try {
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'AppChrome' -Event 'Start'
        if (Test-Path -LiteralPath $chromePath) {
            Open-WcdApplication -Path $chromePath
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'Chrome ouvert.'
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'AppChrome' -Event 'Finish' -Kind 'success'
            $results += [pscustomobject]@{ Step = 'AppChrome'; Success = $true; Error = '' }
        } else {
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'Chrome introuvable.'
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'AppChrome' -Event 'Finish' -Kind 'warning'
            $results += [pscustomobject]@{ Step = 'AppChrome'; Success = $true; Error = 'Chrome introuvable.'; Severity = 'WARNING' }
        }
    } catch {
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ('Chrome: {0}' -f $_.Exception.Message)
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'AppChrome' -Event 'Finish' -Kind 'error'
        $results += [pscustomobject]@{ Step = 'AppChrome'; Success = $false; Error = $_.Exception.Message }
    }

    # 4. Teams — lancement direct via ms-teams.exe
    $teamsExe = 'ms-teams.exe'
    if ($null -ne $apps -and -not [string]::IsNullOrWhiteSpace($apps.TeamsExe)) {
        $teamsExe = $apps.TeamsExe
    }
    try {
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'AppTeams' -Event 'Start'
        Start-Process $teamsExe -ErrorAction Stop
        Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'Teams ouvert.'
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'AppTeams' -Event 'Finish' -Kind 'success'
        $results += [pscustomobject]@{ Step = 'AppTeams'; Success = $true; Error = '' }
    } catch {
        Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'Teams introuvable.'
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'AppTeams' -Event 'Finish' -Kind 'warning'
        $results += [pscustomobject]@{ Step = 'AppTeams'; Success = $true; Error = 'Teams introuvable.'; Severity = 'WARNING' }
    }

    # 5. Snip-it (Outil Capture) — lancement direct via snippingtool
    $snipExe = 'snippingtool'
    if ($null -ne $apps -and -not [string]::IsNullOrWhiteSpace($apps.SnipItExe)) {
        $snipExe = $apps.SnipItExe
    }
    try {
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'AppSnipIt' -Event 'Start'
        Start-Process $snipExe -ErrorAction Stop
        Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'Outil Capture ouvert.'
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'AppSnipIt' -Event 'Finish' -Kind 'success'
        $results += [pscustomobject]@{ Step = 'AppSnipIt'; Success = $true; Error = '' }
    } catch {
        Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'Outil Capture introuvable.'
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'AppSnipIt' -Event 'Finish' -Kind 'warning'
        $results += [pscustomobject]@{ Step = 'AppSnipIt'; Success = $true; Error = 'Outil Capture introuvable.'; Severity = 'WARNING' }
    }

    # 6. GlobalProtect — verification par nom de processus dans le gestionnaire des taches
    # PanGPA.exe est le processus principal; les PIDs sont dynamiques donc on detecte par nom.
    $gpProcessNames = @('PanGPA', 'pangps')
    if ($null -ne $apps -and $null -ne $apps.GlobalProtectProcessNames -and @($apps.GlobalProtectProcessNames).Count -gt 0) {
        $gpProcessNames = @($apps.GlobalProtectProcessNames)
    }
    try {
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'AppGlobalProtect' -Event 'Start'
        $gpFound = $false
        foreach ($gpName in $gpProcessNames) {
            $proc = Get-Process -Name $gpName -ErrorAction SilentlyContinue
            if ($null -ne $proc) {
                $gpFound = $true
                break
            }
        }
        if ($gpFound) {
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'GlobalProtect actif (PanGPA en cours d execution).'
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'AppGlobalProtect' -Event 'Finish' -Kind 'success'
            $results += [pscustomobject]@{ Step = 'AppGlobalProtect'; Success = $true; Error = '' }
        } else {
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'GlobalProtect non detecte (PanGPA absent des processus actifs).'
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'AppGlobalProtect' -Event 'Finish' -Kind 'warning'
            $results += [pscustomobject]@{ Step = 'AppGlobalProtect'; Success = $true; Error = 'GlobalProtect non detecte (PanGPA absent des processus actifs).'; Severity = 'WARNING' }
        }
    } catch {
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ('GlobalProtect: {0}' -f $_.Exception.Message)
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'AppGlobalProtect' -Event 'Finish' -Kind 'error'
        $results += [pscustomobject]@{ Step = 'AppGlobalProtect'; Success = $false; Error = $_.Exception.Message }
    }

    # 7. Micro Focus — ouvrir dans l'explorateur SEULEMENT si present
    $mfPath = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Micro Focus'
    if ($null -ne $apps -and -not [string]::IsNullOrWhiteSpace($apps.MicroFocus)) {
        $mfPath = $apps.MicroFocus
    }
    try {
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'AppMicroFocus' -Event 'Start'
        if (Test-Path -LiteralPath $mfPath) {
            Open-WcdInExplorer -FolderPath $mfPath
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'Micro Focus: dossier ouvert dans l explorateur.'
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'AppMicroFocus' -Event 'Finish' -Kind 'success'
            $results += [pscustomobject]@{ Step = 'AppMicroFocus'; Success = $true; Error = '' }
        } else {
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'Micro Focus: non present, etape ignoree.'
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'AppMicroFocus' -Event 'Finish' -Kind 'success'
            $results += [pscustomobject]@{ Step = 'AppMicroFocus'; Success = $true; Error = ''; Severity = 'INFO' }
        }
    } catch {
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ('Micro Focus: {0}' -f $_.Exception.Message)
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'AppMicroFocus' -Event 'Finish' -Kind 'error'
        $results += [pscustomobject]@{ Step = 'AppMicroFocus'; Success = $false; Error = $_.Exception.Message }
    }

    # 8. ServiceNow (lien web)
    $snUrl = 'https://example.service-now.com/sp'
    if ($null -ne $apps -and -not [string]::IsNullOrWhiteSpace($apps.ServiceNowUrl)) {
        $snUrl = $apps.ServiceNowUrl
    }
    try {
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'AppServiceNow' -Event 'Start'
        Open-WcdApplication -Path $snUrl
        Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'ServiceNow My IT Support ouvert.'
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'AppServiceNow' -Event 'Finish' -Kind 'success'
        $results += [pscustomobject]@{ Step = 'AppServiceNow'; Success = $true; Error = '' }
    } catch {
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ('ServiceNow: {0}' -f $_.Exception.Message)
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'AppServiceNow' -Event 'Finish' -Kind 'error'
        $results += [pscustomobject]@{ Step = 'AppServiceNow'; Success = $false; Error = $_.Exception.Message }
    }

    return $results
}
