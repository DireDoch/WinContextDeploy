# Config-Printer.ps1 - connects the shared print queues from the manifest.
# Entry point: Set-WcdPrinterConfiguration. Requires WcdHelpers.ps1.
#
# Shared print-server queues only. Direct-IP printers need Add-PrinterPort and
# a driver in the driver store, which is a bigger surface.

function Get-WcdPrinter {
    <#
    .SYNOPSIS
        Returns the installed printer with the given name, or $null.

    .DESCRIPTION
        Thin wrapper over Get-Printer so the idempotency check has a seam the
        tests can mock on a machine with no print spooler.

    .PARAMETER Name
        Printer queue name.

    .OUTPUTS
        The printer object, or $null when it is not installed.

    .EXAMPLE
        if (Get-WcdPrinter -Name 'Floor-4-Colour') { 'already connected' }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    return (Get-Printer -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Add-WcdPrinterConnection {
    <#
    .SYNOPSIS
        Connects a shared print-server queue.

    .DESCRIPTION
        Thin wrapper over Add-Printer -ConnectionName. For a shared queue the
        connection name is all that is needed: the driver comes from the print
        server.

    .PARAMETER ConnectionName
        UNC path of the queue, e.g. '\\printserver\Floor-4-Colour'.

    .OUTPUTS
        None. Throws when the server is unreachable or the queue is unknown.

    .EXAMPLE
        Add-WcdPrinterConnection -ConnectionName '\\printserver\Floor-4-Colour'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConnectionName
    )

    Add-Printer -ConnectionName $ConnectionName -ErrorAction Stop
}

function Set-WcdPrinterConfiguration {
    <#
    .SYNOPSIS
        Connects the shared print-server queues declared in the manifest.

    .DESCRIPTION
        Idempotent: a queue already installed is checked with Get-Printer and left
        alone. An unreachable print server is an actionable warning, never a crash,
        and an empty Printers array returns nothing at all so the Module is skipped
        and printers stay a Manual Step.

    .PARAMETER Config
        The imported manifest. Only its Printers array is read.

    .PARAMETER LogPath
        Full path to the log file. Resolved automatically when omitted.

    .PARAMETER ProgressCallback
        Scriptblock invoked at the start and end of each step for progress display.

    .OUTPUTS
        [pscustomobject[]] with Step, Success, Error, Severity and, on a failure,
        RemedyKey and RemedyArgs. One result per printer.

    .EXAMPLE
        Set-WcdPrinterConfiguration -Config $config -LogPath 'C:\temp\log.txt'
    #>
    [CmdletBinding()]
    param(
        [hashtable]$Config,
        [string]$LogPath,
        [scriptblock]$ProgressCallback
    )

    $resolvedLogPath = Resolve-WcdLogPath -CandidatePath $LogPath
    $moduleName = 'Config-Printer'
    $printers = @(Get-WcdPrinterTarget -Config $Config)

    # No printers declared: nothing to do, and nothing to warn about.
    if ($printers.Count -eq 0) {
        return @()
    }

    $results = @()
    foreach ($printer in $printers) {
        $name = [string]$printer.Name
        $connection = [string]$printer.Connection
        $step = Get-WcdPrinterStepKey -Name $name

        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey $step -Event 'Start'

        try {
            if ($null -ne (Get-WcdPrinter -Name $name)) {
                Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('Printer: {0} already connected.' -f $name)
                Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey $step -Event 'Finish' -Kind 'success'
                $results += [pscustomobject]@{ Step = $step; Success = $true; Error = ''; Severity = 'INFO' }
                continue
            }

            Add-WcdPrinterConnection -ConnectionName $connection
            Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message ('Printer: {0} connected via {1}.' -f $name, $connection)
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey $step -Event 'Finish' -Kind 'success'
            $results += [pscustomobject]@{ Step = $step; Success = $true; Error = ''; Severity = 'INFO' }
        } catch {
            # An unreachable print server is common on a machine that is not on
            # the corporate network yet, so it is a warning the technician can
            # act on, never a crash.
            $message = $_.Exception.Message
            Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message ('Printer {0}: {1}' -f $name, $message)
            Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback -ModuleName $moduleName -StepKey $step -Event 'Finish' -Kind 'warning'
            $results += [pscustomobject]@{
                Step       = $step
                Success    = $true
                Error      = $message
                Severity   = 'WARNING'
                RemedyKey  = 'PrinterUnreachable'
                RemedyArgs = @($connection, $name)
            }
        }
    }

    return $results
}

function Get-WcdPrinterDescriptor {
    <#
    .SYNOPSIS
        Declares what Config-Printer contributes to the run.

    .DESCRIPTION
        One Step per queue declared in the manifest, folded into one row. A
        manifest declaring no queue plans nothing, the Module is skipped, and
        printers stay a Manual Step the Diagnostic raises at the end.

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
        Get-WcdPrinterDescriptor -ExecutionOptions $options -Config $config -Translations $T
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

    $printers = @(Get-WcdPrinterTarget -Config $Config)
    $steps = @($printers | ForEach-Object {
        @{ Key = (Get-WcdPrinterStepKey -Name ([string]$_.Name)); Label = [string]$_.Name }
    })

    return [pscustomobject]@{
        Name     = 'Config-Printer'
        Order    = 120
        RowOrder = 120
        Steps    = $steps
        Rows     = @(if ($steps.Count -gt 0) {
            @{ Label = $Translations.Checklist.Printers; Steps = @($steps | ForEach-Object { $_.Key }) }
        })
        Invoke   = {
            param($ctx)

            Set-WcdPrinterConfiguration -Config $ctx.Config -LogPath $ctx.LogPath -ProgressCallback $ctx.ProgressCallback
        }
    }
}