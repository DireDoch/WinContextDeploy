# Config-Decimal.ps1 - forces the decimal and currency separators to a period.
# Entry point: Set-WcdDecimalConfiguration. Requires WcdHelpers.ps1.

function Set-WcdDecimalThreadCulture {
    <#
    .SYNOPSIS
        Applies the separators to the current PowerShell thread's culture.

    .DESCRIPTION
        The registry write only takes effect for processes started afterwards, so
        the running session is updated too - otherwise the rest of this run would
        still format numbers the old way.

    .PARAMETER DecimalSeparator
        Decimal separator to apply, e.g. '.'.

    .PARAMETER ThousandsSeparator
        Thousands separator to apply, e.g. ','.

    .OUTPUTS
        None.

    .EXAMPLE
        Set-WcdDecimalThreadCulture -DecimalSeparator '.' -ThousandsSeparator ','
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DecimalSeparator,

        [Parameter(Mandatory)]
        [string]$ThousandsSeparator
    )

    $culture = [System.Globalization.CultureInfo]::CurrentCulture.Clone()
    $culture.NumberFormat.NumberDecimalSeparator = $DecimalSeparator
    $culture.NumberFormat.CurrencyDecimalSeparator = $DecimalSeparator
    $culture.NumberFormat.NumberGroupSeparator = $ThousandsSeparator
    $culture.NumberFormat.CurrencyGroupSeparator = $ThousandsSeparator

    [System.Threading.Thread]::CurrentThread.CurrentCulture = $culture
    [System.Threading.Thread]::CurrentThread.CurrentUICulture = $culture

    if ([System.Threading.Thread].GetProperty('DefaultThreadCurrentCulture')) {
        [System.Threading.Thread]::DefaultThreadCurrentCulture = $culture
        [System.Threading.Thread]::DefaultThreadCurrentUICulture = $culture
    }
}

function Set-WcdDecimalConfiguration {
    <#
    .SYNOPSIS
        Forces the decimal and currency separators to a period.

    .DESCRIPTION
        Writes HKCU:\Control Panel\International, then updates the running
        session's culture to match. This is an HKCU write, so it works unelevated;
        a key locked by Group Policy is reported with a remediation saying the
        change has to come from Group Policy instead.

    .PARAMETER LogPath
        Full path to the log file. Resolved automatically when omitted.

    .PARAMETER ProgressCallback
        Scriptblock invoked at the start and end of each step for progress display.

    .OUTPUTS
        [pscustomobject] with Step, Success, LogPath, Error and, on a failure,
        RemedyKey.

    .EXAMPLE
        Set-WcdDecimalConfiguration -LogPath 'C:\temp\log.txt'
    #>
    [CmdletBinding()]
    param(
        [string]$LogPath,
        [scriptblock]$ProgressCallback
    )

    $resolvedLogPath = Resolve-WcdLogPath -CandidatePath $LogPath
    $intlPath = 'HKCU:\Control Panel\International'
    $moduleName = 'Config-Decimal'

    try {
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'DecimalAndCurrency' -Event 'Start'
        Set-WcdRegistryValue -Path $intlPath -Name 'sDecimal' -Value '.'
        Set-WcdRegistryValue -Path $intlPath -Name 'sThousandSep' -Value ','
        Set-WcdRegistryValue -Path $intlPath -Name 'sMonDecimalSep' -Value '.'
        Set-WcdRegistryValue -Path $intlPath -Name 'sMonetaryDecimal' -Value '.'
        Set-WcdRegistryValue -Path $intlPath -Name 'sMonThousandSep' -Value ','
        Set-WcdDecimalThreadCulture -DecimalSeparator '.' -ThousandsSeparator ','
        Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'Regional: decimal and currency separators forced to a period.'
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'DecimalAndCurrency' -Event 'Finish' -Kind 'success'

        return [pscustomobject]@{
            Step    = 'DecimalAndCurrency'
            Success = $true
            LogPath = $resolvedLogPath
            Error   = ''
        }
    } catch {
        $note = $_.Exception.Message
        $remedyKey = 'RegistryWriteFailed'
        if ($_.Exception -is [System.UnauthorizedAccessException] -or $note -match 'non autorisee|access is denied|unauthorized') {
            $note = 'Registry key locked by GPO or access denied.'
            $remedyKey = 'RegistryGpo'
        }
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ("Regional: {0}" -f $note)
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey 'DecimalAndCurrency' -Event 'Finish' -Kind 'error'

        return [pscustomobject]@{
            Step      = 'DecimalAndCurrency'
            Success   = $false
            LogPath   = $resolvedLogPath
            Error     = $note
            RemedyKey = $remedyKey
        }
    }
}

function Get-WcdDecimalDescriptor {
    <#
    .SYNOPSIS
        Declares what Config-Decimal contributes to the run.

    .DESCRIPTION
        One Step, one row.

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
        Get-WcdDecimalDescriptor -ExecutionOptions $options -Config $config -Translations $T
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
        Name     = 'Config-Decimal'
        Order    = 30
        RowOrder = 40
        Steps    = @(
            @{ Key = 'DecimalAndCurrency'; Label = 'Decimal and currency' }
        )
        Rows     = @(
            @{ Label = $Translations.Checklist.Decimal; Steps = @('DecimalAndCurrency') }
        )
        Invoke   = {
            param($ctx)

            Set-WcdDecimalConfiguration -LogPath $ctx.LogPath -ProgressCallback $ctx.ProgressCallback
        }
    }
}