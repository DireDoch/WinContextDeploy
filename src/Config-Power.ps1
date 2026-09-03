# Config-Power.ps1 - screen timeouts, lid-close action, and the active scheme.
# Entry point: Set-WcdPowerConfiguration. Requires WcdHelpers.ps1.
#
# The only Module that needs Administrator. Unelevated, it reports what would
# have needed it rather than failing.

function Set-WcdPowerConfiguration {
    <#
    .SYNOPSIS
        Applies the screen timeouts, the lid-close action and the active power scheme.

    .DESCRIPTION
        Drives powercfg.exe from a step table. The battery and lid steps apply to a
        Laptop only; on a Desktop they are Not Applicable, not skipped.

        The sleep steps (standby-timeout-*) are deliberately left out - they are
        blocked by Group Policy in the environments this tool was built for. The
        commented rows in the step table are what to restore if that changes.

        powercfg needs Administrator. An unelevated run attempts nothing: every
        step reports as a warning saying to relaunch elevated, which is a far more
        useful diagnostic than five raw exit codes.

    .PARAMETER FormFactor
        'Laptop' or 'Desktop'. Battery and lid steps apply to a Laptop only.
        Defaults to 'Laptop'.

    .PARAMETER Elevated
        Whether the run holds Administrator rights. When $false no powercfg call is
        attempted. Defaults to $true.

    .PARAMETER LogPath
        Full path to the log file. Resolved automatically when omitted.

    .PARAMETER ProgressCallback
        Scriptblock invoked at the start and end of each step for progress display.

    .OUTPUTS
        [pscustomobject[]] with Step, Success, Error and, on a failure, Severity
        and RemedyKey.

    .EXAMPLE
        Set-WcdPowerConfiguration -FormFactor 'Laptop' -LogPath 'C:\temp\log.txt'

    .EXAMPLE
        # Unelevated: reports what would need Administrator instead of failing
        Set-WcdPowerConfiguration -FormFactor 'Desktop' -Elevated $false
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Laptop', 'Desktop')]
        [string]$FormFactor = 'Laptop',

        [bool]$Elevated = $true,

        [string]$LogPath,

        [scriptblock]$ProgressCallback
    )

    $resolvedLogPath = Resolve-WcdLogPath -CandidatePath $LogPath
    $results = @()
    $moduleName = 'Config-Power'
    $laptopOnly = ($FormFactor -eq 'Laptop')

    $steps = @(
        @{ Step = 'ScreenTimeoutBattery'; LaptopOnly = $true;  Log = 'Power: screen timeout on battery set to 10 min.'; Fail = 'Screen timeout on battery'
           Arguments = @('/change', 'monitor-timeout-dc', '10') }

        @{ Step = 'ScreenTimeoutAc';      LaptopOnly = $false; Log = 'Power: screen timeout on AC set to 15 min.';      Fail = 'Screen timeout on AC'
           Arguments = @('/change', 'monitor-timeout-ac', '15') }

        # BLOCKED BY GPO: the standby-timeout steps are deliberately disabled.
        # @{ Step = 'SleepAcNever';      LaptopOnly = $false; Log = 'Power: sleep on AC set to never.';      Fail = 'Sleep on AC'
        #    Arguments = @('/change', 'standby-timeout-ac', '0') }
        # @{ Step = 'SleepBatteryNever'; LaptopOnly = $true;  Log = 'Power: sleep on battery set to never.'; Fail = 'Sleep on battery'
        #    Arguments = @('/change', 'standby-timeout-dc', '0') }

        @{ Step = 'LidActionAcNone';      LaptopOnly = $true;  Log = 'Power: lid close on AC set to do nothing.';      Fail = 'Lid close on AC'
           Arguments = @('/setacvalueindex', 'SCHEME_CURRENT', 'SUB_BUTTONS', 'LIDACTION', '0') }

        @{ Step = 'LidActionBatteryNone'; LaptopOnly = $true;  Log = 'Power: lid close on battery set to do nothing.'; Fail = 'Lid close on battery'
           Arguments = @('/setdcvalueindex', 'SCHEME_CURRENT', 'SUB_BUTTONS', 'LIDACTION', '0') }

        @{ Step = 'SetActiveSchemeCurrent'; LaptopOnly = $false; Log = 'Power: active scheme applied.'; Fail = 'Apply active scheme'
           Arguments = @('/setactive', 'SCHEME_CURRENT') }
    )

    foreach ($step in $steps) {
        if ($step.LaptopOnly -and -not $laptopOnly) { continue }

        $key = [string]$step.Step
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey $key -Event 'Start'

        if (-not $Elevated) {
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('{0}: skipped, powercfg requires Administrator.' -f $step.Fail)
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey $key -Event 'Finish' -Kind 'warning'
            $results += [pscustomobject]@{
                Step      = $key
                Success   = $true
                Error     = 'powercfg requires Administrator.'
                Severity  = 'WARNING'
                RemedyKey = 'RequiresAdmin'
            }
            continue
        }

        try {
            $powerCfgArguments = @($step.Arguments)
            Invoke-WcdPowerCfg @powerCfgArguments
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ([string]$step.Log)
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey $key -Event 'Finish' -Kind 'success'
            $results += [pscustomobject]@{ Step = $key; Success = $true; Error = '' }
        } catch {
            Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ('{0}: {1}' -f $step.Fail, $_.Exception.Message)
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey $key -Event 'Finish' -Kind 'error'
            $results += [pscustomobject]@{
                Step      = $key
                Success   = $false
                Error     = $_.Exception.Message
                RemedyKey = 'PowerCfgFailed'
            }
        }
    }

    return $results
}

function Get-WcdPowerDescriptor {
    <#
    .SYNOPSIS
        Declares what Config-Power contributes to the run.

    .DESCRIPTION
        Five Steps on a Laptop and two on a Desktop. The battery and lid Steps are
        Not Applicable to a Desktop, so they are declared but not planned - the
        label survives for the diagnostic, the progress bar cannot overshoot.

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
        Get-WcdPowerDescriptor -ExecutionOptions $options -Config $config -Translations $T
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

    $laptop = ($ExecutionOptions.FormFactor -eq 'Laptop')

    $steps = @(
        @{ Key = 'ScreenTimeoutBattery';   Label = 'Screen timeout on battery';       Planned = $laptop }
        @{ Key = 'ScreenTimeoutAc';        Label = 'Screen timeout on AC';            Planned = $true }
        @{ Key = 'LidActionAcNone';        Label = 'Lid close on AC: do nothing';     Planned = $laptop }
        @{ Key = 'LidActionBatteryNone';   Label = 'Lid close on battery: do nothing'; Planned = $laptop }
        @{ Key = 'SetActiveSchemeCurrent'; Label = 'Active power scheme';             Planned = $true }
    )

    return [pscustomobject]@{
        Name     = 'Config-Power'
        Order    = 20
        RowOrder = 50
        Steps    = $steps
        Rows     = @(
            @{ Label = $Translations.Checklist.Power
               Steps = @($steps | Where-Object { $_.Planned } | ForEach-Object { $_.Key }) }
        )
        Invoke   = {
            param($ctx)

            Set-WcdPowerConfiguration -FormFactor $ctx.ExecutionOptions.FormFactor -Elevated $ctx.Elevated `
                -LogPath $ctx.LogPath -ProgressCallback $ctx.ProgressCallback
        }
    }
}