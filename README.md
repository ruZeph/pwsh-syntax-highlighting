# pwsh-syntax-highlighting

<img src="assets/icon.png" width="88" align="right" alt="pwsh-syntax-highlighting icon">

[![PowerShell](https://img.shields.io/badge/PowerShell-7%2B-5391FE?logo=powershell&logoColor=white)](https://learn.microsoft.com/powershell/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![PSGallery](https://img.shields.io/powershellgallery/v/pwsh-syntax-highlighting?label=PSGallery)](https://www.powershellgallery.com/packages/pwsh-syntax-highlighting)
[![Fork](https://img.shields.io/badge/Fork-digitalguy99%2Fpwsh--syntax--highlighting-181717?logo=github)](https://github.com/digitalguy99/pwsh-syntax-highlighting)

Interactive syntax highlighting and command validation for PowerShell.

## AI Usage Disclosure

This repository uses AI-assisted development for code generation, refactoring, diagnostics, test scaffolding, and documentation drafting. All AI output is reviewed and edited by a human maintainer before release.

Use of AI-assisted software is entirely your choice. You can use or avoid this project based on your own preferences; no judgment is implied either way.

## Project Notes

- Fork notice: this repository is a fork of <https://github.com/digitalguy99/pwsh-syntax-highlighting>
- Maintainer: <https://github.com/ruZeph>
- Project type: **hobby project for personal use**; this is a voluntary effort to maintain an active fork with quality-of-life improvements
- Status: Actively maintained with a focus on reliability and diagnostic tooling

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
irm 'https://raw.githubusercontent.com/ruZeph/pwsh-syntax-highlighting/main/scripts/install.ps1' | iex
```

The menu supports:

- Install to current user module path
- Update existing installation
- Interactive runtime flag configuration
- Complete uninstall with environment cleanup
- Automatic profile autoload

### Option B: Local dev import (when you already have the folder)

```powershell
Set-Location '<repo-root>'
Remove-Module pwsh-syntax-highlighting -ErrorAction Ignore
Import-Module .\pwsh-syntax-highlighting.psd1 -Force
```

## Version Management

The installer automatically checks for newer versions when you run the update command:

```powershell
# Run the installer to check available versions
irm 'https://raw.githubusercontent.com/ruZeph/pwsh-syntax-highlighting/main/scripts/install.ps1' | iex

# The menu will show:
# - Current installed version (if any)
# - Available version from remote (if newer)
# - Update recommendation when an upgrade is available
```

**Current version**: 1.2.2

To see what's new, check the [repository changelog](https://github.com/ruZeph/pwsh-syntax-highlighting/releases).

## Releases

Release builds are automated by [`.github/workflows/release.yml`](.github/workflows/release.yml).

1. Bump `ModuleVersion` in `pwsh-syntax-highlighting.psd1` and add a matching `## [x.y.z]` section to
   `CHANGELOG.md`.
2. Push to `main`. The workflow validates the manifest, runs PSScriptAnalyzer and the full test
   suite, then creates the `vx.y.z` tag and publishes a GitHub Release containing
   `pwsh-syntax-highlighting-x.y.z.zip` and its `.sha256` checksum.
3. Nothing is published when the manifest version is already tagged, so documentation-only pushes
   stay quiet.

Other entry points:

- Push a `v*` tag by hand - the tag must match `ModuleVersion`, otherwise the run fails with an
  explanation instead of shipping a mislabelled package.
- Re-run the workflow from the Actions tab (or `gh workflow run release.yml`) to rebuild the assets
  for the current `ModuleVersion`; existing release assets are replaced. Set the `dry_run` input to
  build and verify the package without tagging or publishing.

The tag is only created after the tests pass, so a failing build leaves no tag behind. The zip
unpacks as `pwsh-syntax-highlighting/<version>/...`, so extracting it into
`Documents\PowerShell\Modules` is a complete install.

## Upstream Parity

This fork tracks <https://github.com/digitalguy99/pwsh-syntax-highlighting>. The upstream
`3.3.1` line added six fixes after this fork branched; all of them are now present here.

| Upstream change | Status in this fork |
| --- | --- |
| Custom throttle setting (`syntax-highlighting <ms>`) | Ported as `Set-SyntaxHighlightingThrottle` + `syntax-highlighting` alias (default 50ms) |
| Skip reserved keywords (`if`, `foreach`, `function`, `exit`, ...) | Ported, generalised: only tokens flagged `CommandName` by the PowerShell tokenizer are validated |
| Skip `#`, `$`, `(`, `)` | Covered by the same `CommandName` check |
| Leading spaces must not break validation | Covered: token offsets come from the AST, not from line-text regex |
| `CTRL+A` / line-navigation overwrite fix | Covered: navigation keys are re-bound to their PSReadLine functions before rendering |
| Publish workflow | Restored for the `src/` layout (`.github/workflows/publish.yml`) |

Because validation is now driven by `TokenFlags`, the fork no longer needs upstream's
hand-maintained keyword list, and new PowerShell keywords are skipped automatically.

## Features in This Fork

This fork of pwsh-syntax-highlighting includes several enhancements over the original:

### Core Improvements

- **Whole-line validation**: every command token on the line is validated, not just the first
- **Command validation caching**: LRU cache (512 entries, 5s TTL) for expensive `Get-Command` lookups
- **Adaptive throttling**: Tunable render throttle (default 50ms, upstream-compatible) with zero-delay paths for fast keys (arrows, tab, etc.); change it at runtime with `syntax-highlighting 100`
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

## Customization

### Color Themes

The module supports custom color schemes. After installing, add this to your PowerShell profile (after the `Import-Module` line):

```powershell
if (Get-Module pwsh-syntax-highlighting) {
    $module = Get-Module pwsh-syntax-highlighting
    $colors = @{
        ValidCommand   = [System.ConsoleColor]::Green       # Edit as needed
        InvalidCommand = [System.ConsoleColor]::Red         # Edit as needed
    }
    & $module { param($c); $script:Styles = $c } $colors
}
```

See [scripts/example-custom-theme.ps1](scripts/example-custom-theme.ps1) for a complete template.

### Runtime Flags via Bootstrap

Configure runtime flags interactively during installation:

```powershell
# Run the installer with interactive menu
irm 'https://raw.githubusercontent.com/ruZeph/pwsh-syntax-highlighting/main/scripts/install.ps1' | iex

# Menu options:
# 1) Install to current user + autoload in profile
# 2) Update existing installation
# 3) Configure runtime flags  <-- Select this to toggle flags
# 4) Uninstall from current user + remove profile autoload
# Q) Quit
```

In the runtime flags menu, you can toggle:

- **Metrics collection**: Enable `$SyntaxHighlightingMetrics` for performance monitoring
- **Debug tracing**: Enable `$SyntaxHighlightingDebugTrace` for diagnostic logging
- **Safe mode**: Enable safe mode with reduced keymap for compatibility

Flags will be persisted to your user-scope environment when you install or update the module.

### Cleanup Options

The uninstall function now cleans up all related environment variables and profile entries:

```powershell
irm 'https://raw.githubusercontent.com/ruZeph/pwsh-syntax-highlighting/main/scripts/install.ps1' | \
    iex -ArgumentList @('-Uninstall')
```

## Safety Features

The installer includes several safety checks:

- **Confirmation prompts** for destructive operations
- **Profile backup** before modifications (saved as `.pwsh-syntax-highlighting.backup`)
- **Write permission validation** before modifying files or directories
- **Internet connectivity check** before attempting downloads
- **Existing installation detection** with override confirmation
- **Module state check** before operations (warns if module is loaded)
- **Automatic cleanup** of temporary files and profiles on error with rollback

## Known Limitations

### Validation scope

- Every command token on the first input line is validated, including commands after a
  semicolon and either side of a pipeline: `foo; bar`, `a | b`,
  `Get-ChildItem -Path . | Where-Object { $_ } ; foo.exe`.
- Tokens on **continuation lines** (after pressing Enter inside a block or a quote) are
  skipped. PSReadLine indents those rows with a continuation prompt, so a buffer offset no
  longer maps to a fixed screen column and colouring would land on the wrong cells.
- Reserved keywords, variables, comments and operators are intentionally left uncoloured
  (matching upstream), so `if`, `foreach`, `$x` and `#todo` never flash red.

### Paste behaviour

Pasted text does **not** arrive as one event. PSReadLine 2.4 has no bracketed-paste support (no
`ESC[200~` / `ESC[201~` handling in its sources, and `Set-PSReadLineKeyHandler` refuses raw escape
sequences), so every terminal delivers a paste as ordinary key events — right-click paste
included. What differs is only how many events and whether the module is on the path:

- **Keyboard paste** (`Ctrl+V`, `Ctrl+Shift+V`, `Shift+Insert`) is bound by this module, so the
  whole clipboard payload is inserted in one step and painted immediately. Measured: pasting
  `Get-ChildItem; nosuchcmd` colours both commands at once, with no further keystroke
  (`Get-ChildItem` green, `nosuchcmd` red).
- **Terminal-driven paste** (right-click in Windows Terminal or conhost) is turned into individual
  key events by the terminal. The last of those events usually lands inside the render throttle,
  so the line can stay one step stale and gets coloured on your next keystroke. Cosmetic only:
  the command itself is unaffected.
- If you paste a lot, set the throttle to 0 so every keystroke repaints:
  `syntax-highlighting 0`.

## Usage

Type commands directly in the prompt. The first command token is highlighted as valid or invalid while you edit.

### Tuning the throttle

If validation feels laggy (slow terminal, SSH, remote session), raise the throttle. If you
want snappier feedback, lower it. Keys that must feel instant (arrows, `Home`/`End`, `Tab`,
`Space`, `Backspace`/`Delete`) always bypass the throttle.

```powershell
syntax-highlighting 100      # set throttle to 100ms
syntax-highlighting -Get     # show current value
syntax-highlighting -Reset   # back to the 50ms default
```

The equivalent environment variable is `PWSH_SYNTAX_HIGHLIGHTING_THROTTLE_MS` (read at import).

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
- `PWSH_SYNTAX_HIGHLIGHTING_THROTTLE_MS=<ms>`
  - Render throttle in milliseconds (default: 50); same knob as `Set-SyntaxHighlightingThrottle`
- `PWSH_SYNTAX_HIGHLIGHTING_RENDER_ERROR_BUDGET=<n>`
  - Enables automatic degraded mode once repeated render errors are detected (default: 5)
- `PWSH_SYNTAX_HIGHLIGHTING_DEGRADED_RETRY_MS=<ms>`
  - How long degraded mode waits before retrying the render path (default: 60000; 0 retries on
    the next keystroke, use 0 only for debugging)

When a render fails, the message is now kept instead of swallowed:

```powershell
$SyntaxHighlightingMetrics.LastRenderError      # '' when healthy
$SyntaxHighlightingDebugTrace | ? Reason -eq 'exception'   # Detail holds the message
```

## Performance

Measured, not assumed. `scripts/benchmark-render.ps1` benchmarks each component of a keystroke;
run it with `-Json out.json` to compare revisions.

| component | mean | notes |
| --- | --- | --- |
| `tokenize` (parser pass) | 0.03 ms | p99 0.04 ms |
| `paint-warm` (cache hit) | 0.03 ms | predicate + colour decision |
| `paint-cold` (`Get-Command` hit) | 0.12 ms | command resolves |
| `Get-Command` **miss** | **~27 ms** | scans `PSModulePath` for auto-loadable modules |
| `screen-map` (offset to cells) | 0.26 ms | per token |
| full render, live console | 9.8 ms | 79 rises/line, 82 console writes |

The dominant cost is confirming a command that does **not** exist (~27 ms, versus ~0.03 ms for one
that does). Three guards keep that off the keystroke path:

- known-command prefixes short-circuit the lookup (~27 ms to ~0.04 ms), so typing a command you
  have used before never triggers a scan;
- negative answers are cached for 30s (`PWSH_SYNTAX_HIGHLIGHTING_NEGATIVE_TTL_MS`);
- single-character tokens are left uncoloured instead of being looked up.

Live-console render cost per keystroke across revisions, same 61-character line:

| build | ms/render | paint ops | paint chars |
| --- | --- | --- | --- |
| 1.2.0 | 10.91 | 85 | 912 |
| 1.2.2 | 9.79 | 82 | 912 |

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
- Additional pre-built color themes and automatic theme detection

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
|- .github/
|  |- workflows/
|     |- publish.yml (manual-only PSGallery publish; disabled)
|     |- release.yml (tested build, tag and GitHub Release from ModuleVersion)
|     |- test.yml (manifest, analyzer and test suites)
|- assets/
|  |- icon.png (module/gallery icon, referenced by psd1 IconUri)
|- docs/
|  |- perf-and-hardening.md
|- scripts/
  |- install.ps1 (main installer with safety checks)
  |- build-icon.ps1 (regenerates assets/icon.png)
  |- example-custom-theme.ps1
  |- manual-test-setup-env.ps1
  |- validate-gate.ps1
  |- benchmark-render.ps1
|- src/
|  |- pwsh-syntax-highlighting.psm1
|- tests/
|  |- test-all.ps1
|  |- test-installer.ps1
|  |- test-local.ps1
|  |- test-scenarios.ps1
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
