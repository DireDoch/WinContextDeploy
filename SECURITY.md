# Security policy

## What this tool does to a machine

WinContextDeploy is worth being careful with, because it is a configuration tool
that a technician runs with intent:

- It requests **Administrator rights via UAC** and relaunches itself elevated.
- It writes to the **registry** (`HKCU` only) and changes the **power plan**,
  the **display language** and the **keyboard layout**.
- It **starts applications and opens URLs** listed in `WinContextDeploy.psd1`.
- It **connects printers** from that same file.
- With `-Usb` it copies the project to `%TEMP%` and removes the copy afterwards.

It never installs software, never downloads anything, and has no network
dependency beyond one ICMP ping to a target you configure.

## The manifest is executable input

`WinContextDeploy.psd1` is loaded with `Import-PowerShellDataFile`, which does
not execute code — but every `Target` in it is a path, command or URL the tool
will launch on a machine, often elevated.

**Treat the manifest as trusted input.** Do not run a manifest you did not write
or review, any more than you would run a script somebody emailed you. If you
distribute this internally, the manifest belongs under the same review as the
rest of your deployment tooling.

## Reporting a vulnerability

If you find something that could be used to harm a machine or a user, please
report it privately rather than opening a public issue:

- Use GitHub's [private vulnerability
  reporting](https://github.com/DireDoch/WinContextDeploy/security/advisories/new)
  on this repository.

Please include what an attacker could achieve, and the smallest set of steps that
shows it. I maintain this in my own time, so I cannot promise a response window,
but I will acknowledge what I receive and credit you in the fix unless you prefer
otherwise.

## Supported versions

This project has no release branches. Fixes land on `main`; pull the latest
commit.
