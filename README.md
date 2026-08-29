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
| Device type | `Portable` (laptop) / `Bureau` (desktop) | `Portable` |
| Device usage | `Principal` (local) / `Secondaire` (Citrix) | `Principal` |
| Open configuration applications | Yes / No | Yes |
| Engineer workstation | Yes / No | No |

Device type selects the power profile (battery and lid-close settings apply to
laptops only). Device usage selects which applications are relevant — a Citrix
endpoint skips the locally installed line-of-business checks.

Or run it directly:

```powershell
powershell -ExecutionPolicy Bypass -File .\src\Invoke-WcdConfiguration.ps1
powershell -ExecutionPolicy Bypass -File .\src\Invoke-WcdConfiguration.ps1 `
    -Language en-US -DeviceType Bureau -Usage Principal -NonInteractive
```

## Configuration

All environment-specific paths and URLs live in `WinContextDeploy.psd1`. Edit
that file rather than the scripts — application shortcuts, portal URLs, and
process names are all resolved from it at runtime, with sensible fallbacks when a
key is absent.

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
