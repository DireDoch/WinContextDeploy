## What this changes

<!-- What problem does it solve? Link the issue if there is one. -->

## How it was tested

<!-- Which Pester tests cover it. If something cannot be verified in CI - a real
     print server, a domain, a managed machine - say what you tested by hand. -->

- [ ] `Invoke-Pester .\tests\*.Tests.ps1` is green
- [ ] Tested on a real Windows machine

## Checklist

<!-- Delete what does not apply. -->

- [ ] New/changed `Wcd*` functions have comment-based help (`tests/Help.Tests.ps1` checks this)
- [ ] User-facing text is in **both** `$T` tables, French and English
- [ ] A failure path gives a `RemedyKey`, not just an exception
- [ ] New module registered: `$modules`, dispatch case, progress plan, step label, checklist row
- [ ] README or manual updated if behaviour changed
