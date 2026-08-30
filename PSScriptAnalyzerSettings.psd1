# PSScriptAnalyzer settings for WinContextDeploy.
#
# The excluded rules are ones that are wrong for this project rather than ones
# that are inconvenient. Each is justified below; do not add to this list
# without one.

@{
    ExcludeRules = @(
        # This is an interactive console tool. Write-Host is the correct cmdlet
        # for a coloured TUI that a technician reads and never pipes anywhere;
        # Write-Output would pollute the Results the modules return.
        'PSAvoidUsingWriteHost'

        # Modules return [pscustomobject] shapes rather than typed classes, so
        # an OutputType attribute would document nothing the help does not.
        'PSUseOutputTypeCorrectly'

        # Set-Wcd*Configuration functions do change machine state, but they are
        # a run's steps, not a general-purpose API - the tool's own prompts and
        # its -NonInteractive switch are the confirmation surface, and -WhatIf
        # on 40 internal functions would be scaffolding nobody calls.
        'PSUseShouldProcessForStateChangingFunctions'

        # Get-WcdNetworkAdapters and friends return collections and are named
        # for it. Renaming them is churn across every module and test.
        'PSUseSingularNouns'

        # The empty catches are deliberate best-effort lookups: a machine with
        # no BIOS serial or no CIM should degrade to 'Unknown', not fail a run.
        'PSAvoidUsingEmptyCatchBlock'

        # -Event is part of the progress-callback contract every module reports
        # against. Renaming it would touch ~40 call sites for a name collision
        # that only exists inside PowerShell's own eventing cmdlets.
        'PSAvoidAssignmentToAutomaticVariable'
    )
}
