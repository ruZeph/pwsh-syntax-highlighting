# AI Usage Disclosure

This repository uses AI-assisted development for code generation, refactoring, diagnostics, test scaffolding, and documentation drafting. All AI output is reviewed and edited by a human maintainer before release.

# pwsh-syntax-highlighting

Interactive syntax highlighting and command validation for PowerShell.

This project is inspired by zsh-syntax-highlighting:
https://github.com/zsh-users/zsh-syntax-highlighting

## Status

- Project/repo naming aligned to pwsh-syntax-highlighting
- Module manifest renamed to pwsh-syntax-highlighting.psd1
- Module implementation moved into src/ for cleaner layout
- Reliability tooling and hardening docs included

## Requirements

- PowerShell 7+ recommended
- PSReadLine enabled (default in modern PowerShell)

## Repository Structure

```text
.
|- docs/
|  |- perf-and-hardening.md
|- scripts/
|  |- benchmark-render.ps1
|  |- manual-test-setup-env.ps1
|  |- validate-gate.ps1
|- src/
|  |- pwsh-syntax-highlighting.psm1
|- tests/
|  |- test-local.ps1
|- LICENSE
|- README.md
|- pwsh-syntax-highlighting.psd1
```

## Quick Start (Local)

```powershell
Set-Location "<repo-root>"
Remove-Module pwsh-syntax-highlighting -ErrorAction Ignore
Import-Module .\pwsh-syntax-highlighting.psd1 -Force
```

Type commands directly in the prompt. The first command token is highlighted as valid or invalid while you edit.

## Operational Flags

- PWSH_SYNTAX_HIGHLIGHTING_METRICS=1
  - Publishes runtime counters to $SyntaxHighlightingMetrics
- PWSH_SYNTAX_HIGHLIGHTING_DEBUG=1
  - Publishes debug trace events to $SyntaxHighlightingDebugTrace
- PWSH_SYNTAX_HIGHLIGHTING_SAFE_MODE=1
  - Uses reduced-risk keymap and conservative behavior
- PWSH_SYNTAX_HIGHLIGHTING_MAX_LENGTH=<n>
  - Skips highlighting on very long input lines
- PWSH_SYNTAX_HIGHLIGHTING_MAX_COMMAND_LENGTH=<n>
  - Limits expensive command lookup for very long first tokens
- PWSH_SYNTAX_HIGHLIGHTING_RENDER_ERROR_BUDGET=<n>
  - Enables automatic degraded mode once repeated render errors are detected

## Reliability and Performance Checks

Run all local checks and benchmark in one command:

```powershell
.\scripts\validate-gate.ps1
```

Run only reliability checks:

```powershell
.\tests\test-local.ps1 -Cycles 100
```

Run micro-benchmark only:

```powershell
.\scripts\benchmark-render.ps1 -Iterations 1000 -WarmupIterations 200
```

## Troubleshooting

If your shell appears to be in a stale key-handler state, use the reset sequence documented in:

- docs/perf-and-hardening.md

Then import the module again.

## Licensing

Licensed under MIT. See LICENSE.

## Credits

- Original project authors: Brian Tannert and Rajeswar Khan
- Ongoing maintenance and fork hardening: contributors
