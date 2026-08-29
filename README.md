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
- Administrator rights for the power-plan steps. The tool offers the UAC prompt
  itself; declining is fine, and those steps then report as needing elevation
  instead of failing. `-NonInteractive` never prompts — start the process
  elevated if an unattended run has to apply them.
- [Pester](https://pester.dev/) 5.x, only if you want to run the tests

## Usage

Double-click `WinContextDeploy.cmd`, then answer the prompts. Use the
left/right arrow keys to change a choice and Enter to confirm.

| Option | Effect |
|---|---|
| *(none)* | Run in place. Nothing is copied, nothing is deleted. |
| `-Usb` | Copy the project to `%TEMP%`, run there, append the history log back next to the launcher, then remove the copy. |
| `-FR` / `-EN` | Force the UI language. Defaults from the system locale. |

`-Usb` is for running off a USB key: PowerShell off removable media is slow and
the key can be pulled mid-run. The copy goes to a uniquely named folder under
`%TEMP%`, so concurrent runs cannot collide and no existing folder is ever
wiped.

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

Prompts are shown in the UI language (`-ScriptUI FR|EN`, defaulting from the
system locale), so a French run offers *Portable* / *Bureau* and *Principal* /
*Secondaire* with their usual shortcut keys, while the values above are what the
code and logs use.

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

`Printers` lists shared print-server queues to connect with the built-in
`Add-Printer` cmdlet. Each entry needs a `Name` (as the print server publishes
it) and a `Connection`:

```powershell
Printers = @(
    @{ Name = 'Floor-4-Colour'; Connection = '\\printserver\Floor-4-Colour' }
)
```

Connecting is idempotent, so a second run is a no-op, and an unreachable print
server is reported as a warning rather than failing the run. Leave the array
empty and printers stay a manual checklist row. Shared queues only — a
direct-IP printer needs `Add-PrinterPort` and a driver in the driver store.

`Network.PingTarget` is what the connectivity test pings. It defaults to
`8.8.8.8`; point it at your gateway or an internal host if your network drops
ICMP to the internet.

## Branding

The startup logo is read from `banner.txt` at the project root. To use your own,
generate ASCII art at [patorjk.com/software/taag](https://patorjk.com/software/taag/)
and paste it into that file. If the file is missing, or the art is wider than the
console window, a plain text title is shown instead.

## Logs and reports

- A timestamped log is written during the run (`src/log.txt` by default;
  override with `-LogPath`). It keeps the raw exception text of any failure;
  the checklist on screen shows the remediation instead.
- With `-HistoryLogPath`, a summary block is appended to a second file at the end
  of the run — useful for keeping one running record across every machine you
  configure.
- With `-ReportPath`, a machine-readable JSON summary is also written, for
  collecting results across a fleet. Console output and the text log are
  unchanged, and a report that cannot be written warns without failing the run.

```json
{
  "schemaVersion": 1,
  "timestamp": "2026-08-29T14:31:00-04:00",
  "computerName": "WKS-01",
  "context": { "formFactor": "Laptop", "environment": "Workstation", "elevated": true, "language": "fr-CA" },
  "summary": { "ok": 14, "warning": 1, "error": 0, "manual": 7, "notApplicable": 1 },
  "steps": [
    { "step": "AppErpClient", "name": "ERP client", "kind": "warning", "detail": "Not found at C:\\ProgramData\\... -> Update Applications['ERP client'].Target in WinContextDeploy.psd1, or remove the entry." }
  ]
}
```

`schemaVersion` is there from the first release so a collector can version
against it.

## Tests

```powershell
Invoke-Pester .\tests\*.Tests.ps1 -Output Detailed
```

Or double-click `Lancer-Tests-Pester.cmd`.

## Structure

```
banner.txt                        <- startup logo (editable)
WinContextDeploy.psd1             <- paths, printers, URLs (edit this)
WinContextDeploy.cmd              <- entry point (-Usb, -FR, -EN)
docs/
  manual.typ / manual.pdf         <- the manual
src/
  Invoke-WcdConfiguration.ps1     <- orchestrator
  WcdHelpers.ps1                  <- shared functions
  Config-*.ps1                    <- configuration modules
tests/
  *.Tests.ps1                     <- Pester tests
```

## Documentation

- [`docs/manual.pdf`](docs/manual.pdf) — the full manual: what the tool does,
  how to add a module, and how to read the diagnostic. Source in
  [`docs/manual.typ`](docs/manual.typ), built with
  [Typst](https://typst.app/) (`typst compile docs/manual.typ`).
- `Get-Help <function>` works on every function in `src/`.

## License

MIT.
