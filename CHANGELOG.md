# Changelog

All notable changes to pwsh-syntax-highlighting are documented in this file.

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
