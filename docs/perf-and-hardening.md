# Performance and Hardening Runbook

This document describes operational controls and diagnostics for the module.

## Runtime Flags

- `PWSH_SYNTAX_HIGHLIGHTING_METRICS=1`
  - Enables metrics publication to `$SyntaxHighlightingMetrics`.
- `PWSH_SYNTAX_HIGHLIGHTING_DEBUG=1`
  - Enables debug event trace publication to `$SyntaxHighlightingDebugTrace`.
- `PWSH_SYNTAX_HIGHLIGHTING_SAFE_MODE=1`
  - Enables reduced-risk mode with a smaller compatibility keymap.
- `PWSH_SYNTAX_HIGHLIGHTING_MAX_LENGTH=<n>`
  - Skips highlighting for very long command lines.
- `PWSH_SYNTAX_HIGHLIGHTING_MAX_COMMAND_LENGTH=<n>`
  - Limits expensive command resolution for very long first tokens.
- `PWSH_SYNTAX_HIGHLIGHTING_RENDER_ERROR_BUDGET=<n>`
  - Maximum render exceptions before degraded mode is activated.

## Safety Design

- Debug tracing is best-effort and cannot break key handlers.
- Render exceptions are counted in `RenderErrors`.
- When `RenderErrors` reaches `RenderErrorBudget`, the module:
  - enters degraded mode,
  - disables debug tracing,
  - continues in a safer behavior profile.
- Preflight runs at import and publishes capability status in metrics.

## Metrics Fields

`$SyntaxHighlightingMetrics` includes:

- `RenderCalls`
- `Throttled`
- `NoToken`
- `SkippedUnchanged`
- `RenderErrors`
- `ErrorBudgetTrips`
- `RegistrationSkipped`
- `CacheHit`
- `CacheMiss`
- `PaintOps`
- `PaintChars`
- `NoColorWrite`
- `TotalRenderMs`
- `SafeMode`
- `DegradedMode`
- `RenderErrorBudget`
- `PreflightPassed`

## Debug Trace Fields

`$SyntaxHighlightingDebugTrace` entries include:

- `Timestamp`
- `Reason`
- `Key`
- `TokenText`

Typical `Reason` values:

- `throttled`
- `no-token`
- `whitespace-token`
- `host-missing`
- `invalid-token-length`
- `max-buffer-length`
- `no-color`
- `skipped-unchanged`
- `painted`
- `exception`
- `degraded-mode-skip`

## Recovery: Reset Key Handlers

If a terminal session is already in a bad key-handler state, reset once:

```powershell
$printable = [char[]](0x20..0x7e + 0xa0..0xff)
foreach ($k in $printable) { Set-PSReadLineKeyHandler -Key $k -Function SelfInsert -ErrorAction SilentlyContinue }
Set-PSReadLineKeyHandler -Key Tab -Function Complete -ErrorAction SilentlyContinue
Set-PSReadLineKeyHandler -Key UpArrow -Function PreviousHistory -ErrorAction SilentlyContinue
Set-PSReadLineKeyHandler -Key DownArrow -Function NextHistory -ErrorAction SilentlyContinue
Set-PSReadLineKeyHandler -Key RightArrow -Function ForwardChar -ErrorAction SilentlyContinue
Set-PSReadLineKeyHandler -Key LeftArrow -Function BackwardChar -ErrorAction SilentlyContinue
Set-PSReadLineKeyHandler -Key Backspace -Function BackwardDeleteChar -ErrorAction SilentlyContinue
Set-PSReadLineKeyHandler -Key Delete -Function DeleteChar -ErrorAction SilentlyContinue
```

Then re-import the module.

## Gate Command

Run all local checks and benchmark in one command:

```powershell
.\scripts\validate-gate.ps1
```

Useful overrides:

```powershell
.\scripts\validate-gate.ps1 -Cycles 100 -BenchmarkIterations 1000 -BenchmarkWarmup 200
```
