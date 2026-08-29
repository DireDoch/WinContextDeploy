# =============================================================================
# WinContextDeploy.psd1
# =============================================================================
# Every environment-specific value lives here. Edit this file rather than the
# scripts in src/ — adding, removing or reordering an application never
# requires a code change.
#
# Format: PowerShell Data File — loaded with Import-PowerShellDataFile
# =============================================================================

@{

    # =========================================================================
    # APPLICATIONS
    # =========================================================================
    # An ordered list of things to verify or open. WinContextDeploy never
    # installs software: applications are expected to arrive through your
    # imaging pipeline, and this list confirms they are present and puts the
    # ones a technician must eyeball in front of them.
    #
    # Each entry supports:
    #
    #   Step        Stable identifier used in logs and the JSON report.
    #               Must be unique. Required.
    #   Name        What the technician sees in the checklist. Required.
    #   Action      One of:
    #                 Launch        start an application (.lnk, .exe, or a
    #                               command on PATH)
    #                 OpenFolder    open a folder in Explorer
    #                 OpenUrl       open a URL in the default browser
    #                 CheckProcess  verify a process is running, launch nothing
    #                               (Target is an array of process names)
    #                 CheckPath     verify a path exists, launch nothing
    #   Target      Path, URL, command, or array of process names. Required.
    #   Environment Restrict to 'Workstation' or 'Vdi'. Omit to always apply.
    #   FormFactor  Restrict to 'Laptop' or 'Desktop'. Omit to always apply.
    #   Optional    $true  -> absence is reported as a note, not a warning.
    #   Prompt      $true  -> not run automatically; offered in the optional
    #                         tools menu instead (see below).
    #
    # The entries below are examples covering every Action. Replace them with
    # your own — the shipped defaults are deliberately generic.
    # =========================================================================
    Applications = @(

        @{
            Step   = 'AppSoftwareCenter'
            Name   = 'Software Center'
            Action = 'Launch'
            Target = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Microsoft Configuration Manager\Configuration Manager\Software Center.lnk'
            Optional = $true
        }

        @{
            Step   = 'AppOutlook'
            Name   = 'Outlook'
            Action = 'Launch'
            Target = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Outlook (classic).lnk'
            Optional = $true
        }

        @{
            Step   = 'AppTeams'
            Name   = 'Teams'
            Action = 'Launch'
            Target = 'ms-teams.exe'
        }

        @{
            Step   = 'AppSnippingTool'
            Name   = 'Snipping Tool'
            Action = 'Launch'
            Target = 'snippingtool'
        }

        # Verify the VPN client is running without launching anything.
        # Target is a list of process names; any one of them counts as running.
        @{
            Step   = 'AppVpn'
            Name   = 'VPN client'
            Action = 'CheckProcess'
            Target = @('PanGPA', 'PanGPS')
            Optional = $true
        }

        @{
            Step   = 'AppHelpdesk'
            Name   = 'Helpdesk portal'
            Action = 'OpenUrl'
            Target = 'https://example.service-now.com/sp'
        }

        # --- Local workstations only -----------------------------------------
        # On a VDI endpoint these live in the remote session, so the checklist
        # marks them Not Applicable rather than warning about them.

        @{
            Step        = 'AppErpClient'
            Name        = 'ERP client'
            Action      = 'OpenFolder'
            Target      = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\SAP Front End'
            Environment = 'Workstation'
            Optional    = $true
        }

        @{
            Step        = 'AppTerminalEmulator'
            Name        = 'Terminal emulator'
            Action      = 'CheckPath'
            Target      = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\IBM i Access Client Solutions'
            Environment = 'Workstation'
            Optional    = $true
        }

        @{
            Step        = 'AppCadViewer'
            Name        = 'CAD viewer'
            Action      = 'CheckPath'
            Target      = 'C:\Program Files (x86)\av\avwin\avwin.exe'
            Environment = 'Workstation'
            Optional    = $true
        }

        # --- VDI endpoints only ----------------------------------------------

        @{
            Step        = 'AppVdiWorkspace'
            Name        = 'Citrix Workspace'
            Action      = 'OpenUrl'
            Target      = 'https://www.citrix.com/downloads/workspace-app/'
            Environment = 'Vdi'
        }

        # --- Optional tools --------------------------------------------------
        # Entries with Prompt = $true are never run automatically. The
        # technician is asked whether this is an engineering workstation and,
        # if so, picks which of these to run. Use this for the extras a CAD or
        # engineering machine needs that a standard desk does not.

        @{
            Step   = 'AppNvidia'
            Name   = 'NVIDIA App'
            Action = 'OpenUrl'
            Target = 'https://www.nvidia.com/en-eu/software/nvidia-app/'
            Prompt = $true
        }

        # @{
        #     Step   = 'AppFleetTelemetry'
        #     Name   = 'Fleet telemetry portal'
        #     Action = 'OpenUrl'
        #     Target = 'https://telemetry.example.com/client/'
        #     Prompt = $true
        # }
    )

    # =========================================================================
    # PRINTERS
    # =========================================================================
    # Shared print-server queues to connect. Leave empty to skip entirely.
    #
    #   Printers = @(
    #       @{ Name = 'Floor-4-Colour'; Connection = '\\printserver\Floor-4-Colour' }
    #   )
    # =========================================================================
    Printers = @()
}
