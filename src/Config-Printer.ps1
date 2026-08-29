<#
.SYNOPSIS
    Ouvre l'outil "Find and add Printer" pour permettre a l'utilisateur
    d'ajouter une imprimante reseau.

.DESCRIPTION
    Lance le raccourci .lnk du gestionnaire d'imprimantes. Si l'ajout est refuse
    par l'utilisateur ou si le raccourci est introuvable, retourne un resultat
    explicite sans lever d'exception.
    Requiert WcdHelpers.ps1 charge au prealable via dot-source.

.PARAMETER AddPrinter
    Si $false, l'ouverture est ignoree et un resultat 'PrinterSkip' est retourne.
    Defaut: $true.

.PARAMETER LogPath
    Chemin complet vers le fichier journal (.txt). Si omis, resolu automatiquement
    par Resolve-WcdLogPath.

.PARAMETER Config
    Hashtable de configuration importee depuis WinContextDeploy.psd1.
    Permet de surcharger le chemin par defaut du raccourci.

.OUTPUTS
    [pscustomobject] — resultat unique avec Step ('PrinterSkip' ou 'PrinterAdd'),
    Success, Error.
#>

function Open-WcdPrinterTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    Start-Process $Path -ErrorAction Stop
}

function Set-WcdPrinterConfiguration {
    [CmdletBinding()]
    param(
        [bool]$AddPrinter = $true,
        [string]$LogPath,
        [hashtable]$Config
    )

    $resolvedLogPath = Resolve-WcdLogPath -CandidatePath $LogPath

    if (-not $AddPrinter) {
        Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'Printer: add declined by the technician.'
        return [pscustomobject]@{ Step = 'PrinterSkip'; Success = $true; Error = '' }
    }

    $printerPath = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Find and add Printer.lnk'
    if ($null -ne $Config -and $null -ne $Config.Printer -and -not [string]::IsNullOrWhiteSpace($Config.Printer.PrintManagerPath)) {
        $printerPath = $Config.Printer.PrintManagerPath
    }

    try {
        if (-not (Test-Path -LiteralPath $printerPath)) {
            Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message 'Printer: printer tool not found.'
            return [pscustomobject]@{ Step = 'PrinterAdd'; Success = $false; Error = 'Find and add Printer introuvable.' }
        }

        Open-WcdPrinterTool -Path $printerPath
        Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'Printer: printer tool opened.'
        return [pscustomobject]@{ Step = 'PrinterAdd'; Success = $true; Error = '' }
    } catch {
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ('Printer: {0}' -f $_.Exception.Message)
        return [pscustomobject]@{ Step = 'PrinterAdd'; Success = $false; Error = $_.Exception.Message }
    }
}
