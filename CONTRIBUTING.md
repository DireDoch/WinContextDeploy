# Contributing

Ideas are genuinely welcome, and they do not have to come with code.

This started as one technician's script for one fleet, which means the parts that
felt obvious to me may well be wrong for you. If your machines need something
mine never did, that is worth an issue — even if it is only a sentence describing
what you do by hand today.

## Things that are always useful

- **A configuration step you still do manually.** If you repeat it on every
  machine, it probably belongs here. Say what it is; the how can be worked out.
- **An `Action` the manifest cannot express.** The five that exist covered my
  fleet. They will not cover everyone's.
- **A place where the diagnostic told you nothing useful.** A failure that does
  not name its fix is a bug in this project, not a fact of life.
- **Anything the manual explains badly.** If a chapter did not answer the
  question you actually had, that is worth reporting.
- **Bug reports.** Include the relevant lines from `log.txt`, or the JSON report
  from `-ReportPath` if you have one.

No contribution is too small, and "I tried this and it did not work" is a
perfectly good contribution.

## Before you write code

Check whether you need code at all. Most of what a technician wants to add is
*opening or checking an application*, and that is one entry in
`WinContextDeploy.psd1`:

```powershell
@{
    Step   = 'AppTimeTracking'
    Name   = 'Time tracking portal'
    Action = 'OpenUrl'
    Target = 'https://time.example.com/'
}
```

That entry gets a progress bar, a checklist row, a log line, an entry in the JSON
report and a remediation sentence when it fails — for free. Write a module only
when the manifest genuinely cannot express what you need: a registry change, a
Windows setting, an inventory check.

Chapter 7 of [the manual](docs/manual.pdf) walks through adding a module, with a
template to copy.

## Setting up

```powershell
git clone https://github.com/DireDoch/WinContextDeploy.git
cd WinContextDeploy
Install-Module Pester -RequiredVersion 5.7.1 -Scope CurrentUser
Invoke-Pester .\tests\*.Tests.ps1 -Output Detailed
```

You can develop against PowerShell 7 on any platform, but the tests exercise
Windows-only cmdlets, so a full green run needs Windows. CI runs them on
`windows-latest` for every pull request.

## What a change should come with

- **A test.** Every module has a `tests/Config-*.Tests.ps1`. Mock anything that
  touches the real machine — the registry, `powercfg`, `Add-Printer`,
  `Start-Process`. A test that reconfigures the machine it runs on is a test
  nobody will run twice.
- **Comment-based help.** Every `Wcd*` function needs `.SYNOPSIS`,
  `.DESCRIPTION`, a `.PARAMETER` for each parameter, `.OUTPUTS` and an
  `.EXAMPLE`. `tests/Help.Tests.ps1` enforces this, so a missing block fails CI.
- **Both languages.** Anything a technician reads lives in the `$T` tables in
  `src/Invoke-WcdConfiguration.ps1`, in French and English. Never hardcode
  user-facing text in a module.
- **A remediation, not just an error.** If a step can fail, give the result a
  `RemedyKey` and add the sentence to both `$T` tables. "The specified file was
  not found" helps nobody; "update `Applications['X'].Target`" does.

## House style

The code follows a few conventions worth matching:

- Functions are `Verb-WcdNoun`, using approved PowerShell verbs.
- A module never writes to the screen. It returns Results and raises progress
  events; the orchestrator decides how that looks. This is what makes modules
  testable with no console attached.
- A failure is recorded and the run continues. Nothing stops the run at step
  three — a technician needs the whole report.
- Comments explain *why*, not *what*. The code already says what it does.
- ASCII only in console output, so it renders in any Windows console.

## Pull requests

Fork, branch, keep `Invoke-Pester .\tests\*.Tests.ps1` green, and open a PR
describing what problem it solves. Small and focused beats large and complete.

If a change cannot be verified in CI — anything needing a real print server,
domain, or managed machine — say so in the PR and describe what you tested
manually.
