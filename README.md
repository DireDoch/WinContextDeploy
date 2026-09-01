```
 __          ___        _____            _            _   _____             _             
 \ \        / (_)      / ____|          | |          | | |  __ \           | |            
  \ \  /\  / / _ _ __ | |     ___  _ __ | |_ _____  _| |_| |  | | ___ _ __ | | ___  _   _ 
   \ \/  \/ / | | '_ \| |    / _ \| '_ \| __/ _ \ \/ / __| |  | |/ _ \ '_ \| |/ _ \| | | |
    \  /\  /  | | | | | |___| (_) | | | | ||  __/>  <| |_| |__| |  __/ |_) | | (_) | |_| |
     \/  \/   |_|_| |_|\_____\___/|_| |_|\__\___/_/\_\\__|_____/ \___| .__/|_|\___/ \__, |
                                                                     | |             __/ |
                                                                     |_|            |___/ 
```

<div align="center">

# WinContextDeploy

**Post-image configuration and quick device diagnostics for Windows 11**

[![Tests](https://github.com/DireDoch/WinContextDeploy/actions/workflows/tests.yml/badge.svg)](https://github.com/DireDoch/WinContextDeploy/actions/workflows/tests.yml)
[![Manual](https://img.shields.io/badge/manual-PDF-1f4e79)](docs/manual.pdf)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

</div>

---

## Where this comes from

This is a spin-off of a PowerShell script I wrote on the job as an IT technician,
where we deployed **more than 300 machines a year** — laptops, desktops, thin
endpoints, engineering workstations, each one wanting something slightly
different from the last.

The image is identical on every machine. What comes *after* the image is not, and
that is where the twenty minutes go: the same settings dialogs in the same order,
except for the three that depend on whether this one has a battery, or runs its
applications locally, or belongs to somebody who needs a French interface. Miss
one and nobody finds out until the user does.

The script cut **7–8 minutes off every deployment (Mininum btw)** — call it a full working week
back over 300 machines — but the time was never really the point. The point was
that the twentieth machine of the week got the same treatment as the first, and
that a technician could hand back a checklist saying so.

WinContextDeploy is that idea, rebuilt in the open: the site-specific parts moved
out into a manifest you edit, the diagnostic taught to say what to do about a
failure rather than just print an exception, and the whole thing documented well
enough that somebody who has never written PowerShell can extend it.

> 📖 **[Read the manual (PDF)](docs/manual.pdf)** — what the tool does, what it
> leaves to you, how the pieces fit together, and how to add your own module.
> Source in [`docs/manual.typ`](docs/manual.typ), built with
> [Typst](https://typst.app/).

## What it does

A technician runs it once on a freshly imaged machine. It applies OS settings that
depend on the machine's context, opens the applications that need to be checked by
eye, and prints a checklist of what was done, what was skipped, and what still has
to be done by hand.

It does **not** install software. Applications are expected to arrive through your
imaging pipeline; this tool verifies they are there and puts them in front of the
technician.

> [!WARNING]
> Running this changes system settings (taskbar, regional separators, power plan,
> keyboard/language). Read `WinContextDeploy.psd1` and adjust the paths to your
> environment before first use.

### Answering the prompts

Four or five questions, answered with the arrow keys — Left and Right move,
Enter confirms. The bracketed option is the current one, highlighted in the
console.

```text
Windows system language
  fr-CA = French Canadian Windows interface  |  en-US = American English
Use Left/Right to change, then Enter to confirm.
[ FR: fr-CA ]   EN: en-US

Machine form factor
  Laptop = has a battery and a lid  |  Desktop = neither
  Selects the power profile: battery and lid-close settings.
[ L: Laptop ]   D: Desktop

Machine environment
  Workstation = full local machine  -> checks the locally installed applications
  Citrix / VDI = thin endpoint      -> its applications live in the remote session
[ W: Workstation ]   V: Citrix / VDI

Open Workstation configuration applications?
  Opens the Application Targets declared in WinContextDeploy.psd1.
  Answer Yes unless applications were already opened manually.
[ Y: Yes ]   N: No
```

### The checklist at the end

Every step, in the order it ran, with a remediation line naming the fix — and
the manifest key to edit — when something needs one.

```text
===============================================
         FINAL DIAGNOSTIC - BY STEP
===============================================
  [x]  Taskbar aligned left     OK
  [x]  Display language         OK
  [x]  Power options            OK
  [x]  Device Manager           OK
  [x]  Disk health              OK
  [x]  Free space               OK         412 GB free of 476 GB
  [x]  TPM readiness            OK         TPM present and ready.
  [x]  Drive encryption         OK         Protected: C: FullyEncrypted.
  [x]  Network adapters         OK
  [x]  Outlook                  OK
  [!]  VPN client               WARNING    No matching process running (PanGPA, PanGPS).
                                           -> Confirm VPN client is installed and started,
                                              or mark the entry Optional.
  [!]  ERP client               ERROR      ERP client not found at C:\ProgramData\...
                                           -> Update Applications['ERP client'].Target in
                                              WinContextDeploy.psd1, or remove the entry.
  [-]  Citrix Workspace         N/A        Not applicable to the chosen Environment.
  [-]  Mail signature           MANUAL     Must be done manually.
  [-]  Wi-Fi                    MANUAL     Must be done manually.

Summary: 10 OK, 1 warning(s), 1 error(s), 7 manual, 1 N/A.
```

`OK`, `WARNING` and `ERROR` are green, yellow and red in the console. `MANUAL`
is yours to do; `N/A` does not apply to this machine, so its absence is correct
rather than a problem.

## Requirements

- Windows 10/11, PowerShell 5.1 or later
- Administrator rights for the power-plan steps and the BitLocker / TPM check.
  The tool offers the UAC prompt itself; declining is fine, and those steps then
  report as needing elevation instead of failing. `-NonInteractive` never
  prompts — start the process elevated if an unattended run has to apply them.
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

`Disk.MinFreeGB` is how much free space the system drive must have before the
machine is handed over. It defaults to 20. Below it the checklist warns and names
the figure; at or above it the row still reports how much room the machine has,
so an OK row is worth reading. An image that leaves 15 GB free on a 128 GB
endpoint is normal for some fleets and a problem for others, which is why the
number lives in the manifest.

Disk *health* is not configurable — a drive reporting `Unhealthy` is an error
everywhere. Removable disks are left out of that check, so a USB key in the port
never affects the result.

Neither is *drive encryption*: an unprotected system drive is always a warning,
with no manifest knob to silence it — and so is one still encrypting, since
Windows reports a drive as protected long before it has finished. A fleet that applies BitLocker by policy
after enrolment will see the warning on a fresh machine, which is the correct
thing for a handover checklist to say. The tool only ever reports — it never
enables BitLocker and never touches a recovery key.

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

Every pull request runs three jobs on CI: the Pester suite on `windows-latest`,
PSScriptAnalyzer against `PSScriptAnalyzerSettings.psd1`, and a compile of
`docs/manual.typ` so the manual cannot rot while nobody rebuilds it.

## Structure

```
banner.txt                        <- startup logo (editable)
WinContextDeploy.psd1             <- paths, printers, URLs (edit this)
WinContextDeploy.cmd              <- entry point (-Usb, -FR, -EN)
PSScriptAnalyzerSettings.psd1     <- lint rules, each exclusion justified
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

- **[The manual (PDF)](docs/manual.pdf)** — 25 pages: what the tool does, what
  it leaves to you, the architecture in diagrams, PowerShell explained from
  nothing, how to add your own module, and how to read the diagnostic when
  something goes wrong.
  Source in [`docs/manual.typ`](docs/manual.typ) — rebuild it with
  `typst compile docs/manual.typ`.
- `Get-Help <function>` works on every function in `src/`, examples included.

## Contributing

**Ideas are genuinely welcome, and they do not have to come with code.**

This started as one technician's script for one fleet, so the parts that felt
obvious to me may well be wrong for you. If your machines need something mine
never did, that is worth an issue — even if it is only a sentence describing what
you do by hand today.

Always useful: a step you still do manually, an `Action` the manifest cannot
express, a place where the diagnostic told you nothing useful, a chapter of the
manual that missed your question, or a plain bug report.

No contribution is too small, and "I tried this and it did not work" is a
perfectly good contribution.

See **[CONTRIBUTING.md](CONTRIBUTING.md)** for how to set up, what a change
should come with, and the house style — plus
[SECURITY.md](SECURITY.md) if you have found something that should not be
reported in public.

## License

MIT — see [LICENSE](LICENSE). Do what you like with it.
