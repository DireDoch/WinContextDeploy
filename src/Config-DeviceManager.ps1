<#
.SYNOPSIS
    Inspecte le Gestionnaire de peripheriques via Win32_PnPEntity et signale
    les peripheriques ayant un ConfigManagerErrorCode non nul.

.DESCRIPTION
    Interroge WMI/CIM pour obtenir tous les peripheriques Plug-and-Play.
    Les codes d'erreur sont classes WARNING ou ERROR selon leur valeur.
    Certains peripheriques connus (ex: PANGP code 22) sont ignores par
    exception explicite pour eviter les faux positifs.
    Requiert WcdHelpers.ps1 charge au prealable via dot-source.

.PARAMETER LogPath
    Chemin complet vers le fichier journal (.txt). Si omis, resolu automatiquement
    par Resolve-WcdLogPath.

.PARAMETER ProgressCallback
    Scriptblock appele a chaque debut/fin d'etape pour afficher la progression.

.OUTPUTS
    [pscustomobject] — resultat unique avec Step, Success, Severity, Error.
#>

function Get-WcdPnPDevices {
    [CmdletBinding()]
    param()

    return @(Get-CimInstance -ClassName 'Win32_PnPEntity' -ErrorAction Stop)
}

function Get-WcdDeviceManagerCodeInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$Code
    )

    switch ($Code) {
        14 { return @{ Severity = 'WARNING'; Label = 'Redemarrage requis pour finaliser le peripherique.' } }
        24 { return @{ Severity = 'WARNING'; Label = 'Peripherique non present ou configuration incomplete.' } }
        45 { return @{ Severity = 'WARNING'; Label = 'Peripherique actuellement non connecte.' } }
        47 { return @{ Severity = 'WARNING'; Label = 'Peripherique en attente de suppression ou de redemarrage.' } }
        1  { return @{ Severity = 'ERROR'; Label = 'Peripherique non configure correctement.' } }
        3  { return @{ Severity = 'ERROR'; Label = 'Pilote probablement endommage ou absent.' } }
        10 { return @{ Severity = 'ERROR'; Label = 'Le peripherique ne peut pas demarrer.' } }
        18 { return @{ Severity = 'ERROR'; Label = 'Le pilote doit etre reinstalle.' } }
        28 { return @{ Severity = 'ERROR'; Label = 'Aucun pilote installe pour ce peripherique.' } }
        31 { return @{ Severity = 'ERROR'; Label = 'Windows ne peut pas charger les pilotes requis.' } }
        43 { return @{ Severity = 'ERROR'; Label = 'Le peripherique a signale une erreur et a ete arrete.' } }
        default { return @{ Severity = 'ERROR'; Label = 'Probleme detecte par le Gestionnaire de peripheriques.' } }
    }
}

function Test-WcdIgnoredDeviceManagerIssue {
    [CmdletBinding()]
    param(
        [string]$DeviceName,

        [int]$Code
    )

    # Exception
    # remonte frequemment en code 22 sans impact operationnel pour le poste.
    # On ignore uniquement ce nom precis combine au code 22 afin de ne pas masquer
    # d'autres erreurs ou avertissements legitimes du Gestionnaire de peripheriques.
    return ($Code -eq 22 -and $DeviceName -like 'PANGP Virtual Ethernet Adapter*')
}

function Format-WcdDeviceManagerSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Devices,

        [int]$Limit = 3
    )

    $preview = @($Devices | Select-Object -First $Limit | ForEach-Object {
        '{0} (code {1})' -f $_.Name, $_.Code
    })

    $summary = $preview -join ', '
    if (@($Devices).Count -gt $Limit) {
        $summary = '{0}, +{1} autre(s)' -f $summary, (@($Devices).Count - $Limit)
    }

    return $summary
}

function Set-WcdDeviceManagerStatus {
    [CmdletBinding()]
    param(
        [string]$LogPath,
        [scriptblock]$ProgressCallback
    )

    $resolvedLogPath = Resolve-WcdLogPath -CandidatePath $LogPath
    $moduleName = 'Config-DeviceManager'
    Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'DeviceManagerStatus' -Event 'Start'

    try {
        $devices = @(Get-WcdPnPDevices)
    } catch {
        $note = 'Impossible d interroger le Gestionnaire de peripheriques via CIM: {0}' -f $_.Exception.Message
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message $note
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'DeviceManagerStatus' -Event 'Finish' -Kind 'error'

        return [pscustomobject]@{
            Step     = 'DeviceManagerStatus'
            Success  = $false
            Severity = 'ERROR'
            Error    = $note
        }
    }

    $problemDevices = @()
    foreach ($device in $devices) {
        $code = 0
        if ($null -ne $device.ConfigManagerErrorCode) {
            $code = [int]$device.ConfigManagerErrorCode
        }

        if ($code -eq 0) {
            continue
        }

        $info = Get-WcdDeviceManagerCodeInfo -Code $code
        $deviceName = $device.Name
        if ([string]::IsNullOrWhiteSpace($deviceName)) {
            $deviceName = $device.PNPDeviceID
        }
        if ([string]::IsNullOrWhiteSpace($deviceName)) {
            $deviceName = 'Peripherique sans nom'
        }

        if (Test-WcdIgnoredDeviceManagerIssue -DeviceName $deviceName -Code $code) {
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('Device Manager: peripherique ignore selon exception connue: {0} (code {1}).' -f $deviceName, $code)
            continue
        }

        $problemDevices += [pscustomobject]@{
            Name     = $deviceName
            Code     = $code
            Severity = $info.Severity
            Label    = $info.Label
        }
    }

    $warningDevices = @($problemDevices | Where-Object { $_.Severity -eq 'WARNING' })
    $errorDevices = @($problemDevices | Where-Object { $_.Severity -eq 'ERROR' })

    if ($errorDevices.Count -gt 0) {
        $errorSummary = Format-WcdDeviceManagerSummary -Devices $errorDevices
        $warningSummary = ''
        if ($warningDevices.Count -gt 0) {
            $warningSummary = ' | Warnings: {0}' -f (Format-WcdDeviceManagerSummary -Devices $warningDevices)
        }

        $message = 'Erreurs Device Manager detectees ({0}): {1}{2}' -f $errorDevices.Count, $errorSummary, $warningSummary
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message $message
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'DeviceManagerStatus' -Event 'Finish' -Kind 'error'

        return [pscustomobject]@{
            Step     = 'DeviceManagerStatus'
            Success  = $false
            Severity = 'ERROR'
            Error    = $message
        }
    }

    if ($warningDevices.Count -gt 0) {
        $message = 'Warnings Device Manager detectes ({0}): {1}' -f $warningDevices.Count, (Format-WcdDeviceManagerSummary -Devices $warningDevices)
        Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message $message
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'DeviceManagerStatus' -Event 'Finish' -Kind 'warning'

        return [pscustomobject]@{
            Step     = 'DeviceManagerStatus'
            Success  = $true
            Severity = 'WARNING'
            Error    = $message
        }
    }

    Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'Device Manager: no warnings or errors detected.'
    Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'DeviceManagerStatus' -Event 'Finish' -Kind 'success'
    return [pscustomobject]@{
        Step     = 'DeviceManagerStatus'
        Success  = $true
        Severity = 'INFO'
        Error    = ''
    }
}