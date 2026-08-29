<#
.SYNOPSIS
    Ouvre l'outil "Find and add Printer" pour permettre a l'utilisateur
    d'ajouter une imprimante reseau.

.DESCRIPTION
    Lance le raccourci .lnk du gestionnaire d'imprimantes. Si l'ajout est refuse
    par l'utilisateur ou si le raccourci est introuvable, retourne un resultat
    explicite sans lever d'exception.
    Requiert MinimalHelpers.ps1 charge au prealable via dot-source.

.PARAMETER AddPrinter
    Si $false, l'ouverture est ignoree et un resultat 'PrinterSkip' est retourne.
    Defaut: $true.

.PARAMETER LogPath
    Chemin complet vers le fichier journal (.txt). Si omis, resolu automatiquement
    par Resolve-MinimalLogPath.

.PARAMETER Config
    Hashtable de configuration importee depuis Config-Paths.psd1.
    Permet de surcharger le chemin par defaut du raccourci.

.OUTPUTS
    [pscustomobject] — resultat unique avec Step ('PrinterSkip' ou 'PrinterAdd'),
    Success, Error.
#>

function Open-MinimalPrinterTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    Start-Process $Path -ErrorAction Stop
}

function Set-MinimalPrinterConfiguration {
    [CmdletBinding()]
    param(
        [bool]$AddPrinter = $true,
        [string]$LogPath,
        [hashtable]$Config
    )

    $resolvedLogPath = Resolve-MinimalLogPath -CandidatePath $LogPath

    if (-not $AddPrinter) {
        Write-MinimalLog -Path $resolvedLogPath -Level 'INFO' -Message 'Imprimante: ajout refuse par l utilisateur.'
        return [pscustomobject]@{ Step = 'PrinterSkip'; Success = $true; Error = '' }
    }

    $printerPath = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Find and add Printer.lnk'
    if ($null -ne $Config -and $null -ne $Config.Printer -and -not [string]::IsNullOrWhiteSpace($Config.Printer.PrintManagerPath)) {
        $printerPath = $Config.Printer.PrintManagerPath
    }

    try {
        if (-not (Test-Path -LiteralPath $printerPath)) {
            Write-MinimalLog -Path $resolvedLogPath -Level 'ERROR' -Message 'Imprimante: Find and add Printer introuvable.'
            return [pscustomobject]@{ Step = 'PrinterAdd'; Success = $false; Error = 'Find and add Printer introuvable.' }
        }

        Open-MinimalPrinterTool -Path $printerPath
        Write-MinimalLog -Path $resolvedLogPath -Level 'INFO' -Message 'Imprimante: Find and add Printer ouvert.'
        return [pscustomobject]@{ Step = 'PrinterAdd'; Success = $true; Error = '' }
    } catch {
        Write-MinimalLog -Path $resolvedLogPath -Level 'ERROR' -Message ('Imprimante: {0}' -f $_.Exception.Message)
        return [pscustomobject]@{ Step = 'PrinterAdd'; Success = $false; Error = $_.Exception.Message }
    }
}
