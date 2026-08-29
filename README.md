# WinContextDeploy

Interactive PowerShell tool for post-image configuration of Windows 11 machines.

A technician runs it once on a freshly imaged machine. It applies OS settings that
depend on the machine's context, opens the applications that need to be checked by
eye, and prints a checklist of what was done, what was skipped, and what still has
to be done by hand.

It does **not** install software. Applications are expected to arrive through your
imaging pipeline; this tool verifies they are there and puts them in front of the
technician.

> Running this changes system settings (taskbar, regional separators, power plan,
> keyboard/language). Read `WinContextDeploy.psd1` and adjust the paths to your
> environment before first use.

## Requirements

- Windows 10/11, PowerShell 5.1 or later
- Administrator rights for the power-plan steps (everything else runs unelevated)
- [Pester](https://pester.dev/) 5.x, only if you want to run the tests

## Usage

Double-click `Lancer-WinContextDeploy.cmd` (French UI) or
`Start-WinContextDeploy.cmd` (English UI), then answer the prompts. Use the
left/right arrow keys to change a choice and Enter to confirm.

| Prompt | Choices | Default |
|---|---|---|
| Windows system language | `fr-CA` / `en-US` | `fr-CA` |
| Form factor | `Laptop` / `Desktop` | `Laptop` |
| Environment | `Workstation` (local) / `Vdi` (Citrix) | `Workstation` |
| Open configuration applications | Yes / No | Yes |
| Engineer workstation | Yes / No | No |

The last prompt appears only when the manifest declares at least one `Prompt`
entry.

Form factor selects the power profile — battery and lid-close settings apply to
laptops only. Environment selects which applications are relevant: a `Vdi`
endpoint skips the locally installed line-of-business checks, since those live in
the remote session.

Prompts are shown in the UI language (`-ScriptUI FR|EN`), so a French run offers
*Portable* / *Bureau* and *Principal* / *Secondaire* with their usual shortcut
keys, while the values above are what the code and logs use.

Or run it directly:

```powershell
powershell -ExecutionPolicy Bypass -File .\src\Invoke-WcdConfiguration.ps1
powershell -ExecutionPolicy Bypass -File .\src\Invoke-WcdConfiguration.ps1 `
    -Language en-US -FormFactor Desktop -Environment Workstation -NonInteractive
```

## Configuration

Everything environment-specific lives in `WinContextDeploy.psd1`. Adding,
removing or reordering an application is a manifest edit — no code changes.

Each entry in `Applications` declares what to do and what to do it to:

```powershell
@{
    Step        = 'AppErpClient'      # stable id, used in logs and reports
    Name        = 'ERP client'        # what the technician sees
    Action      = 'OpenFolder'        # see table below
    Target      = 'C:\ProgramData\...\SAP Front End'
    Environment = 'Workstation'       # optional: 'Workstation' or 'Vdi'
    FormFactor  = 'Laptop'            # optional: 'Laptop' or 'Desktop'
    Optional    = $true               # absent -> note, not a warning
    Prompt      = $true               # offer in the optional tools menu
}
```

| Action | Effect |
|---|---|
| `Launch` | Starts an application (`.lnk`, `.exe`, or a command on `PATH`) |
| `OpenFolder` | Opens a folder in Explorer |
| `OpenUrl` | Opens a URL in the default browser |
| `CheckProcess` | Verifies a process is running; `Target` is an array of names |
| `CheckPath` | Verifies a path exists; launches nothing |

`Environment` and `FormFactor` filter an entry to matching machines. A filtered-out
target is reported **Not Applicable** in the checklist rather than omitted, so the
technician can see it was considered.

`Prompt = $true` keeps an entry out of the automatic run and offers it in the
optional-tools menu instead — for the extras an engineering or CAD workstation
needs that a standard desk does not.

`Printers` lists shared print-server queues to connect. Leave it empty to skip.

## Branding

The startup logo is read from `banner.txt` at the project root. To use your own,
generate ASCII art at [patorjk.com/software/taag](https://patorjk.com/software/taag/)
and paste it into that file. If the file is missing, or the art is wider than the
console window, a plain text title is shown instead.

## Logs

- A timestamped log is written during the run (`src/log.txt` by default;
  override with `-LogPath`).
- With `-HistoryLogPath`, a summary block is appended to a second file at the end
  of the run — useful for keeping one running record across every machine you
  configure.

## Tests

```powershell
Invoke-Pester .\tests\*.Tests.ps1 -Output Detailed
```

Or double-click `Lancer-Tests-Pester.cmd`.

## Structure

```
banner.txt                        <- startup logo (editable)
WinContextDeploy.psd1             <- paths and URLs (edit this)
Lancer-WinContextDeploy.cmd       <- entry point, French UI
Start-WinContextDeploy.cmd        <- entry point, English UI
src/
  Invoke-WcdConfiguration.ps1     <- orchestrator
  WcdHelpers.ps1                  <- shared functions
  Config-*.ps1                    <- configuration modules
tests/
  *.Tests.ps1                     <- Pester tests
```

## License

MIT.
