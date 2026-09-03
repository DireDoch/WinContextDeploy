# Config-TaskbarLeft.ps1 - aligns the taskbar left and hides the Task View button.
# Entry point: Set-WcdTaskbarLeft. Requires WcdHelpers.ps1.

function Set-WcdTaskbarLeft {
    <#
    .SYNOPSIS
        Aligns the taskbar to the left and hides the Task View button.

    .DESCRIPTION
        Two HKCU writes under Explorer\Advanced, so they work unelevated. A key
        locked by Group Policy is reported with a remediation rather than a raw
        access-denied message.

    .PARAMETER LogPath
        Full path to the log file. Resolved automatically when omitted.

    .PARAMETER ProgressCallback
        Scriptblock invoked at the start and end of each step for progress display.

    .OUTPUTS
        [pscustomobject[]] with Step, Success, Error and, on a failure, RemedyKey.

    .EXAMPLE
        Set-WcdTaskbarLeft -LogPath 'C:\temp\log.txt'
    #>
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
        $remedyKey = 'RegistryWriteFailed'
        if ($_.Exception -is [System.UnauthorizedAccessException] -or $note -match 'non autorisee|access is denied|unauthorized') {
            $note = 'Registry key locked by GPO or access denied.'
            $remedyKey = 'RegistryGpo'
        }
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ("Taskbar align: {0}" -f $note)
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'TaskbarAlignLeft' -Event 'Finish' -Kind 'error'
        $results += [pscustomobject]@{ Step = 'TaskbarAlignLeft'; Success = $false; Error = $note; RemedyKey = $remedyKey }
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
        $remedyKey = 'RegistryWriteFailed'
        if ($_.Exception -is [System.UnauthorizedAccessException] -or $note -match 'non autorisee|access is denied|unauthorized') {
            $note = 'Registry key locked by GPO or access denied.'
            $remedyKey = 'RegistryGpo'
        }
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ("Taskbar task view: {0}" -f $note)
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'DisableTaskView' -Event 'Finish' -Kind 'error'
        $results += [pscustomobject]@{ Step = 'DisableTaskView'; Success = $false; Error = $note; RemedyKey = $remedyKey }
    }

    return $results
}

function Get-WcdTaskbarLeftDescriptor {
    <#
    .SYNOPSIS
        Declares what Config-TaskbarLeft contributes to the run.

    .DESCRIPTION
        Two Steps folded into one row: the technician reads the taskbar as one thing.

        A Module declares itself here instead of in six places across the
        orchestrator and the helpers. See Test-WcdModuleDescriptor in
        WcdHelpers.ps1 for the contract.

    .PARAMETER ExecutionOptions
        Resolved run options: Language, FormFactor, Environment, OpenApps,
        OptionalTools, NewComputerName and JoinDomain.

    .PARAMETER Config
        The imported manifest.

    .PARAMETER Translations
        The active $T table, for the checklist row labels.

    .OUTPUTS
        [pscustomobject] with Name, Order, RowOrder, Steps, Rows and Invoke.

    .EXAMPLE
        Get-WcdTaskbarLeftDescriptor -ExecutionOptions $options -Config $config -Translations $T
    #>
    # The signature is a contract: the orchestrator calls all twelve descriptors
    # the same way, so each declares all three parameters even when it reads one.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
        Justification = 'Uniform descriptor signature; the orchestrator calls every Module identically.')]
    [CmdletBinding()]
    param(
        [pscustomobject]$ExecutionOptions,

        [hashtable]$Config,

        [hashtable]$Translations
    )

    return [pscustomobject]@{
        Name     = 'Config-TaskbarLeft'
        Order    = 40
        RowOrder = 20
        Steps    = @(
            @{ Key = 'TaskbarAlignLeft'; Label = 'Taskbar aligned left' }
            @{ Key = 'DisableTaskView';  Label = 'Task view disabled' }
        )
        Rows     = @(
            @{ Label = $Translations.Checklist.Taskbar; Steps = @('TaskbarAlignLeft', 'DisableTaskView') }
        )
        Invoke   = {
            param($ctx)

            Set-WcdTaskbarLeft -LogPath $ctx.LogPath -ProgressCallback $ctx.ProgressCallback
        }
    }
}