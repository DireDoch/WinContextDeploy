// WinContextDeploy manual.
//
// Build with:  typst compile docs/manual.typ
//
// Diagrams are CeTZ, console output is styled text: no image files, so nothing
// here can drift out of date without the source drifting with it.

#import "@preview/cetz:0.3.4"
#import cetz.draw as d

// ---------------------------------------------------------------------------
// Palette and page setup
// ---------------------------------------------------------------------------

#let accent = rgb("#1f4e79")
#let accentDark = rgb("#143a5a")
#let accentLight = rgb("#e8f0f8")
#let grey = rgb("#5a6472")
#let greyLight = rgb("#f0f2f5")
#let okGreen = rgb("#2e7d32")
#let warnOrange = rgb("#b26a00")
#let warnBox = rgb("#fff6e5")
#let errRed = rgb("#c62828")

#set document(title: "WinContextDeploy - Manual", author: "WinContextDeploy")
#set page(
  paper: "a4",
  margin: (x: 2.2cm, y: 2.4cm),
  numbering: "1",
  number-align: center,
)
#set text(font: ("Libertinus Serif", "DejaVu Serif"), size: 10.5pt, lang: "en")
#set par(justify: true, leading: 0.65em)
#show link: it => text(fill: accent, it)

#set heading(numbering: "1.1")
#show heading.where(level: 1): it => {
  pagebreak(weak: true)
  block(width: 100%, inset: (bottom: 8pt), stroke: (bottom: 1.2pt + accent))[
    #text(fill: grey, size: 9pt, weight: "bold", tracking: 1pt)[
      CHAPTER #counter(heading).display("1")
    ]
    #linebreak()
    #text(fill: accentDark, size: 20pt, weight: "bold")[#it.body]
  ]
  v(6pt)
}
#show heading.where(level: 2): it => {
  v(8pt)
  text(fill: accent, size: 13pt, weight: "bold")[#it]
  v(2pt)
}
#show heading.where(level: 3): it => {
  v(6pt)
  text(fill: accentDark, size: 11pt, weight: "bold")[#it]
  v(1pt)
}

#show raw.where(block: false): it => box(
  fill: greyLight, inset: (x: 3pt, y: 0pt), outset: (y: 3pt), radius: 2pt,
  text(font: ("DejaVu Sans Mono",), size: 9pt, it),
)
#show raw.where(block: true): it => block(
  fill: greyLight, inset: 9pt, radius: 3pt, width: 100%,
  stroke: (left: 2pt + accent),
  text(font: ("DejaVu Sans Mono",), size: 8.5pt, it),
)

// ---------------------------------------------------------------------------
// Callouts
// ---------------------------------------------------------------------------

#let callout(title, body, fill: accentLight, stroke: accent) = block(
  width: 100%, fill: fill, radius: 3pt, inset: 9pt,
  stroke: (left: 2.5pt + stroke),
)[
  #text(weight: "bold", fill: stroke, size: 9.5pt)[#title] \
  #body
]
#let tip(body) = callout("TIP", body)
#let warn(body) = callout("CAUTION", body, fill: warnBox, stroke: warnOrange)
#let note(body) = callout("NOTE", body, fill: greyLight, stroke: grey)

// Console output, reproduced as text rather than as a screenshot: it cannot go
// stale against the code, and it stays searchable and selectable.
//
// Lines are passed as plain strings so that neither markup characters nor runs
// of spaces are reinterpreted - column alignment is the whole point here.
#let cFg = rgb("#dcdcdc")
#let cGreen = rgb("#4ec94e")
#let cYellow = rgb("#e0c341")
#let cRed = rgb("#f26d6d")
#let cBlue = rgb("#5fc9e8")
#let cDim = rgb("#9a9a9a")

#let cline(s, fill: cFg) = text(fill: fill, s.replace(" ", "\u{00A0}"))

// A highlighted choice, the way the arrow-key prompt renders the selection.
#let csel(s) = box(fill: cYellow, inset: (x: 2pt), outset: (y: 1pt),
  text(fill: rgb("#1e1e1e"), s.replace(" ", "\u{00A0}")))

#let console(..lines, size: 8pt, leading: 0.62em) = block(
  width: 100%, fill: rgb("#1e1e1e"), radius: 3pt, inset: 9pt,
  {
    // Justification would stretch the fixed-width columns apart.
    set par(justify: false, leading: leading)
    text(font: ("DejaVu Sans Mono",), size: size, fill: cFg,
      lines.pos().join(linebreak()))
  },
)

// ---------------------------------------------------------------------------
// CeTZ diagram helpers
// ---------------------------------------------------------------------------

// A rounded box with centred content, addressed by its centre.
#let dnode(pos, body, w: 5, h: 0.9, fill: accentLight, stroke: accent) = {
  let (x, y) = pos
  d.rect((x - w / 2, y - h / 2), (x + w / 2, y + h / 2),
    radius: 0.12, fill: fill, stroke: 0.9pt + stroke)
  d.content((x, y), body)
}

#let arrow(from, to, colour: accent, ..args) = d.line(from, to,
  mark: (end: "stealth", fill: colour), stroke: 0.9pt + colour, ..args)

#let dlabel(pos, body, size: 7pt, fill: grey) = d.content(pos,
  text(size: size, fill: fill, body))

// A left-aligned name with its description pushed to the right edge.
#let launcherRow(name, description) = box(width: 12.6cm)[
  #text(font: ("DejaVu Sans Mono",), size: 8.5pt, weight: "bold")[#name]
  #h(1fr)
  #text(size: 8pt)[#description]
]

#let flowNode(y, body, fill: accentLight, stroke: accent, w: 9.5) = dnode((0, y), body,
  w: w, h: 0.75, fill: fill, stroke: stroke)

// ---------------------------------------------------------------------------
// Title page
// ---------------------------------------------------------------------------

#page(numbering: none)[
  #v(5cm)
  #align(center)[
    #text(size: 34pt, weight: "bold", fill: accentDark)[WinContextDeploy]
    #v(4pt)
    #text(size: 13pt, fill: grey)[Post-image configuration and quick device diagnostics]
    #v(1.2cm)
    #line(length: 45%, stroke: 1pt + accent)
    #v(1.2cm)
    #text(size: 11pt, fill: grey)[
      Technician's manual \
      #v(2pt)
      What the tool does, what it leaves to you, \
      and how to extend it
    ]
  ]
  #v(1fr)
  #align(center)[
    #text(size: 9pt, fill: grey)[
      Built with Typst from `docs/manual.typ` · MIT licence
    ]
  ]
]

#page(numbering: none)[
  #text(size: 16pt, weight: "bold", fill: accentDark)[Contents]
  #v(8pt)
  #outline(title: none, depth: 2, indent: 1.2em)
]

#counter(page).update(1)

= Introduction

== Why this tool exists

A freshly imaged Windows machine is not a finished machine. The image is the
same for everyone, but the machine in front of you is not: it has a battery or
it does not, it runs its applications locally or in a remote session, it belongs
to a technician who needs a French interface or an English one.

Closing that gap by hand takes twenty minutes of clicking through the same
settings dialogs, in the same order, and it takes them again on the next
machine. Twenty minutes is not the problem. The problem is that the twentieth
machine of the week gets a slightly different treatment from the first, and
nobody can say afterwards which settings were actually applied.

WinContextDeploy is the answer to that: a technician runs it once, answers four
or five questions, and it applies the settings that depend on the machine's
context, opens the applications that need to be checked by eye, and prints a
checklist of what was done, what was skipped, and what still has to be done by
hand.

#warn[
  It does *not* install software. Applications are expected to arrive through
  your imaging pipeline. This tool confirms they are there and puts the ones a
  technician must eyeball in front of them.
]

== The three ways to launch it

There is one launcher, `WinContextDeploy.cmd`, and it covers three situations.

#v(0.3cm)
#align(center)[
  #cetz.canvas({
    dnode((0, 0), launcherRow(
      [WinContextDeploy.cmd], [Run *in place* — correct for a `git clone`]),
      w: 13.4, h: 1.0)

    dnode((0, -1.25), launcherRow(
      [WinContextDeploy.cmd -Usb], [Copy to `%TEMP%`, run there, write the log back]),
      w: 13.4, h: 1.0, fill: greyLight, stroke: grey)

    dnode((0, -2.5), launcherRow(
      [powershell -File src\\Invoke-WcdConfiguration.ps1], [Direct, scriptable]),
      w: 13.4, h: 1.0, fill: warnBox, stroke: warnOrange)
  })
]
#v(0.2cm)

*Run in place* is the default and the one to use after a `git clone`. Nothing is
copied and nothing is deleted.

*`-Usb`* is for a USB key. PowerShell off removable media is slow and the key can
be pulled mid-run, so the project is copied to a uniquely named folder under
`%TEMP%`, run from there, and the run's history block is appended back to
`log.txt` next to the launcher before the copy is removed.

*Direct* is how you drive it from another script: every prompt has a matching
parameter, so `-NonInteractive` runs the whole thing without asking anything.

Add `-FR` or `-EN` to either `.cmd` form to force the interface language. Without
one, it follows the system locale.

== What this manual covers

- *Chapters 2 and 3* — how to run the tool, and what it does on its own.
- *Chapter 4* — what it deliberately leaves to you.
- *Chapter 5* — how the project is put together, in diagrams.
- *Chapter 6* — PowerShell, explained from nothing.
- *Chapter 7* — adding your own module.
- *Chapter 8* — reading the diagnostic and the logs when something goes wrong.

= Quick start

== Before you run it

#table(
  columns: (auto, 1fr),
  stroke: none,
  inset: (x: 4pt, y: 5pt),
  fill: (_, row) => if calc.odd(row) { greyLight },
  [*Windows*], [Windows 10 or 11.],
  [*PowerShell*], [5.1 or later. Windows ships with it; nothing to install.],
  [*Administrator*],
  [Only the power settings need it. The tool offers the UAC prompt itself and
   carries on perfectly well if you decline.],
  [*The manifest*],
  [Open `WinContextDeploy.psd1` and point it at the applications, printers and
   URLs of *your* environment. The shipped entries are generic examples.],
)

#warn[
  Read the manifest before the first run on a real machine. The tool changes
  system settings: the taskbar, the regional separators, the power plan and the
  keyboard layout.
]

== Running it

Double-click `WinContextDeploy.cmd`. A console window opens, the banner is
drawn, and the questions start.

#console(
  cline(" __          ___        _____            _            _   _____             _"),
  cline(" \\ \\        / (_)      / ____|          | |          | | |  __ \\           | |"),
  cline("  \\ \\  /\\  / / _ _ __ | |     ___  _ __ | |_ _____  _| |_| |  | | ___ _ __ | | ___  _   _"),
  cline("   \\ \\/  \\/ / | | '_ \\| |    / _ \\| '_ \\| __/ _ \\ \\/ / __| |  | |/ _ \\ '_ \\| |/ _ \\| | | |"),
  cline("    \\  /\\  /  | | | | | |___| (_) | | | | ||  __/>  <| |_| |__| |  __/ |_) | | (_) | |_| |"),
  cline("     \\/  \\/   |_|_| |_|\\_____\\___/|_| |_|\\__\\___/_/\\_\\\\__|_____/ \\___| .__/|_|\\___/ \\__, |"),
  cline("                                                                     | |             __/ |"),
  cline("                                                                     |_|            |___/"),
  cline(""),
  cline("Post-image configuration and quick device diagnostics", fill: cDim),
  size: 6.2pt,
  leading: 1.0em,
)

Every question works the same way: *Left* and *Right* move between the choices,
*Enter* confirms. The highlighted option is the default, so holding Enter through
all of them is a valid answer.

== The menu questions

=== Windows system language

#console(
  cline("Windows system language", fill: cBlue),
  cline("  fr-CA = French Canadian Windows interface  |  en-US = American English", fill: cDim),
  cline("Use Left/Right to change, then Enter to confirm.", fill: cDim),
  [#csel(" FR: fr-CA ") #cline("  EN: en-US", fill: cDim)],
)

Sets the display language, the keyboard layout, the user culture and the home
region. This is the language *Windows* will speak, and it is independent of the
language the tool itself uses for its prompts.

=== Machine form factor

#console(
  cline("Machine form factor", fill: cBlue),
  cline("  Laptop = has a battery and a lid  |  Desktop = neither", fill: cDim),
  cline("  Selects the power profile: battery and lid-close settings.", fill: cDim),
  [#csel(" L: Laptop ") #cline("  D: Desktop", fill: cDim)],
)

On a *Laptop*, the tool sets the screen timeout on battery, the screen timeout on
AC, and makes closing the lid do nothing. On a *Desktop* the battery and lid
steps do not apply, and the checklist says so rather than leaving them out.

=== Machine environment

#console(
  cline("Machine environment", fill: cBlue),
  cline("  Workstation = full local machine  -> checks the locally installed applications", fill: cDim),
  cline("  Citrix / VDI = thin endpoint      -> its applications live in the remote session", fill: cDim),
  [#csel(" W: Workstation ") #cline("  V: Citrix / VDI", fill: cDim)],
)

This is what decides which applications are relevant. On a VDI endpoint the
line-of-business applications live in the remote session, so checking for them
locally would report a problem that is not one — the checklist marks them *Not
Applicable* instead.

=== Open the configuration applications

#console(
  cline("Open Workstation configuration applications?", fill: cBlue),
  cline("  Opens the Application Targets declared in WinContextDeploy.psd1.", fill: cDim),
  cline("  Answer Yes unless applications were already opened manually.", fill: cDim),
  [#csel(" Y: Yes ") #cline("  N: No", fill: cDim)],
)

Answer *No* if you have already opened everything by hand. The applications then
appear on the checklist as manual steps rather than silently disappearing from
it.

=== Engineering workstation

#console(
  cline("Engineering workstation? (offers the optional tools)", fill: cBlue),
  cline("  Offers the extras declared Prompt in WinContextDeploy.psd1.", fill: cDim),
  cline("  Answer No for a standard machine.", fill: cDim),
  [#cline("Y: Yes ", fill: cDim) #csel(" N: No ")],
)

Answering *Yes* opens a numbered menu of the optional tools, where several can be
picked at once by typing their numbers together — `13` selects the first and the
third.

#note[
  This question only appears when the manifest declares at least one entry with
  `Prompt = $true`. With none, the tool skips it entirely.
]

== The result: the final diagnostic

When every module has run, the tool prints its report twice. First grouped by
module, which is the view that tells you whether the run itself went well:

#console(
  cline("==============================================="),
  cline("         FINAL DIAGNOSTIC - BY MODULE"),
  cline("==============================================="),
  cline("  [x]  Config-Power              OK        5 step(s)", fill: cGreen),
  cline("  [x]  Config-Decimal            OK        1 step(s)", fill: cGreen),
  cline("  [x]  Config-TaskbarLeft        OK        2 step(s)", fill: cGreen),
  cline("  [x]  Config-Language           OK        2 step(s)", fill: cGreen),
  cline("  [!]  Config-Applications       WARNING   9 step(s)  Warnings: AppVpn", fill: cYellow),
  cline("  [x]  Config-DeviceManager      OK        1 step(s)", fill: cGreen),
  cline("  [x]  Config-Disk               OK        2 step(s)", fill: cGreen),
  cline("  [x]  Config-Network            OK        3 step(s)", fill: cGreen),
)

Then as a flat checklist, which is the view you actually work from — one line per
thing that had to happen on this machine:

#console(
  cline("==============================================="),
  cline("         FINAL DIAGNOSTIC - BY STEP"),
  cline("==============================================="),
  cline("  [x]  Taskbar aligned left     OK", fill: cGreen),
  cline("  [x]  Display language         OK", fill: cGreen),
  cline("  [x]  Keyboard layout          OK", fill: cGreen),
  cline("  [x]  Decimal separator        OK", fill: cGreen),
  cline("  [x]  Power options            OK", fill: cGreen),
  cline("  [x]  Device Manager           OK", fill: cGreen),
  cline("  [x]  Disk health              OK", fill: cGreen),
  cline("  [x]  Free space               OK         412 GB free of 476 GB", fill: cGreen),
  cline("  [x]  Network adapters         OK", fill: cGreen),
  cline("  [x]  Software Center          OK", fill: cGreen),
  cline("  [!]  VPN client               WARNING    No matching process running (PanGPA, PanGPS).", fill: cYellow),
  cline("                                           -> Confirm VPN client is installed and started,", fill: cYellow),
  cline("                                              or mark the entry Optional.", fill: cYellow),
  cline("  [!]  ERP client               ERROR      ERP client not found at C:\\ProgramData\\...", fill: cRed),
  cline("                                           -> Update Applications['ERP client'].Target in", fill: cRed),
  cline("                                              WinContextDeploy.psd1, or remove the entry.", fill: cRed),
  cline("  [-]  Citrix Workspace         N/A        Not applicable to the chosen Environment.", fill: cDim),
  cline("  [-]  Mail signature           MANUAL     Must be done manually.", fill: cDim),
  cline("  [-]  Wi-Fi                    MANUAL     Must be done manually.", fill: cDim),
  cline("  [-]  Network drives           MANUAL     Must be done manually.", fill: cDim),
  cline(""),
  cline("Summary: 8 OK, 1 warning(s), 1 error(s), 7 manual, 1 N/A.", fill: cYellow),
)

The arrow lines are the point of the whole report. A failure that only says
_"the specified file was not found"_ tells a technician nothing; a failure that
names the manifest key to edit tells a technician exactly what to do next.

= What the tool does automatically

== The full execution flow

From the double-click to the final report, the run always follows the same path.
Your answers change what each module *does*, never the order they run in.

#v(0.2cm)
#align(center)[
  #cetz.canvas({
    let modules = (
      ("Config-Power", "power plan, lid, screen timeouts"),
      ("Config-Decimal", "decimal and currency separators"),
      ("Config-TaskbarLeft", "taskbar alignment, task view"),
      ("Config-Language", "display language, keyboard"),
      ("Config-Applications", "verify and open the targets"),
      ("Config-DeviceManager", "devices Windows cannot configure"),
      ("Config-Disk", "disk health, free space on the system drive"),
      ("Config-Network", "adapters, connectivity, network places"),
      ("Config-Printer", "shared print queues"),
    )

    // Start / setup
    dnode((0, 0), text(size: 8.5pt, weight: "bold", fill: white)[Launch],
      w: 4.4, h: 0.7, fill: accent, stroke: accentDark)
    dnode((0, -1.0), text(size: 8pt)[Elevation check (UAC prompt, or carry on)], w: 8.4, h: 0.68)
    dnode((0, -2.0), text(size: 8pt)[Read `WinContextDeploy.psd1`], w: 8.4, h: 0.68)
    dnode((0, -3.0), text(size: 8pt)[Ask the menu questions], w: 8.4, h: 0.68)
    arrow((0, -0.35), (0, -0.66))
    arrow((0, -1.34), (0, -1.66))
    arrow((0, -2.34), (0, -2.66))

    // Modules
    let top = -4.2
    for (i, m) in modules.enumerate() {
      let y = top - i * 0.85
      dnode((0, y), [
        #text(font: ("DejaVu Sans Mono",), size: 7.5pt, weight: "bold")[#m.at(0)]
        #h(0.5em) #text(size: 7.5pt, fill: grey)[— #m.at(1)]
      ], w: 9.6, h: 0.66, fill: rgb("#eaf5ea"), stroke: okGreen)
      if i == 0 { arrow((0, -3.34), (0, y + 0.33)) } else { arrow((0, y + 0.85 - 0.33), (0, y + 0.33)) }
    }

    let last = top - 8 * 0.85
    dnode((0, last - 1.0), text(size: 8pt)[Final diagnostic: by module, then by step], w: 8.4, h: 0.68)
    dnode((0, last - 2.0), text(size: 8pt)[Write the log, the history block and the JSON report], w: 8.4, h: 0.68)
    dnode((0, last - 3.0), text(size: 8.5pt, weight: "bold", fill: white)[End],
      w: 4.4, h: 0.7, fill: accent, stroke: accentDark)
    arrow((0, last - 0.33), (0, last - 0.66))
    arrow((0, last - 1.34), (0, last - 1.66))
    arrow((0, last - 2.34), (0, last - 2.66))

    // Brace over the module band
    d.line((5.2, top + 0.33), (5.5, top + 0.33), (5.5, last - 0.33), (5.2, last - 0.33),
      stroke: 0.8pt + grey)
    dlabel((7.1, (top + last) / 2), align(left)[9 modules, \ run in \ this order], size: 8pt)
  })
]
#v(0.2cm)

#note[
  A module that crashes does not stop the run. Its failure is recorded, the next
  module starts, and you still get a complete report at the end. The only thing
  a technician cannot use is a report that never appears.
]

== What each module does

=== Config-Power — power plan, lid and screen timeouts

Sets the screen timeout to 10 minutes on battery and 15 on AC, makes closing the
lid do nothing, and applies the active power scheme. On a `Desktop` the battery
and lid steps do not apply.

This is the *only* module that needs Administrator. Without it, the module
attempts nothing and every step reports:

#console(
  cline("  [!]  Power options            WARNING    Screen timeout on AC: powercfg requires", fill: cYellow),
  cline("                                           Administrator.", fill: cYellow),
  cline("                                           -> Requires Administrator. Relaunch elevated", fill: cYellow),
  cline("                                              to apply.", fill: cYellow),
)

#tip[
  The sleep steps (`standby-timeout-*`) are deliberately switched off: they are
  blocked by Group Policy in most managed environments, so attempting them only
  produces noise. The commented rows in the module's step table are what to
  restore if that is not true for you.
]

=== Config-Decimal — decimal and currency separators

Forces the period as the decimal separator and the comma as the thousands
separator, for both numbers and money. A French-Canadian Windows uses a comma
for decimals by default, which quietly corrupts anything pasted into a
spreadsheet built around the other convention.

=== Config-TaskbarLeft — taskbar alignment and task view

Aligns the taskbar to the left and hides the Task View button — Windows 11
defaults that most users on a fleet want changed once, not every time.

=== Config-Language — display language and keyboard

Applies the display language, the keyboard layout, the user culture, the system
locale and the home region for the culture you chose.

#note[
  The system locale and the home region need Administrator. Without it, the
  module applies everything else and notes the two it could not do. Some Windows
  Store applications also only pick up the new language after a sign-out.
]

=== Config-Applications — verify and open the targets

The manifest-driven core of the tool. It walks the `Applications` list in
`WinContextDeploy.psd1` in order and runs each entry according to its `Action`:

#table(
  columns: (auto, 1fr),
  stroke: none,
  inset: (x: 5pt, y: 5pt),
  fill: (_, row) => if calc.odd(row) { greyLight },
  [`Launch`], [Starts an application: a `.lnk`, an `.exe`, or a command on `PATH`.],
  [`OpenFolder`], [Opens a folder in Explorer.],
  [`OpenUrl`], [Opens a URL in the default browser.],
  [`CheckProcess`], [Verifies a process is running. Launches nothing. `Target` is a list of process names, and any one of them counts.],
  [`CheckPath`], [Verifies a path exists. Launches nothing.],
)

Adding, removing or reordering an application is a manifest edit. No code
changes, no new module.

=== Config-DeviceManager — devices Windows cannot configure

Reads every Plug-and-Play device and reports the ones with a problem code. A
missing driver on a freshly imaged machine is exactly what this catches, before
the user finds it a week later.

Codes that resolve themselves — a pending reboot, a device not currently
connected — are warnings. A missing or broken driver is an error.

=== Config-Disk — disk health and free space

A freshly imaged machine can still be sitting on a dying drive, or on a partition
far smaller than the image expects. Neither shows up anywhere else in the run,
and the technician usually finds out weeks later, from the user.

Two steps. `Disk health` reads the health each disk reports: `Healthy` passes,
`Warning` is a warning, `Unhealthy` is an error that names the drive and its
serial number so the right one gets pulled. A status the drive does not report at
all is a warning rather than a silent pass — an unreadable disk is not a healthy
one. `Free space` reads the system drive and reports the figure either way, so an
OK row still tells you how much room the machine has.

Removable disks are left out of the health check. A technician's USB key is not
the machine's disk, and it must never block a handover. Free space is read on the
system drive only, for the same reason.

#tip[
  How much free space is enough is a fleet decision, so it lives in the manifest:

  ```powershell
  Disk = @{
      MinFreeGB = 20
  }
  ```

  Omit the key and the threshold is 20 GB. Below it the checklist warns and names
  the figure and the threshold; the remediation points back at `Disk.MinFreeGB`,
  so a threshold that is wrong for your fleet is one edit away.
]

#note[
  Wear percentage and drive temperature — `Get-StorageReliabilityCounter` — are
  deliberately not read. They are genuinely useful on refurbished machines, but
  they need Administrator and return nothing on plenty of consumer SATA and NVMe
  drives, so the step would silently report nothing on a large slice of any fleet.
]

=== Config-Network — adapters, connectivity and network places

Inventories the active adapters (the virtual ones — Bluetooth, loopback, VPN,
hypervisor — are filtered out), pings the configured target *from the Wi-Fi
adapter*, and triggers the user's "Refresh My Network Places" shortcut.

#tip[
  The ping source address is forced to the Wi-Fi adapter on purpose. With a cable
  plugged in, an ordinary ping would be answered over Ethernet and pass while the
  Wi-Fi is quietly broken.

  A blocked ping is a warning, never a hard failure — many corporate networks
  drop ICMP to the internet. Point `Network.PingTarget` at your gateway or an
  internal host if that is your case.
]

=== Config-Printer — shared print queues

Connects the shared print-server queues listed in the manifest's `Printers`
array, using the built-in `Add-Printer` cmdlet. Already connected is a no-op, so
running the tool twice is safe, and an unreachable print server is a warning
rather than a crash.

Leave `Printers = @()` and the module is skipped entirely; printers then stay on
the checklist as a manual step.

= What stays manual

Some things are deliberately not automated. Automating them badly is worse than
not automating them: a step that half-works on some machines is a step nobody
can trust on any machine.

They appear on the checklist anyway, marked `MANUAL`, so a technician cannot
finish a machine having forgotten one.

#table(
  columns: (auto, 1fr),
  stroke: none,
  inset: (x: 5pt, y: 6pt),
  fill: (_, row) => if calc.odd(row) { greyLight },
  [*Mail signature*],
  [Depends on the person, not the machine: their name, title and telephone
   number. There is nothing about the machine that can supply them.],
  [*Wi-Fi*],
  [Joining a network usually needs a credential or a certificate the tool has no
   business handling.],
  [*Network drives*],
  [Which shares a user gets is a directory decision. `Config-Network` refreshes
   network places, but it will not invent mappings.],
  [*Account sync*],
  [Signing into the account is the user's action, at their first login.],
  [*Windows desktop*],
  [Icon layout and personal shortcuts — a preference, not a configuration.],
  [*Browser favourites*],
  [Imported from the user's profile or pushed by policy, not by a local script.],
  [*Printers*],
  [Manual *only when the manifest declares none*. Fill in the `Printers` array
   and this becomes automatic.],
)

#note[
  A manual step is not a failure and not a skipped step. The tool distinguishes
  three things that look alike:

  - *MANUAL* — deliberately yours to do.
  - *N/A* — does not apply to this machine's form factor or environment, so its
    absence is correct.
  - *ERROR* — should have worked, and did not.
]

= How the project is put together

== C4 diagram — the architecture

A C4 diagram describes a system at progressively closer zoom levels. Think of it
as a map: level 1 is the satellite view of who uses what, level 2 shows the
buildings inside.

=== Level 1 — context: who interacts with what

#v(0.2cm)
#align(center)[
  #cetz.canvas({
    dnode((0, 0), [
      #text(size: 8.5pt, weight: "bold", fill: white)[IT technician] \
      #text(size: 7pt, fill: rgb("#dfe8f2"))[Runs the tool, reads the checklist]
    ], w: 3.4, h: 1.6, fill: accent, stroke: accentDark)

    dnode((5.6, 0), [
      #text(size: 8.5pt, weight: "bold", fill: white)[WinContextDeploy] \
      #text(size: 7pt, fill: rgb("#dfe8f2"))[Applies the context-dependent \ settings, reports the rest]
    ], w: 4.4, h: 1.6, fill: rgb("#2c6da8"), stroke: accentDark)

    dnode((11.0, 1.15), [
      #text(size: 8.5pt, weight: "bold")[Windows 11] \
      #text(size: 7pt, fill: grey)[Registry, power plan, locale]
    ], w: 3.8, h: 1.3, fill: greyLight, stroke: grey)

    dnode((11.0, -1.15), [
      #text(size: 8.5pt, weight: "bold")[Applications] \
      #text(size: 7pt, fill: grey)[Already installed by the image]
    ], w: 3.8, h: 1.3, fill: greyLight, stroke: grey)

    arrow((1.7, 0), (3.4, 0))
    dlabel((2.55, 0.28), [runs])
    arrow((7.8, 0.35), (9.1, 1.0), colour: grey)
    dlabel((8.2, 1.05), [configures])
    arrow((7.8, -0.35), (9.1, -1.0), colour: grey)
    dlabel((8.3, -1.1), [verifies, opens])
  })
]

=== Level 2 — containers: the pieces inside

#v(0.2cm)
#align(center)[
  #cetz.canvas({
    let cont(pos, title, sub, fill: accentLight, stroke: accent) = dnode(pos, [
      #text(size: 8pt, weight: "bold")[#title] \
      #text(size: 7pt, fill: grey)[#sub]
    ], w: 3.9, h: 1.2, fill: fill, stroke: stroke)

    cont((0, 0), [WinContextDeploy.cmd], [Launcher])
    cont((5, 0), [Invoke-WcdConfiguration.ps1], [Orchestrator])
    cont((10, 0), [Config-\*.ps1], [The 9 modules], fill: rgb("#eaf5ea"), stroke: okGreen)
    cont((10, -2.6), [WinContextDeploy.psd1], [The manifest], fill: warnBox, stroke: warnOrange)
    cont((5, -2.6), [WcdHelpers.ps1], [Shared functions])
    cont((0, -2.6), [log.txt / report.json], [Output], fill: greyLight, stroke: grey)

    arrow((1.95, 0), (3.05, 0));       dlabel((2.5, 0.25), [starts])
    arrow((6.95, 0), (8.05, 0));       dlabel((7.5, 0.25), [calls])
    arrow((6.2, -0.6), (9.1, -2.0));   dlabel((8.3, -1.05), [reads])
    arrow((5, -0.6), (5, -2.0));       dlabel((5.55, -1.3), [loads])
    arrow((8.05, -2.6), (6.95, -2.6)); dlabel((7.5, -2.35), [uses])
    arrow((3.05, -2.6), (1.95, -2.6)); dlabel((2.5, -2.35), [writes])
  })
]

#tip[
  Notice which way the arrows point. The orchestrator reads the manifest and
  hands each module exactly what it needs; the modules return a Result and write
  to the log. Nothing reads back out of a module. That is what makes each one
  testable on its own — and why adding a module changes nothing else.
]

== The folder tree

#align(center)[
  #cetz.canvas({
    let row(y, indent, name, note, mono: true) = {
      d.content((indent, y), anchor: "west",
        text(font: ("DejaVu Sans Mono",), size: 8.5pt, weight: if indent == 0 { "bold" } else { "regular" },
          fill: if indent == 0 { accentDark } else { black }, name))
      if note != none {
        d.content((7.4, y), anchor: "west", text(size: 8pt, fill: grey, note))
      }
    }
    row(0, 0, "WinContextDeploy/", none)
    row(-0.55, 0.4, "banner.txt", [startup logo, editable])
    row(-1.1, 0.4, "WinContextDeploy.cmd", [the one launcher])
    row(-1.65, 0.4, "WinContextDeploy.psd1", [the manifest — edit this])
    row(-2.2, 0.4, "src/", [the code])
    row(-2.75, 0.9, "Invoke-WcdConfiguration.ps1", [orchestrator])
    row(-3.3, 0.9, "WcdHelpers.ps1", [shared functions])
    row(-3.85, 0.9, "Config-*.ps1", [one file per module])
    row(-4.4, 0.4, "tests/", [Pester tests, one file per module])
    row(-4.95, 0.4, "docs/", [this manual])
    d.line((0.25, -0.35), (0.25, -4.95), stroke: 0.7pt + grey)
    d.line((0.75, -2.55), (0.75, -3.85), stroke: 0.7pt + grey)
  })
]

#v(0.2cm)
#table(
  columns: (auto, 1fr),
  stroke: none,
  inset: (x: 5pt, y: 5pt),
  fill: (_, row) => if calc.odd(row) { greyLight },
  [`WinContextDeploy.psd1`],
  [Every environment-specific value: application paths, printers, URLs, the ping
   target. This is the file you edit; the rest is the same everywhere.],
  [`src/`],
  [One file per module, plus the orchestrator and the shared helpers. Adding a
   module means adding a file here.],
  [`tests/`],
  [One Pester test file per module. A new module gets a new test file.],
  [`docs/`],
  [This manual, as Typst source and as a built PDF.],
)

== Sequence diagram — how the pieces talk

This is one run, in the order things actually happen.

#v(0.2cm)
#align(center)[
  #cetz.canvas({
    let actors = (
      (0, "Technician"), (2.9, ".cmd"), (5.8, "Orchestrator"),
      (8.7, "Module"), (11.2, "Windows"), (13.7, "log.txt"),
    )
    for (x, name) in actors {
      dnode((x, 0), text(size: 7.5pt, weight: "bold", fill: white)[#name],
        w: 2.3, h: 0.55, fill: accent, stroke: accentDark)
      d.line((x, -0.3), (x, -9.6), stroke: (paint: grey.lighten(40%), dash: "dashed", thickness: 0.6pt))
    }

    let msg(y, from, to, label, dashed: false) = {
      d.line((from, y), (to, y),
        mark: (end: "stealth", fill: if dashed { grey } else { accent }),
        stroke: (paint: if dashed { grey } else { accent }, thickness: 0.8pt,
          dash: if dashed { "dashed" } else { none }))
      dlabel(((from + to) / 2, y + 0.22), label, size: 7pt)
    }

    msg(-0.9, 0, 2.9, [double-click])
    msg(-1.5, 2.9, 5.8, [start PowerShell])
    // A self-action, not a message to anyone else.
    d.line((5.8, -1.95), (6.5, -1.95), (6.5, -2.35), (5.8, -2.35),
      mark: (end: "stealth", fill: accent), stroke: 0.8pt + accent)
    dlabel((8.0, -2.15), [check elevation, read the manifest], size: 7pt)
    msg(-2.7, 5.8, 0, [ask the menu questions], dashed: true)
    msg(-3.3, 0, 5.8, [answers])
    msg(-4.1, 5.8, 8.7, [call the module])
    msg(-4.7, 8.7, 11.2, [registry / powercfg / Add-Printer])
    msg(-5.3, 11.2, 8.7, [ok or error], dashed: true)
    msg(-5.9, 8.7, 13.7, [Write-WcdLog])
    msg(-6.5, 8.7, 5.8, [Result { Step, Success, Remedy }], dashed: true)

    d.rect((4.4, -7.0), (12.6, -7.6), radius: 0.08,
      stroke: (paint: grey, dash: "dashed", thickness: 0.7pt))
    dlabel((8.5, -7.3), [repeated once per module, eight times], size: 7.5pt)

    msg(-8.1, 5.8, 0, [print the final diagnostic], dashed: true)
    msg(-8.7, 5.8, 13.7, [history block + JSON report])
    msg(-9.3, 5.8, 0, [press Enter, window closes], dashed: true)
  })
]

#note[
  The module never touches the screen. It returns a Result and raises progress
  events; the orchestrator decides what that looks like. That is exactly why a
  module can be tested with no console attached at all.
]

= PowerShell, explained simply

You do not need to be a developer to extend this tool. You need four ideas, and
this chapter covers all four with examples taken from the code you already have.

== What PowerShell is

Windows has a graphical interface and a text one. Clicking through the Settings
app is fine for one machine. It is unbearable for twelve a week, and — the part
that matters — it leaves no record of what was actually done.

PowerShell is the text interface. You write down the steps once, in a file, and
Windows performs them the same way every time. That file *is* the record.

A PowerShell file has the extension `.ps1`. That is all a "script" is.

== The four building blocks

=== Variables — remember a value

A variable is a labelled box. It starts with `$`, you put something in it, and
you use the label afterwards instead of repeating the value.

```powershell
# Store the registry key we are about to change
$intlPath = 'HKCU:\Control Panel\International'

# Use it twice without retyping it
Set-WcdRegistryValue -Path $intlPath -Name 'sDecimal'      -Value '.'
Set-WcdRegistryValue -Path $intlPath -Name 'sThousandSep'  -Value ','
```

If the key ever moves, you change one line, not two. On a longer script, not
twenty.

=== Conditions — do something only sometimes

`if` runs a block only when something is true. This is how the tool adapts to the
machine in front of it, and it is the whole idea behind the Form Factor question:

```powershell
if ($FormFactor -eq 'Laptop') {
    # Only a laptop has a lid to close
    Invoke-WcdPowerCfg '/setacvalueindex' 'SCHEME_CURRENT' 'SUB_BUTTONS' 'LIDACTION' '0'
}
```

`-eq` means "equals". The others read the same way: `-ne` not equal, `-gt`
greater than, `-lt` less than, `-match` matches a pattern.

=== Functions — name a piece of work

A function is a named block you can call from anywhere. Every module in this
project is a function.

```powershell
function Set-WcdDecimalConfiguration {
    param(
        [string]$LogPath        # what the caller passes in
    )

    # ... the work ...

    return [pscustomobject]@{ Step = 'DecimalAndCurrency'; Success = $true }
}

# Calling it
$result = Set-WcdDecimalConfiguration -LogPath 'C:\temp\log.txt'
```

`param(...)` declares what the caller may pass. `return` hands something back.

=== try / catch — the safety net

This is the one that makes the whole tool usable. `try` attempts something;
`catch` runs only if it failed, instead of the whole script stopping.

```powershell
try {
    Set-WcdRegistryValue -Path $intlPath -Name 'sDecimal' -Value '.'
    $success = $true
} catch {
    # $_ is whatever went wrong
    $note = $_.Exception.Message
    $success = $false
}
```

#tip[
  This is why one locked registry key does not cost you the whole run. The module
  records the failure, returns, and the next module starts. A technician gets a
  full report of a partly successful run — which is far more useful than a script
  that stopped at step three with a red wall of text.
]

== The anatomy of a module

`Config-Decimal` is the simplest module in the project: one step, no
dependencies. Every other module has the same five zones — only zone 4 differs.

#v(0.2cm)
#align(center)[
  #cetz.canvas({
    let zone(y, n, title, body, fill, stroke) = {
      dnode((0, y), box(width: 12.4cm)[
        #set align(left)
        #text(size: 8.5pt, weight: "bold")[Zone #n — #title] #h(0.6em)
        #text(size: 8pt, fill: grey)[#body]
      ], w: 13.2, h: 0.85, fill: fill, stroke: stroke)
    }
    zone(0, [1], [Header], [what the module does, its parameters, what it returns],
      accentLight, accent)
    zone(-0.95, [2], [Function and parameters],
      [`function Set-Wcd<X>Configuration { param(...) }`], rgb("#eaf5ea"), okGreen)
    zone(-1.9, [3], [Initialisation], [resolve the log path, name the module],
      warnBox, warnOrange)
    zone(-2.85, [4], [try / catch — the actual work],
      [do it, raise progress events, log the outcome], accentLight, accent)
    zone(-3.8, [5], [Return], [`[pscustomobject]@{ Step; Success; Error; RemedyKey }`],
      rgb("#eaf5ea"), okGreen)
  })
]
#v(0.2cm)

Here is the real module, with the zones marked:

```powershell
# ---------------------------------------------------------------- ZONE 1
# Config-Decimal.ps1 - forces the decimal and currency separators to a period.
# Entry point: Set-WcdDecimalConfiguration. Requires WcdHelpers.ps1.

function Set-WcdDecimalConfiguration {
    [CmdletBinding()]
    param(                                                       # ZONE 2
        [string]$LogPath,                 # where to write the log
        [scriptblock]$ProgressCallback    # how to report progress
    )

    # ------------------------------------------------------------ ZONE 3
    $resolvedLogPath = Resolve-WcdLogPath -CandidatePath $LogPath
    $intlPath = 'HKCU:\Control Panel\International'
    $moduleName = 'Config-Decimal'

    # ------------------------------------------------------------ ZONE 4
    try {
        # Tell the orchestrator this step is starting
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback `
            -ModuleName $moduleName -StepKey 'DecimalAndCurrency' -Event 'Start'

        # The actual work
        Set-WcdRegistryValue -Path $intlPath -Name 'sDecimal'       -Value '.'
        Set-WcdRegistryValue -Path $intlPath -Name 'sThousandSep'   -Value ','
        Set-WcdRegistryValue -Path $intlPath -Name 'sMonDecimalSep' -Value '.'
        Set-WcdDecimalThreadCulture -DecimalSeparator '.' -ThousandsSeparator ','

        Write-WcdLog -Path $resolvedLogPath -Level 'INFO' `
            -Message 'Regional: decimal and currency separators forced to a period.'

        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback `
            -ModuleName $moduleName -StepKey 'DecimalAndCurrency' `
            -Event 'Finish' -Kind 'success'

        # -------------------------------------------------------- ZONE 5
        return [pscustomobject]@{
            Step    = 'DecimalAndCurrency'
            Success = $true
            LogPath = $resolvedLogPath
            Error   = ''
        }

    } catch {
        # Something went wrong: note it, name the fix, and carry on
        $note = $_.Exception.Message
        $remedyKey = 'RegistryWriteFailed'
        if ($note -match 'access is denied|unauthorized') {
            $note = 'Registry key locked by GPO or access denied.'
            $remedyKey = 'RegistryGpo'
        }

        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' -Message "Regional: $note"
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback `
            -ModuleName $moduleName -StepKey 'DecimalAndCurrency' `
            -Event 'Finish' -Kind 'error'

        return [pscustomobject]@{
            Step      = 'DecimalAndCurrency'
            Success   = $false
            LogPath   = $resolvedLogPath
            Error     = $note          # the raw detail, for the log
            RemedyKey = $remedyKey     # what the technician should do
        }
    }
}
```

#tip[
  Understand this module and you understand all eight. `Config-Power` has six
  steps instead of one and `Config-Language` calls different cmdlets, but the
  shape never changes.
]

== A word about `RemedyKey`

Notice what the `catch` block returns. It keeps the raw error *and* names a
remedy — but it does not write the remediation sentence itself.

That is deliberate. The sentence is user-facing text, so it lives in the
translation tables in `Invoke-WcdConfiguration.ps1`, in both languages, next to
every other string a technician reads. The module only says *which* problem this
is; the orchestrator decides how to say it, and in what language.

= Adding a new module

== First: does it need to be a module at all?

Most of what a technician wants to add is *opening or checking an application*,
and that needs no code at all — it is one entry in `WinContextDeploy.psd1`:

```powershell
@{
    Step   = 'AppTimeTracking'
    Name   = 'Time tracking portal'
    Action = 'OpenUrl'
    Target = 'https://time.example.com/'
}
```

That entry gets a progress bar, a checklist row, a log line, an entry in the JSON
report and a remediation sentence when it fails — for free, because
`Config-Applications` already does all of that for every entry in the list.

#warn[
  Write a module only when the manifest genuinely cannot express what you need:
  a registry change, a Windows setting, an inventory check. If the answer is
  "open this" or "check this exists", it is a manifest edit and you are done.
]

== The four steps

#v(0.2cm)
#align(center)[
  #cetz.canvas({
    let step(y, n, body, h: 0.95) = {
      d.circle((0, y), radius: 0.32, fill: accent, stroke: 0.9pt + accentDark)
      d.content((0, y), text(size: 9pt, weight: "bold", fill: white)[#n])
      dnode((6.3, y), box(width: 11.2cm)[
        #set align(left)
        #set par(justify: false, leading: 0.55em)
        #text(size: 8.5pt)[#body]
      ], w: 11.8, h: h)
    }
    step(0, [1], [Create `src/Config-MyThing.ps1` from the template below.])
    step(-1.2, [2], [Write your work in zone 4, and pick a `Step` key for it.])
    step(-2.7, [3], [Register it: the module list and its dispatch case, a
      progress-plan entry, a step label, and a checklist row in both languages.],
      h: 1.5)
    step(-4.2, [4], [Add `tests/Config-MyThing.Tests.ps1` and run the suite.])
    arrow((0, -0.35), (0, -0.85))
    arrow((0, -1.55), (0, -2.3))
    arrow((0, -3.1), (0, -3.85))
  })
]

== The template

Copy this into `src/Config-MyThing.ps1` and replace `MyThing` and `MyStep` with
your own names.

```powershell
# Config-MyThing.ps1 - one line saying what this module is for.
# Entry point: Set-WcdMyThingConfiguration. Requires WcdHelpers.ps1.

function Set-WcdMyThingConfiguration {
    <#
    .SYNOPSIS
        One sentence: what this module does.

    .DESCRIPTION
        A paragraph: how it does it, and anything a reader would otherwise have
        to work out from the code - what needs Administrator, what is deliberately
        left out, what is safe to run twice.

    .PARAMETER LogPath
        Full path to the log file. Resolved automatically when omitted.

    .PARAMETER ProgressCallback
        Scriptblock invoked at the start and end of each step.

    .OUTPUTS
        [pscustomobject[]] with Step, Success, Error and, on a failure, RemedyKey.

    .EXAMPLE
        Set-WcdMyThingConfiguration -LogPath 'C:\temp\log.txt'
    #>
    [CmdletBinding()]
    param(
        [string]$LogPath,
        [scriptblock]$ProgressCallback
    )

    $resolvedLogPath = Resolve-WcdLogPath -CandidatePath $LogPath
    $moduleName = 'Config-MyThing'
    $results = @()

    try {
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback `
            -ModuleName $moduleName -StepKey 'MyStep' -Event 'Start'

        # ------------------------------------------------------------------
        # YOUR WORK GOES HERE
        # ------------------------------------------------------------------

        Write-WcdLog -Path $resolvedLogPath -Level 'INFO' -Message 'MyThing: done.'
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback `
            -ModuleName $moduleName -StepKey 'MyStep' -Event 'Finish' -Kind 'success'
        $results += [pscustomobject]@{ Step = 'MyStep'; Success = $true; Error = '' }
    } catch {
        Write-WcdLog -Path $resolvedLogPath -Level 'ERROR' `
            -Message ('MyThing: {0}' -f $_.Exception.Message)
        Invoke-WcdProgressCallback -ProgressCallback $ProgressCallback `
            -ModuleName $moduleName -StepKey 'MyStep' -Event 'Finish' -Kind 'error'
        $results += [pscustomobject]@{
            Step      = 'MyStep'
            Success   = $false
            Error     = $_.Exception.Message
            RemedyKey = 'MyStepFailed'   # add the sentence to both $T tables
        }
    }

    return $results
}
```

#tip[
  The template raises its own `Finish` event because it has one step. A module
  with several — `Config-Disk` and `Config-Network` both have — should call
  `Complete-WcdProgressStep` instead: it reads the Result your module just
  recorded and picks the right progress kind, so a dozen branches never repeat
  the mapping.

  ```powershell
  Complete-WcdProgressStep -ProgressCallback $ProgressCallback `
      -ModuleName $moduleName -StepKey 'MyStep' -Results $results
  ```
]

== Registering it

Four small edits, all in files you already have.

*In `src/Invoke-WcdConfiguration.ps1`* — add it to the module list and give it a
dispatch case:

```powershell
$modules = @(
    # ... the existing ones ...
    @{ Name = 'Config-MyThing'; File = 'Config-MyThing.ps1' }
)

# and, in the switch:
'Config-MyThing' {
    $modResults = @(Set-WcdMyThingConfiguration -LogPath $resolvedLogPath `
        -ProgressCallback $progressCallback)
}
```

*In `src/WcdHelpers.ps1`* — tell the progress bar how many steps to expect, and
give the step a readable name:

```powershell
# in Get-WcdModuleProgressPlan
'Config-MyThing' = @('MyStep')

# in Get-WcdTechnicalStepLabels
'MyStep' = 'My thing'
```

*Back in `src/Invoke-WcdConfiguration.ps1`* — add a checklist row and its label in
*both* translation tables:

```powershell
# in both $T tables, inside Checklist
MyThing = 'My thing'          # 'Mon truc' in the French table

# in Get-WcdFinalChecklistEntries
$entries += Resolve-WcdAutomaticEntry -Label $T.Checklist.MyThing `
    -ResultLookup $lookup -StepKeys @('MyStep') -StepLabels $StepLabels
```

== Testing it

Every module has a test file, and yours should too. The pattern is always the
same: dot-source the helpers and the module, mock whatever touches the machine,
and assert on the Results.

```powershell
Describe 'Config-MyThing' {
    BeforeAll {
        $srcDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'src'
        . (Join-Path $srcDir 'WcdHelpers.ps1')
        . (Join-Path $srcDir 'Config-MyThing.ps1')
    }

    It 'succeeds when the work goes through' {
        Mock -CommandName 'Set-WcdRegistryValue' {}

        $results = @(Set-WcdMyThingConfiguration -LogPath (Join-Path $TestDrive 'log.txt'))

        $results[0].Step | Should -Be 'MyStep'
        $results[0].Success | Should -BeTrue
    }

    It 'reports a failure without throwing' {
        Mock -CommandName 'Set-WcdRegistryValue' { throw 'Access is denied' }

        $results = @(Set-WcdMyThingConfiguration -LogPath (Join-Path $TestDrive 'log.txt'))

        $results[0].Success | Should -BeFalse
        $results[0].Error | Should -Match 'denied'
    }
}
```

#tip[
  Mock anything that touches the real machine — the registry, `powercfg`,
  `Add-Printer`, `Start-Process`. A test that changes the machine it runs on is
  a test nobody will run twice.

  Run the suite with `Invoke-Pester .\tests\*.Tests.ps1 -Output Detailed`, or by
  double-clicking `Lancer-Tests-Pester.cmd`.
]

= Troubleshooting

== Reading the diagnostic statuses

Every row of the final checklist carries one of five statuses. Telling them apart
is most of what troubleshooting is.

#table(
  columns: (auto, auto, 1fr),
  stroke: none,
  align: (left, left, left),
  inset: (x: 5pt, y: 6pt),
  fill: (_, row) => if calc.odd(row) { greyLight },
  table.header(
    text(weight: "bold")[Status], text(weight: "bold")[Colour], text(weight: "bold")[What it means],
  ),
  text(font: ("DejaVu Sans Mono",), size: 8.5pt, fill: okGreen)[\[x\] OK],
  text(fill: okGreen)[Green],
  [The step did what it was supposed to. It may still carry a note — an Optional
   application that is simply not installed says so here.],

  text(font: ("DejaVu Sans Mono",), size: 8.5pt, fill: warnOrange)[\[!\] WARNING],
  text(fill: warnOrange)[Yellow],
  [Something worth your attention that is not a failure: a VPN client not
   running, a print server out of reach, a power step that needed Administrator.],

  text(font: ("DejaVu Sans Mono",), size: 8.5pt, fill: errRed)[\[!\] ERROR],
  text(fill: errRed)[Red],
  [The step should have worked and did not. Read the remediation on the same
   line; the raw detail is in the log.],

  text(font: ("DejaVu Sans Mono",), size: 8.5pt, fill: grey)[\[-\] MANUAL],
  text(fill: grey)[Yellow],
  [Deliberately not automated. Yours to do — see chapter 4.],

  text(font: ("DejaVu Sans Mono",), size: 8.5pt, fill: grey)[\[-\] N/A],
  text(fill: grey)[Grey],
  [Does not apply to this machine's form factor or environment. Its absence is
   correct, not a problem.],
)

#tip[
  The line under a warning or an error is the one to act on. It names the fix,
  and where a manifest entry is at fault, the exact key to edit:

  #v(4pt)
  #console(
    cline("  [!]  ERP client            ERROR    ERP client not found at C:\\ProgramData\\...", fill: cRed),
    cline("                                      -> Update Applications['ERP client'].Target in", fill: cRed),
    cline("                                         WinContextDeploy.psd1, or remove the entry.", fill: cRed),
  )
]

== Reading the logs

Three files can come out of a run, and they answer different questions.

#table(
  columns: (auto, 1fr),
  stroke: none,
  inset: (x: 5pt, y: 6pt),
  fill: (_, row) => if calc.odd(row) { greyLight },
  [*The run log* \ `src/log.txt`],
  [Everything this run did, line by line, with the *raw* error text. Override the
   location with `-LogPath`. This is where you look when the remediation on
   screen is not enough.],
  [*The history log* \ `-HistoryLogPath`],
  [One block appended per machine — name, serial number, model, user, the whole
   run log and the final diagnostic. One file becomes the record of every machine
   you configured. The `-Usb` launcher points this at the key automatically.],
  [*The JSON report* \ `-ReportPath`],
  [The same result, machine-readable, for collecting across a fleet. Carries a
   `schemaVersion` so a collector can version against it.],
)

Each log line is a timestamp, a level, and a message:

#console(
  cline("2026-08-29 09:14:23 [INFO]  Power: screen timeout on AC set to 15 min."),
  cline("2026-08-29 09:14:23 [INFO]  Power: active scheme applied."),
  cline("2026-08-29 09:14:24 [INFO]  Regional: decimal and currency separators forced to a period."),
  cline("2026-08-29 09:14:25 [ERROR] Taskbar align: Registry key locked by GPO or access denied.", fill: cRed),
  cline("2026-08-29 09:14:26 [INFO]  Display language: fr-CA applied."),
  cline("2026-08-29 09:14:27 [WARNING] Set-WinSystemLocale not applied (Access denied).", fill: cYellow),
)

#note[
  An `[ERROR]` line does not mean the tool crashed. It never stops on a failed
  step: the error is recorded so you can deal with it afterwards, and the run
  continues to the end. A report you can read beats a run that stopped at step
  three.
]

== Common problems

#table(
  columns: (1fr, 1fr, 1.2fr),
  stroke: none,
  inset: (x: 5pt, y: 7pt),
  fill: (_, row) => if calc.odd(row) { greyLight },
  table.header(
    text(weight: "bold")[Symptom], text(weight: "bold")[Likely cause], text(weight: "bold")[What to do],
  ),

  [The window closes immediately],
  [PowerShell execution policy],
  [Launch through `WinContextDeploy.cmd`, never the `.ps1` directly. The launcher
   passes `-ExecutionPolicy Bypass` for exactly this reason.],

  [Every power step says it needs Administrator],
  [You declined the UAC prompt, or the account has no rights to give],
  [Nothing is broken — everything else applied. Relaunch elevated to finish the
   power settings, or accept them as they are.],

  [`Registry key locked by GPO` in the log],
  [Group Policy owns that setting],
  [Expected on a managed machine. The change has to be made in Group Policy; the
   tool cannot and should not fight it.],

  [An application says it was not found],
  [The manifest points at a path that does not exist here],
  [The remediation names the key: fix `Applications['<name>'].Target`, or remove
   the entry if that application is not part of this image.],

  [`Module not found` in the diagnostic],
  [A `Config-*.ps1` is missing or misnamed],
  [Check that the file exists in `src/` and that its name matches the `File`
   value in `$modules`.],

  [`Free space` warns on a machine that is fine],
  [The threshold does not suit this fleet],
  [The remediation names the key: raise or lower `Disk.MinFreeGB` in the manifest.
   It defaults to 20 GB, which is generous on a 128 GB endpoint.],

  [The connectivity test fails on a working network],
  [The network drops ICMP to the internet],
  [Point `Network.PingTarget` in the manifest at your gateway or an internal
   host.],

  [The history export failed after elevating],
  [`-HistoryLogPath` is on a network share],
  [UAC opens a new logon session, which drops mapped drives. Use a local or USB
   path, or run elevated from the start. The tool warns before elevating when it
   sees a UNC path.],

  [A printer never connects],
  [The print server is unreachable, or the queue name is wrong],
  [Check `Printers[].Connection` against what the print server publishes.
   `Name` must match the published queue name for the idempotency check to work.],
)

== Getting more detail

Every function in `src/` carries proper help. When you want to know what
something does or what it returns, ask PowerShell rather than reading the source:

```powershell
Get-Help Set-WcdPowerConfiguration -Full
Get-Help Get-WcdApplicationTarget -Examples
```

And when a change to the code is what you need, the test suite is the fastest way
to find out whether it worked:

```powershell
Invoke-Pester .\tests\*.Tests.ps1 -Output Detailed
```
