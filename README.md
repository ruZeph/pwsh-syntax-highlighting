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
- Update existing installation
- Automatic profile autoload
- Uninstall and profile cleanup

### Option B: Local dev import (when you already have the folder)

```powershell
Set-Location '<repo-root>'
Remove-Module pwsh-syntax-highlighting -ErrorAction Ignore
Import-Module .\pwsh-syntax-highlighting.psd1 -Force
```

## Features in This Fork

This fork of pwsh-syntax-highlighting includes several enhancements over the original:

### Core Improvements

- **Command validation caching**: LRU cache (512 entries, 5s TTL) for expensive `Get-Command` lookups
- **Adaptive throttling**: Render throttling (30ms minimum interval) with zero-delay paths for fast keys (arrows, tab, etc.)
- **Safe mode**: Optional reduced-risk keymap via `PWSH_SYNTAX_HIGHLIGHTING_SAFE_MODE=1`
- **Error resilience**: Automatic degradation to safe mode after repeated render failures
- **Telemetry & diagnostics**: Optional metrics (`$SyntaxHighlightingMetrics`) and debug tracing (`$SyntaxHighlightingDebugTrace`)

### Performance Optimizations

- Command lookup skipped for very long inputs (configurable via `PWSH_SYNTAX_HIGHLIGHTING_MAX_LENGTH`)
- Long command token lookup disabled or rate-limited (configurable via `PWSH_SYNTAX_HIGHLIGHTING_MAX_COMMAND_LENGTH`)
- Render signature tracking prevents redundant repaints for unchanged buffer state
- Best-effort diagnostics that cannot break key handlers or input processing

### Hardening

- Preflight checks validate PSReadLine availability and required methods
- Key handler registration wrapped in try/catch to prevent uninstall failures
- Graceful fallback to degraded mode instead of hard failures

## Known Limitations

### Right-Click Paste in Windows Terminal

Right-click paste is a built-in Windows Terminal feature that bypasses PowerShell's PSReadLine key handler system. This means:

- **Keyboard paste** (`Ctrl+V`, `Shift+Insert`) will trigger syntax highlighting immediately
- **Right-click paste** will insert text without immediate syntax highlighting; highlighting appears after the next render cycle (when you press a key or after ~30ms)

This is by design—no workaround exists for intercepting Windows Terminal's native right-click paste through PSReadLine APIs reliably.

## Usage

Type commands directly in the prompt. The first command token is highlighted as valid or invalid while you edit.

## Runtime Flags

- `PWSH_SYNTAX_HIGHLIGHTING_METRICS=1`
  - Publishes runtime counters to `$SyntaxHighlightingMetrics`
- `PWSH_SYNTAX_HIGHLIGHTING_DEBUG=1`
  - Publishes debug trace events to `$SyntaxHighlightingDebugTrace`
- `PWSH_SYNTAX_HIGHLIGHTING_SAFE_MODE=1`
  - Uses reduced-risk keymap and conservative behavior
- `PWSH_SYNTAX_HIGHLIGHTING_MAX_LENGTH=<n>`
  - Skips highlighting on very long input lines
- `PWSH_SYNTAX_HIGHLIGHTING_MAX_COMMAND_LENGTH=<n>`
  - Limits expensive command lookup for very long first tokens
- `PWSH_SYNTAX_HIGHLIGHTING_RENDER_ERROR_BUDGET=<n>`
  - Enables automatic degraded mode once repeated render errors are detected (default: 5)

## Performance Strategy

This module is inspired by and optimized using principles from [zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting):

### Key Optimizations

1. **Command Resolution Caching**: Expensive `Get-Command` lookups are cached with a 5-second TTL and LRU eviction to prevent repeated lookups for the same commands during typical usage patterns.

2. **Adaptive Throttling**: Render operations are throttled to a 30ms minimum interval for most keys, but zero-delay paths are maintained for fast navigation keys (arrows, tab) to keep the UX responsive.

3. **Incremental Rendering**: The module tracks render signatures (buffer state, cursor position, token) to skip redundant repaints when nothing changed.

4. **Conservative Defaults**: Safe Mode (`PWSH_SYNTAX_HIGHLIGHTING_SAFE_MODE=1`) reduces the key handler set to essential operations, minimizing compatibility issues.

5. **Error Budgeting**: Instead of failing hard on render errors, the module tracks errors and automatically downgrades to degraded mode after a configurable threshold, allowing graceful degradation under stress.

### Future Performance Enhancements

Planned optimizations inspired by zsh-syntax-highlighting's architecture:

- Pluggable highlighter system to allow users to enable/disable specific highlighting rules
- Async/background command validation via background jobs  
- Incremental token painting (only repaint changed tokens, not entire buffer)
- User-configurable highlighting semantics and color schemes

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
