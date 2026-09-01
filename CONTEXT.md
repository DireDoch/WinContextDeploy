# WinContextDeploy

An interactive PowerShell tool a technician runs once on a freshly imaged Windows
machine. It applies OS settings that depend on the machine's context, opens the
applications the technician must eyeball, and prints a checklist of what was done,
what was skipped, and what still has to be done by hand.

## Language

### Machine context

**Form Factor**:
Whether the machine has a battery and a lid. One of `Laptop` or `Desktop`.
Chosen by the technician, not detected.
_Avoid_: DeviceType, Portable, Bureau, hardware type

**Environment**:
Whether the machine is a full local workstation (`Workstation`) or a thin endpoint
whose real applications live on a remote desktop platform (`Vdi`).
Chosen by the technician, not detected.
_Avoid_: Usage, Principal, Secondaire, MachineType, machine role

### Work

**Module**:
One area of configuration, owning a group of related Steps. Power, Language and
Applications are Modules.
_Avoid_: script, task group, component

**Step**:
The smallest unit of work that can independently succeed, fail, or be skipped.
Every Step yields exactly one Result.
_Avoid_: action, task, item

**Result**:
What a Step produced: its identity, whether it succeeded, and a severity.
_Avoid_: outcome, status object, return value

**Application Target**:
An application the tool verifies or opens — never one it installs. Applications
arrive on the machine through imaging; WinContextDeploy only confirms they are
there and puts them in front of the technician.
_Avoid_: app, package, install target, dependency

**Optional Tool**:
An Application Target the technician is offered rather than one that runs
automatically — the extras an engineering or CAD workstation needs and a standard
desk does not. Same shape as any other Application Target; only the prompting
differs.
_Avoid_: engineer tool, add-on, extra, plugin

**Manual Step**:
Work the tool deliberately does not automate and hands to the technician, listed
in the Diagnostic so it cannot be forgotten. Distinct from a Step that failed.
_Avoid_: TODO, pending, unhandled

**Not Applicable**:
A Step that does not apply to the chosen Form Factor or Environment, and whose
absence is therefore correct rather than a problem. Distinct from a skipped Step.
_Avoid_: skipped, ignored, N/A as a synonym for failed

**Diagnostic**:
The end-of-run report, given twice: once grouped by Module, once as a flat
technician's checklist.
_Avoid_: summary, report, results table

**Manifest**:
The user-editable data file holding every site-specific value — application paths,
URLs, printers. Editing it must never require editing a Module.
_Avoid_: config, settings, paths file

**Elevated**:
Whether the run holds Administrator rights. Power settings and the BitLocker and
TPM checks require them; a non-elevated run still completes, reporting those
Steps as needing elevation rather than as failures.
_Avoid_: admin, privileged, root

## Resolved ambiguities

**"Optional" now means exactly one thing.** An Application Target carrying
`Optional` produces a note when absent, never a warning. The separate hardcoded
"logiciels optionnels" table is gone; it was the same concept expressed twice.

**"Skip" is now three distinct things.** A technician declining the
open-applications prompt yields Manual Steps. A Step that does not apply to the
chosen Form Factor or Environment is Not Applicable. A Step that could not run is
a failure. Only the first is a choice, and the Diagnostic renders all three
differently.

## Example dialogue

**Dev**: The tech picked Vdi. Do we still check AutoVue?

**Tech**: No. On a Vdi endpoint the CAD viewer lives in the remote session, so
it's Not Applicable — the checklist should say so, not warn.

**Dev**: And if they picked Workstation but AutoVue genuinely isn't installed?

**Tech**: Then it's an Optional Application Target that's absent. Tell me, don't
fail the run. Half our workstations don't have it and that's fine.

**Dev**: What about the printer — that's a Step that changes the machine.

**Tech**: Right, and if it fails I need to see it as a failed Step. Don't quietly
fold it into Manual Steps just because I could also do it by hand.
