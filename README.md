# pwsh-syntax-highlighting

[![PowerShell](https://img.shields.io/badge/PowerShell-7%2B-5391FE?logo=powershell&logoColor=white)](https://learn.microsoft.com/powershell/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Fork](https://img.shields.io/badge/Fork-digitalguy99%2Fpwsh--syntax--highlighting-181717?logo=github)](https://github.com/digitalguy99/pwsh-syntax-highlighting)
[![PSGallery](https://img.shields.io/badge/PSGallery-Not%20Published-lightgrey)](#installation)

Interactive syntax highlighting and command validation for PowerShell.

## AI Usage Disclosure

This repository uses AI-assisted development for code generation, refactoring, diagnostics, test scaffolding, and documentation drafting. All AI output is reviewed and edited by a human maintainer before release.

Use of AI-assisted software is entirely your choice. You can use or avoid this project based on your own preferences; no judgment is implied either way.

## Project Notes

- Fork notice: this repository is a fork of <https://github.com/digitalguy99/pwsh-syntax-highlighting>
- Maintainer: <https://github.com/ruZeph>
- Project type: hobby project focused on practical PowerShell UX improvements

## Why This Fork Exists

- Preserve and maintain the project with active fixes and compatibility updates
- Improve interactive reliability for modern PSReadLine behavior
- Add hardening, diagnostics, and local validation tooling for safer releases
- Keep the original project name for continuity and discoverability

Inspired by zsh-syntax-highlighting: <https://github.com/zsh-users/zsh-syntax-highlighting>

## Installation

This fork is currently not published to PowerShell Gallery.

### Option A: One-liner bootstrap script (no clone)

Run this to open an interactive installer menu.

```powershell
irm 'https://raw.githubusercontent.com/ruZeph/pwsh-syntax-highlighting/main/scripts/bootstrap-installer.ps1' | iex
```

The menu supports:

- Install to current user module path
- Automatic profile autoload
- Uninstall and profile cleanup

### Option B: Direct one-liner install (non-interactive)

```powershell
& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/ruZeph/pwsh-syntax-highlighting/main/scripts/bootstrap-installer.ps1'))) -Install
```

### Option C: Direct one-liner uninstall (non-interactive)

```powershell
& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/ruZeph/pwsh-syntax-highlighting/main/scripts/bootstrap-installer.ps1'))) -Uninstall
```

### Option D: Local dev import (when you already have the folder)

```powershell
Set-Location '<repo-root>'
Remove-Module pwsh-syntax-highlighting -ErrorAction Ignore
Import-Module .\pwsh-syntax-highlighting.psd1 -Force
```

## Usage

Type commands directly in the prompt. The first command token is highlighted as valid or invalid while you edit.

## Runtime Flags

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

## Validation and Benchmark

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

## Repository Layout

```text
.
|- docs/
|  |- perf-and-hardening.md
|- scripts/
|  |- benchmark-render.ps1
|  |- bootstrap-installer.ps1
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

## Troubleshooting

If your shell appears to be in a stale key-handler state, use the reset sequence documented in docs/perf-and-hardening.md, then import the module again.

## License

Licensed under MIT. See LICENSE.

## Credits

- Original project authors: Brian Tannert and Rajeswar Khan
- Upstream repository: <https://github.com/digitalguy99/pwsh-syntax-highlighting>
- Fork maintenance: <https://github.com/ruZeph>
