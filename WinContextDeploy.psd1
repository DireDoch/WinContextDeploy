# =============================================================================
# WinContextDeploy.psd1
# =============================================================================
# Fichier de configuration statique pour WinContextDeploy.
# Contient tous les chemins, URLs et parametres externes utilises par les
# scripts de configuration. Modifier ici plutot que dans les scripts.
#
# Format: PowerShell Data File (.psd1) — charge avec Import-PowerShellDataFile
# =============================================================================

@{

    # =========================================================================
    # PRINCIPAL — Chemins specifiques au mode poste principal
    # =========================================================================
    Principal = @{
        # Dossier SAP Front End dans le menu Demarrer (ouvrir dans l'explorateur)
        SAPPath      = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\SAP Front End'

        # Point d'entree AS400 / IBM i Access pour verification du poste principal
        AS400Path    = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\IBM i Access Client Solutions'

        # Dossier Programs general (ouvrir dans l'explorateur)
        ProgramsPath = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs'
    }

    # =========================================================================
    # CITRIX — Mode poste secondaire
    # =========================================================================
    Citrix = @{
        # URL de telechargement de Citrix Workspace
        DownloadUrl = 'https://www.citrix.com/downloads/workspace-app/'
    }

    # =========================================================================
    # APPLICATIONS — Applications communes a ouvrir (Principal ET Citrix)
    # =========================================================================
    Applications = @{
        # Software Center (Microsoft Configuration Manager)
        SoftwareCenter = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Microsoft Configuration Manager\Configuration Manager\Software Center.lnk'

        # Outlook classique
        Outlook        = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Outlook (classic).lnk'

        # Google Chrome — ouverture du raccourci pour lancer le navigateur par defaut du script
        ChromePath     = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Google Chrome.lnk'

        # Microsoft Teams — lancement direct via executable
        TeamsExe       = 'ms-teams.exe'

        # Outil Capture (Snipping Tool) — lancement direct via executable
        SnipItExe      = 'snippingtool'

        # GlobalProtect — noms de processus a verifier dans le gestionnaire des taches
        # PanGPA.exe est le processus principal de GlobalProtect; les PIDs sont dynamiques donc on detecte par nom.
        GlobalProtectProcessNames = @('PanGPA', 'PanGPS')

        # Micro Focus — ouvrir dans l'explorateur SEULEMENT si present
        MicroFocus     = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Micro Focus'

        # Portail My IT Support (lien web)
        ServiceNowUrl  = 'https://example.service-now.com/sp'
 
    }

    # =========================================================================
    # ENGINEER — Configuration ordinateur d'ingenieur
    # =========================================================================
    Engineer = @{
        # URL de telechargement Nvidia App
        NvidiaUrl  = 'https://www.nvidia.com/en-eu/software/nvidia-app/'

        # Fleet/GPS portal URL (site-specific — replace with your own)
        GPSUrl     = 'https://gps.example.com/client/publish.htm'

        # Chemin vers Chrome dans le menu Demarrer (fallback: ouvre directement l'URL)
        ChromePath = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Google Chrome.lnk'

        # Autovue
        AutovuePath = 'C:\Program Files (x86)\av\avwin\avwin.exe'
    }

    # =========================================================================
    # PRINTER — Ajout d'imprimante
    # =========================================================================
    Printer = @{
        # Raccourci Find and add Printer dans le menu Demarrer
        PrintManagerPath = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Find and add Printer.lnk'
    }
}
