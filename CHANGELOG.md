# Changelog

All notable changes to pwsh-syntax-highlighting are documented in this file.

## [1.2.0] - 2026-05-06

### Added

- **Whole-line validation.** Every command token on the line is validated instead of only the
  first, so `foo; bar`, `a | b` and `Get-ChildItem | Where-Object { $_ } ; foo.exe` colour each
  command correctly. Token selection is driven by the same `CommandName` token flag, so
  keywords, variables and comments stay uncoloured.
- **`Get-ScreenRunForToken`** maps a buffer offset/length onto terminal cells and returns
  per-row runs, so painting is correct when a command wraps or follows other text. Replaces the
  previous "token starts at cursor origin + offset" assumption.

### Fixed

- **Degraded mode was permanent.** Once the render error budget tripped, highlighting stayed off
  for the rest of the session with no way back, so one transient failure (a resize, a paste burst,
  a console API hiccup) silently disabled the module. It now retries after
  `PWSH_SYNTAX_HIGHLIGHTING_DEGRADED_RETRY_MS` (default 60s) and clears itself on success.
- **Render failures were undiagnosable.** The catch block discarded the exception, so a broken
  render path looked like "colouring just stopped working". The message is now stored in
  `$SyntaxHighlightingMetrics.LastRenderError`, added to debug trace events as `Detail`, and an
  `error-budget-tripped` event records the trip.

### Changed

- Render path paints each target token through the new mapping, batching one
  `GetBufferContents`/`SetBufferContents` pair per row run and skipping rows whose colour is
  already correct.
- Render signature now covers every visible token (text, offset, length, colour), so edits
  anywhere on the line trigger a repaint instead of only edits to the first token.
- Screen-offset mapping and the degraded-mode gate live in module scriptblocks, not functions:
  the render action is built with `GetNewClosure()`, and a closure resolves scriptblock
  variables but not module functions.

### Remaining limitation

- Tokens on continuation lines (after Enter inside a block) are skipped, because PSReadLine may
  prefix those rows with a continuation prompt; a buffer offset no longer maps to a fixed screen
  column. Documented in the README.

## [1.1.0] - 2026-05-06

### Upstream parity merge (digitalguy99/pwsh-syntax-highlighting 3.3.1)

Merged the six upstream commits made after this fork branched. Upstream's fixes were
re-implemented in the fork's architecture rather than copied, because the fork's render
path (AST token extents, caching, telemetry) differs from upstream's line-text regex.

### Added

- **`Set-SyntaxHighlightingThrottle`** with the upstream-compatible `syntax-highlighting`
  alias. `syntax-highlighting 100` sets the throttle, `-Get` reads it, `-Reset` restores the
  50ms default. `PWSH_SYNTAX_HIGHLIGHTING_THROTTLE_MS` works as an import-time equivalent.
- **`.github/workflows/publish.yml`** restored for the new `src/` layout, with a staged
  publish directory and manifest validation before `Publish-Module`.
- Tests: token-gating cases (keywords, variables, comments, operators, strings) and
  throttle command/alias assertions in `tests/test-local.ps1`.

### Changed

- **Validation is gated on `TokenFlags`**: only tokens flagged `CommandName` are validated.
  This replaces upstream's hardcoded reserved-keyword list, so `if`/`foreach`/`function`/
  `exit`/`return`/`try`/`trap`/`throw`/`switch`/`while`/`do`/`class`/`enum`/`workflow`,
  variables (`$x`, `@args`), comments, numbers, strings and grouping characters are all
  skipped automatically — no list to maintain when PowerShell adds keywords.
- Default render throttle is now 50ms (upstream parity), still bypassed for navigation and
  text-insert keys (arrows, Home/End, Tab, Space, Backspace/Delete).
- Version is single-sourced from the module manifest: `scripts/install.ps1` (local version +
  remote version parsing) and the test suites no longer hardcode `1.0.0`.
- **`Publish` workflow is manual-only and disabled** until the `PSG_API_KEY` repository secret
  exists; a push trigger made every module commit a red build for a release that was not
  intended to ship.

### Fixed

- **Publish workflow could not see the gallery key.** The secret was interpolated inline, so an
  unset secret collapsed into `Publish-Module -NuGetApiKey` with no argument and the run failed
  with "Missing an argument for parameter 'NuGetApiKey'". The key is now passed through
  `env: PSG_API_KEY` and validated first, failing with an annotated error that names the missing
  repository secret. Added a guard that skips publishing when PSGallery already has that version
  (so non-version-bump pushes to `src/` do not turn the build red).
- **Gallery icon pointed at someone else's CDN.** `IconUri` referenced the `evgeniypeshkov`
  VS Code extension icon on `gallerycdn.vsassets.io`. It now points at `assets/icon.png` in this
  repository, and the README shows the same icon. The hardcoded `Version` badge was replaced with
  a live PSGallery version badge so it cannot drift from the manifest.
- Importing the module in a host without PSReadLine (non-interactive `pwsh`, CI) no longer
  throws `Unable to find type [Microsoft.PowerShell.PSConsoleReadLine]`; preflight now
  reports the failure cleanly and leaves the session untouched.
- Installer update detection parsed only the literal `1.0.0` in the remote manifest, so any
  newer release reported "no update available". It now parses the real `ModuleVersion`.

## [1.0.0] - 2026-04-06

### Major Release - First Stable Version

This is the first stable release of the enhanced pwsh-syntax-highlighting fork with comprehensive safety features, version management, and production-ready testing.

### Added

#### Safety & Reliability
- **Comprehensive Safety Checks**: Internet connectivity validation, write permission checks, profile backups
- **User Confirmations**: Confirmation prompts for all destructive operations (install, update, uninstall)
- **Error Handling**: Automatic rollback and recovery mechanisms on failure
- **Module State Detection**: Checks for loaded modules before operations

#### Installation & Management
- **Interactive Menu**: User-friendly menu-driven installation configuration
- **Version Management**: Automatic remote version checking with upgrade detection
- **Profile Management**: Safe profile modification with backup/restore capabilities
- **Runtime Flags**: User-configurable flags for metrics, debug tracing, and safe mode

#### Testing & Quality
- **Master Test Orchestrator**: Unified test runner (test-all.ps1) with progress tracking
- **Installer Tests**: 30+ static analysis tests validating all features (60/60 passing)
- **Scenario Tests**: Integration tests for module loading, flags, and cleanup
- **Quick Mode**: Fast validation tests for CI/CD pipelines (0.16s)

#### Code Quality
- **PSScriptAnalyzer Compliance**: All approved verbs, no warnings
- **iex Compatibility**: Works perfectly with one-liner installation
- **Markdown Linting**: README passes all markdown lint checks

### Changed  

- Replaced bootstrap-installer.ps1 with install.ps1 (cleaner naming)
- Converted command-line parameters to interactive menu (better UX)
- Refactored flag handling for environment variable persistence
- Simplified regex patterns for Invoke-Expression compatibility

### Fixed

- Fixed PSScriptAnalyzer warning: Replaced unapproved verb "Ensure" with "Initialize"
- Fixed iex parsing issues with complex regex patterns
- Fixed markdown linting: Added blank line after main heading (MD022)
- Fixed unused variable warnings in install.ps1

### Documentation

- Added comprehensive "Version Management" section to README
- Added "Safety Features" section documenting all checks
- Added "Runtime Flags" documentation
- Added "Performance Strategy" section

### Testing

- ✓ 60/60 installer tests passing
- ✓ Syntax validation passing
- ✓ All required functions present  
- ✓ Safety features validated
- ✓ Runtime flags supported
- ✓ Module manifest consistent

### Installation

```powershell
# One-liner (recommended)
irm 'https://raw.githubusercontent.com/ruZeph/pwsh-syntax-highlighting/main/scripts/install.ps1' | iex

# Local dev import
Set-Location '<repo-root>'
Import-Module .\pwsh-syntax-highlighting.psd1 -Force
```

### What's Next

Planned enhancements for future releases:
- Pluggable highlighter system for custom rules
- Async/background command validation
- Incremental token painting
- Additional pre-built color themes
- Automatic theme detection

---

## Version Strategy

This project uses [Semantic Versioning](https://semver.org/):
- **MAJOR**: Breaking changes (e.g., 2.0.0)
- **MINOR**: New features (e.g., 1.1.0)
- **PATCH**: Bug fixes (e.g., 1.0.1)

Starting point: 1.0.0 (first stable release)
