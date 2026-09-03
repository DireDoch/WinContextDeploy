# CLAUDE.md

Notes for whoever - or whatever - works on this repo next.

## Running PowerShell and the tests on Linux

The tool targets Windows PowerShell 5.1 and CI runs on `windows-latest`, but
the test suite is almost entirely mocked, so it runs on Linux under PowerShell
7. That is the fast feedback loop; CI is still the authority.

Nothing here needs `sudo`. PowerShell ships as a self-contained tarball:

```bash
mkdir -p ~/.local/opt/powershell ~/.local/bin
curl -fsSL https://github.com/PowerShell/PowerShell/releases/download/v7.6.5/powershell-7.6.5-linux-x64.tar.gz \
  | tar -xz -C ~/.local/opt/powershell
chmod +x ~/.local/opt/powershell/pwsh
ln -sf ~/.local/opt/powershell/pwsh ~/.local/bin/pwsh

pwsh -NoProfile -c "Install-Module Pester -RequiredVersion 5.7.1 -Force -SkipPublisherCheck -Scope CurrentUser"
pwsh -NoProfile -c "Install-Module PSScriptAnalyzer -Force -SkipPublisherCheck -Scope CurrentUser"
```

Pin Pester to 5.7.1: that is the version CI installs, and Pester 6 changes
enough of the assertion surface to disagree with it.

Run what CI runs:

```bash
pwsh -NoProfile -c "Import-Module Pester -RequiredVersion 5.7.1; Invoke-Pester ./tests/*.Tests.ps1 -Output Detailed"
pwsh -NoProfile -c "Import-Module PSScriptAnalyzer; Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1"
```

One file only, which is what you want while iterating:

```bash
pwsh -NoProfile -c "Import-Module Pester -RequiredVersion 5.7.1; Invoke-Pester ./tests/Config-Network.Tests.ps1 -Output Detailed"
```

### Two tests fail on Linux, and are meant to

They reach cmdlets that only exist on Windows and cannot be mocked away,
because Pester's `Mock` needs the command to exist before it can replace it:

| Test | Missing cmdlet |
|---|---|
| `Config-Language.ajoute la langue fallback dans la liste utilisateur` | `New-WinUserLanguageList` |
| `WcdHelpers.ajoute un bloc historique a la fin du log cumule avec le diagnostic final` | `Get-CimInstance` |

So a clean Linux run is **2 failed**. Any third failure is yours. Compare
against `main` before believing otherwise:

```bash
git stash -u && git checkout main
pwsh -NoProfile -c "Import-Module Pester -RequiredVersion 5.7.1; (Invoke-Pester ./tests/*.Tests.ps1 -Output None -PassThru).FailedCount"
git checkout - && git stash pop
```

### Debugging a single function

The Modules dot-source cleanly, so you can poke at one in isolation:

```bash
pwsh -NoProfile -c ". ./src/WcdHelpers.ps1; . ./src/Config-Network.ps1; Test-WcdRelevantNetworkAdapter -Adapter ([pscustomobject]@{ Name = 'vEthernet' })"
```

`src/WcdDiagnostic.ps1` reads `\$T` from script scope, so set it first:

```bash
pwsh -NoProfile -c ". ./src/WcdHelpers.ps1; \$T = @{ MissingModuleData = 'x' }; . ./src/WcdDiagnostic.ps1; Get-WcdSeverityRank -Severity 'WARNING'"
```

`src/Invoke-WcdConfiguration.ps1` cannot be dot-sourced - it runs the whole
run and exits. That is why the Diagnostic lives in its own file.

## Line endings

`.gitattributes` checks `*.ps1` and `*.psd1` out as CRLF and stores them as LF.
Tools that rewrite these files must preserve CRLF in the working tree, or every
line shows up in the diff.
