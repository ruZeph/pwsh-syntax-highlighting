$global:lastRender = Get-Date
$script:LastRenderTick = [Environment]::TickCount64

$script:CommandLookupCache = @{}
$script:CommandLookupOrder = [System.Collections.Generic.Queue[string]]::new()
$script:CommandCacheMaxSize = 512
$script:CommandCacheTtlMs = 5000
# A name that does not exist is far more expensive to confirm than one that does: Get-Command
# spends ~27ms scanning PSModulePath for auto-loadable modules, versus ~0.03ms for a hit. Keep
# negative answers longer, and remember the prefixes of known commands so typing them never
# triggers that scan (see KnownCommandPrefixes below).
$script:NegativeCacheTtlMs = if ($env:PWSH_SYNTAX_HIGHLIGHTING_NEGATIVE_TTL_MS) { [int]$env:PWSH_SYNTAX_HIGHLIGHTING_NEGATIVE_TTL_MS } else { 30000 }
$script:KnownCommandPrefixes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$script:KnownCommandPrefixLimit = 20000
$script:MaxBufferLength = if ($env:PWSH_SYNTAX_HIGHLIGHTING_MAX_LENGTH) { [int]$env:PWSH_SYNTAX_HIGHLIGHTING_MAX_LENGTH } else { 0 }
$script:MaxCommandLookupLength = if ($env:PWSH_SYNTAX_HIGHLIGHTING_MAX_COMMAND_LENGTH) { [int]$env:PWSH_SYNTAX_HIGHLIGHTING_MAX_COMMAND_LENGTH } else { 256 }

# Throttle in milliseconds. Matches upstream's default of 50ms and is user-tunable
# via Set-SyntaxHighlightingThrottle (alias: syntax-highlighting).
$script:ThrottleLimit = if ($env:PWSH_SYNTAX_HIGHLIGHTING_THROTTLE_MS) { [int]$env:PWSH_SYNTAX_HIGHLIGHTING_THROTTLE_MS } else { 50 }
if ($script:ThrottleLimit -lt 0) { $script:ThrottleLimit = 0 }

$script:Styles = @{
    ValidCommand   = [System.ConsoleColor]::Green
    InvalidCommand = [System.ConsoleColor]::Red
}

$script:Highlighters = @(
    @{
        Name      = 'main-command'
        Predicate = {
            param($ctx)

            # Only a real command-name token is validated. This single check replaces
            # upstream's hardcoded skip list: reserved keywords (if/foreach/function/
            # exit/return/...), variables ($x, @args), comments (#...), numbers,
            # strings, grouping/operators and brackets are all non-command tokens.
            if ([string]::IsNullOrWhiteSpace($ctx.TokenText)) { return $false }
            if ($ctx.TokenText.Contains('[') -or $ctx.TokenText.Contains(']')) { return $false }

            $commandNameFlag = [System.Management.Automation.Language.TokenFlags]::CommandName
            return [bool]($ctx.Token.TokenFlags -band $commandNameFlag)
        }
        Paint     = {
            param($ctx)

            if ($script:MaxCommandLookupLength -gt 0 -and $ctx.TokenText.Length -gt $script:MaxCommandLookupLength) {
                return $script:Styles.InvalidCommand
            }

            # A single character is never a settled command name; leave the colour alone rather
            # than spend a command lookup (and a red flash) on every first keystroke.
            if ($ctx.TokenText.Length -lt 2) {
                return $null
            }

            # If a known-good command starts with this text, the user is still typing that
            # command. Trust it and skip the lookup: confirming a *non*-existent name is ~27ms.
            if ($script:KnownCommandPrefixes.Contains($ctx.TokenText)) {
                if ($script:EnableTelemetry) { $script:Perf.PrefixShortCircuit++ }
                return $script:Styles.ValidCommand
            }

            $nowTicks = [Environment]::TickCount64
            $cacheEntry = $script:CommandLookupCache[$ctx.TokenText]
            if ($cacheEntry) {
                $ttl = if ([bool]$cacheEntry.Exists) { $script:CommandCacheTtlMs } else { $script:NegativeCacheTtlMs }
                if (($nowTicks - [int64]$cacheEntry.Tick) -lt $ttl) {
                    if ($script:EnableTelemetry) { $script:Perf.CacheHit++ }
                    if ([bool]$cacheEntry.Exists) {
                        return $script:Styles.ValidCommand
                    }
                    return $script:Styles.InvalidCommand
                }
            }

            if ($cacheEntry) {
                $script:CommandLookupCache.Remove($ctx.TokenText) | Out-Null
            }

            if ($script:EnableTelemetry) { $script:Perf.CacheMiss++ }
            $exists = [bool](Get-Command -Name $ctx.TokenText -ErrorAction Ignore)
            $script:CommandLookupCache[$ctx.TokenText] = @{
                Exists = $exists
                Tick   = $nowTicks
            }
            $script:CommandLookupOrder.Enqueue($ctx.TokenText)

            while ($script:CommandLookupOrder.Count -gt $script:CommandCacheMaxSize) {
                $oldest = $script:CommandLookupOrder.Dequeue()
                if ($script:CommandLookupCache.ContainsKey($oldest)) {
                    $script:CommandLookupCache.Remove($oldest) | Out-Null
                }
            }

            if ($exists) {
                # Remember every prefix of a real command so typing it again stays lookup-free.
                if ($script:KnownCommandPrefixes.Count -lt $script:KnownCommandPrefixLimit) {
                    for ($prefixLength = 2; $prefixLength -lt $ctx.TokenText.Length; $prefixLength++) {
                        [void]$script:KnownCommandPrefixes.Add($ctx.TokenText.Substring(0, $prefixLength))
                    }
                }
                return $script:Styles.ValidCommand
            }

            return $script:Styles.InvalidCommand
        }
    }
)

$script:LastRenderSignature = ''
$script:LastPaintedLength = -1
$script:VerifiedOriginX = -1
$script:VerifiedOriginY = -1
$script:SafeMode = ($env:PWSH_SYNTAX_HIGHLIGHTING_SAFE_MODE -eq '1')
$script:EnableTelemetry = ($env:PWSH_SYNTAX_HIGHLIGHTING_METRICS -eq '1')
$script:EnableDebugTrace = (-not $script:SafeMode) -and ($env:PWSH_SYNTAX_HIGHLIGHTING_DEBUG -eq '1')
$script:RenderErrorBudget = if ($env:PWSH_SYNTAX_HIGHLIGHTING_RENDER_ERROR_BUDGET) { [int]$env:PWSH_SYNTAX_HIGHLIGHTING_RENDER_ERROR_BUDGET } else { 5 }
$script:DegradedMode = $false
$script:LastRenderError = ''
$script:DegradedSince = [int64]0
$script:DegradedRetryMs = if ($env:PWSH_SYNTAX_HIGHLIGHTING_DEGRADED_RETRY_MS) { [int]$env:PWSH_SYNTAX_HIGHLIGHTING_DEGRADED_RETRY_MS } else { 60000 }
$script:DebugTrace = New-Object System.Collections.Generic.List[object]
$script:Preflight = [ordered]@{
    Passed                   = $false
    HostSupportsRawUI        = $false
    PSReadLineLoaded         = $false
    KeyHandlerCommandPresent = $false
    MissingMethods           = @()
}
$script:Perf = [ordered]@{
    RenderCalls         = 0
    Throttled           = 0
    NoToken             = 0
    SkippedUnchanged    = 0
    RenderErrors        = 0
    ErrorBudgetTrips    = 0
    RegistrationSkipped = 0
    CacheHit            = 0
    CacheMiss           = 0
    PrefixShortCircuit  = 0
    PaintOps            = 0
    PaintVerifyFails    = 0
    PaintChars          = 0
    NoColorWrite        = 0
    TotalRenderMs       = 0.0
}

$script:AddDebugTraceEvent = {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Reason,

        $Key = $null,

        [string]$TokenText = '',

        [string]$Detail = ''
    )

    try {
        if (-not $script:EnableDebugTrace) {
            return
        }

        if ($script:DebugTrace.Count -ge 300) {
            $script:DebugTrace.RemoveAt(0)
        }

        $script:DebugTrace.Add([pscustomobject]@{
                Timestamp = (Get-Date)
                Reason    = $Reason
                Key       = if ($null -eq $Key) { 'NoName' } else { [string]$Key }
                TokenText = $TokenText
                Detail    = $Detail
            })

        # Keep debug plumbing best-effort; never let tracing break key handlers.
        $global:SyntaxHighlightingDebugTrace = [object[]]$script:DebugTrace.ToArray()
    }
    catch {
        return
    }
}.GetNewClosure()

$script:PublishMetrics = {
    $m = [ordered]@{}
    foreach ($k in $script:Perf.Keys) {
        $m[$k] = $script:Perf[$k]
    }
    $m.SafeMode = $script:SafeMode
    $m.DegradedMode = $script:DegradedMode
    $m.ThrottleLimit = $script:ThrottleLimit
    $m.RenderErrorBudget = $script:RenderErrorBudget
    $m.DegradedRetryMs = $script:DegradedRetryMs
    $m.PreflightPassed = $script:Preflight.Passed
    $m.LastRenderError = $script:LastRenderError
    $global:SyntaxHighlightingMetrics = [pscustomobject]$m
}.GetNewClosure()

function Invoke-SyntaxHighlightingPreflight {
    $requiredMethods = @(
        'GetBufferState',
        'SetCursorPosition',
        'Insert',
        'TabCompleteNext',
        'PreviousHistory',
        'NextHistory',
        'ForwardChar',
        'BackwardChar',
        'BeginningOfLine',
        'EndOfLine',
        'NextWord',
        'BackwardWord',
        'TabCompletePrevious',
        'BackwardDeleteChar',
        'DeleteChar'
    )

    $availableMethodNames = @()
    try {
        $availableMethodNames = @([Microsoft.PowerShell.PSConsoleReadLine].GetMethods() | Select-Object -ExpandProperty Name -Unique)
    }
    catch {
        # PSReadLine type is not loaded in this host (e.g. non-interactive pwsh).
        # Preflight will fail cleanly instead of throwing a type-resolution error.
        $availableMethodNames = @()
    }
    $missing = @()
    foreach ($name in $requiredMethods) {
        if ($name -notin $availableMethodNames) {
            $missing += $name
        }
    }

    $script:Preflight.HostSupportsRawUI = ($null -ne $host -and $null -ne $host.UI -and $null -ne $host.UI.RawUI)
    $script:Preflight.PSReadLineLoaded = ($null -ne (Get-Module PSReadLine -ErrorAction SilentlyContinue))
    $script:Preflight.KeyHandlerCommandPresent = ($null -ne (Get-Command Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue))
    $script:Preflight.MissingMethods = $missing
    $script:Preflight.Passed = $script:Preflight.HostSupportsRawUI -and $script:Preflight.PSReadLineLoaded -and $script:Preflight.KeyHandlerCommandPresent -and ($missing.Count -eq 0)
}

# Screen-offset mapping lives in a scriptblock, not a function: the render action is built
# with GetNewClosure(), and a closure resolves scriptblock variables but not module functions.
$script:EnterRenderGate = {
    param($Key)

    if (-not $script:DegradedMode) { return $true }

    $degradedForMs = [Environment]::TickCount64 - $script:DegradedSince
    if ($script:DegradedRetryMs -gt 0 -and $degradedForMs -ge $script:DegradedRetryMs) {
        # Give the render path another chance instead of staying silent for the session.
        $script:DegradedMode = $false
        $script:Perf.RenderErrors = 0
        $script:EnableDebugTrace = (-not $script:SafeMode) -and ($env:PWSH_SYNTAX_HIGHLIGHTING_DEBUG -eq '1')
        & $script:AddDebugTraceEvent 'degraded-mode-retry' $Key
        return $true
    }

    & $script:AddDebugTraceEvent 'degraded-mode-skip' $Key
    return $false
}

$script:GetScreenRuns = {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][ValidateRange(0, [int]::MaxValue)][int]$Offset,
        [Parameter(Mandatory = $true)][ValidateRange(0, [int]::MaxValue)][int]$Length,
        [Parameter(Mandatory = $true)][int]$StartX,
        [Parameter(Mandatory = $true)][int]$BufferWidth
    )

    $runs = New-Object System.Collections.Generic.List[object]
    if ($Length -le 0 -or $BufferWidth -le 0) { return @() }

    $x = $StartX
    $y = 0

    # Advance to the token's first character.
    $limit = [Math]::Min($Offset, $Text.Length)
    for ($i = 0; $i -lt $limit; $i++) {
        if ($Text[$i] -eq "`n") {
            $y++
            $x = 0
            continue
        }
        $x++
        if ($x -ge $BufferWidth) {
            $x = 0
            $y++
        }
    }

    # Then collect the characters, breaking a run whenever the row changes.
    $runX = $x
    $runY = $y
    $runLength = 0
    for ($i = $Offset; $i -lt ($Offset + $Length); $i++) {
        if ($i -ge $Text.Length) { break }

        if ($runLength -eq 0) {
            $runX = $x
            $runY = $y
        }
        $runLength++

        if ($Text[$i] -eq "`n") {
            $runs.Add([pscustomobject]@{ X = $runX; Y = $runY; Length = $runLength })
            $runLength = 0
            $x = 0
            $y++
            continue
        }

        $x++
        if ($x -ge $BufferWidth) {
            $runs.Add([pscustomobject]@{ X = $runX; Y = $runY; Length = $runLength })
            $runLength = 0
            $x = 0
            $y++
        }
    }

    if ($runLength -gt 0) {
        $runs.Add([pscustomobject]@{ X = $runX; Y = $runY; Length = $runLength })
    }

    return $runs.ToArray()
}

function Get-ScreenRunForToken {
    <#
    .SYNOPSIS
        Maps a buffer offset/length onto terminal cells, split into per-row runs.
    .DESCRIPTION
        Public entry point for the logic the renderer uses (see $script:GetScreenRuns).
        The buffer is a flat string but the terminal is a rectangle: character N is not
        simply X = origin + N once the line wraps or contains a newline.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][ValidateRange(0, 2147483647)][int]$Offset,
        [Parameter(Mandatory = $true)][ValidateRange(0, 2147483647)][int]$Length,
        [Parameter(Mandatory = $true)][int]$StartX,
        [Parameter(Mandatory = $true)][int]$BufferWidth
    )

    & $script:GetScreenRuns -Text $Text -Offset $Offset -Length $Length -StartX $StartX -BufferWidth $BufferWidth
}

$script:RenderAction = {
    param($KeyInfo)

    $normalizedKeyInfo = $null
    if ($KeyInfo -is [System.ConsoleKeyInfo]) {
        $normalizedKeyInfo = $KeyInfo
    }
    elseif ($null -ne $KeyInfo -and $KeyInfo.PSObject -and $KeyInfo.PSObject.Properties['HasValue']) {
        if ($KeyInfo.HasValue) {
            $normalizedKeyInfo = $KeyInfo.Value
        }
    }

    if ($script:EnableTelemetry) { $script:Perf.RenderCalls++ }
    $eventKey = if ($normalizedKeyInfo) { $normalizedKeyInfo.Key } else { [System.ConsoleKey]::NoName }

    try {
        if (-not (& $script:EnterRenderGate $eventKey)) { return }

        # High-latency keys respect the tunable throttle; interactive/navigation keys
        # bypass it so the prompt never feels sticky (upstream: "custom throttle setting").
        $minRenderIntervalMs = $script:ThrottleLimit
        if ($normalizedKeyInfo.Key -in @(
                [System.ConsoleKey]::UpArrow,
                [System.ConsoleKey]::DownArrow,
                [System.ConsoleKey]::LeftArrow,
                [System.ConsoleKey]::RightArrow,
                [System.ConsoleKey]::Home,
                [System.ConsoleKey]::End,
                [System.ConsoleKey]::Tab,
                [System.ConsoleKey]::Spacebar,
                [System.ConsoleKey]::Delete,
                [System.ConsoleKey]::Backspace
            )) {
            $minRenderIntervalMs = 0
        }

        # A paste (or undo, or history recall) arrives as one multi-character change; it must
        # not be swallowed by the throttle, or the pasted line stays uncoloured until the next
        # keystroke. Read the buffer text first (no parse) and bypass the throttle when the
        # length moved by more than a single character.
        $earlyBufferText = $null; $earlyCursor = $null
        try {
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$earlyBufferText, [ref]$earlyCursor)
        }
        catch {
            $earlyBufferText = $null
        }

        if ($null -ne $earlyBufferText -and $script:LastPaintedLength -ge 0) {
            $lengthDelta = [Math]::Abs($earlyBufferText.Length - $script:LastPaintedLength)
            if ($lengthDelta -gt 1) {
                $minRenderIntervalMs = 0
                & $script:AddDebugTraceEvent 'bulk-change-bypass' $eventKey $earlyBufferText
            }
        }

        $nowTick = [Environment]::TickCount64
        $elapsedMs = ($nowTick - $script:LastRenderTick)
        if ($elapsedMs -lt $minRenderIntervalMs) {
            & $script:AddDebugTraceEvent 'throttled' $eventKey
            if ($script:EnableTelemetry) { $script:Perf.Throttled++ }
            return
        }

        $perfStart = $null
        if ($script:EnableTelemetry) {
            $perfStart = [System.Diagnostics.Stopwatch]::StartNew()
        }

        $ast = $null; $tokens = $null; $errors = $null; $cursor = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$ast, [ref]$tokens, [ref]$errors, [ref]$cursor)
        if (-not $tokens -or $tokens.Count -eq 0 -or -not $tokens[0]) {
            & $script:AddDebugTraceEvent 'no-token' $eventKey
            if ($script:EnableTelemetry) {
                $script:Perf.NoToken++
                $perfStart.Stop()
                $script:Perf.TotalRenderMs += $perfStart.Elapsed.TotalMilliseconds
            }
            return
        }

        $bufferText = $null; $cursorIgnored = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$bufferText, [ref]$cursorIgnored)
        if ([string]::IsNullOrEmpty($bufferText)) {
            $script:VerifiedOriginX = -1
            $script:VerifiedOriginY = -1
            & $script:AddDebugTraceEvent 'empty-buffer' $eventKey
            if ($script:EnableTelemetry) {
                $script:Perf.NoToken++
                $perfStart.Stop()
                $script:Perf.TotalRenderMs += $perfStart.Elapsed.TotalMilliseconds
            }
            return
        }

        if (-not $host -or -not $host.UI -or -not $host.UI.RawUI) {
            & $script:AddDebugTraceEvent 'host-missing' $eventKey
            return
        }

        $bufferLength = if ($ast -and $ast.Extent) { $ast.Extent.EndOffset } else { -1 }
        if ($script:MaxBufferLength -gt 0 -and $bufferLength -gt $script:MaxBufferLength) {
            & $script:AddDebugTraceEvent 'max-buffer-length' $eventKey
            if ($script:EnableTelemetry) {
                $perfStart.Stop()
                $script:Perf.TotalRenderMs += $perfStart.Elapsed.TotalMilliseconds
            }
            return
        }

        # Tokens on continuation lines are skipped: PSReadLine may prefix those rows with a
        # continuation prompt, so a buffer offset no longer maps to a fixed screen column.
        $firstNewline = $bufferText.IndexOf("`n")
        $paintableLimit = if ($firstNewline -ge 0) { $firstNewline } else { [int]::MaxValue }

        # Every token gets a chance to colour itself; the stock highlighter only claims
        # command-name tokens. This is what makes `foo; bar` and `a | b` validate both sides.
        $targets = New-Object System.Collections.Generic.List[object]
        foreach ($candidate in $tokens) {
            $candidateText = [string]$candidate.Text
            if ([string]::IsNullOrWhiteSpace($candidateText)) { continue }

            $candidateStart = [int]$candidate.Extent.StartOffset
            $candidateLength = [int]($candidate.Extent.EndOffset - $candidateStart)
            if ($candidateLength -le 0) { continue }
            if ($candidateStart -ge $paintableLimit) {
                & $script:AddDebugTraceEvent 'continuation-line-skip' $eventKey $candidateText
                continue
            }

            $ctx = [pscustomobject]@{
                Token            = $candidate
                TokenText        = $candidateText
                TokenStartOffset = $candidateStart
                TokenLength      = $candidateLength
                BufferLength     = $bufferLength
                CursorX          = $bufferOriginX
                CursorY          = $bufferOriginY
                Ast              = $ast
                Tokens           = $tokens
                Errors           = $errors
            }

            $color = $null
            foreach ($highlighter in $script:Highlighters) {
                $useThis = $false
                try {
                    $useThis = [bool](& $highlighter.Predicate $ctx)
                }
                catch {
                    continue
                }

                if (-not $useThis) { continue }

                try {
                    $color = & $highlighter.Paint $ctx
                }
                catch {
                    $color = $null
                }

                if ($null -ne $color) {
                    break
                }
            }

            if ($null -eq $color) { continue }

            $targets.Add([pscustomobject]@{
                    Text        = $candidateText
                    StartOffset = $candidateStart
                    Length      = $candidateLength
                    Color       = $color
                })
        }

        if ($targets.Count -eq 0) {
            & $script:AddDebugTraceEvent 'no-color' $eventKey
            if ($script:EnableTelemetry) {
                $perfStart.Stop()
                $script:Perf.TotalRenderMs += $perfStart.Elapsed.TotalMilliseconds
            }
            return
        }

        $bufferWidth = $host.UI.RawUI.BufferSize.Width
        if ($bufferWidth -le 0) { return }

        # Where does buffer offset 0 sit on screen?
        #
        # Console cursor reads are not trustworthy enough to compute this once and believe it:
        # measured on one unchanged line, SetCursorPosition(0)+read reported 5, 11, 31, 49 and 44
        # on consecutive frames, and the arithmetic variant drifted the same way. So every
        # candidate is confirmed by reading the cells it implies and comparing them with the
        # token's own characters. Candidates are tried cheapest-first and lazily: a cached origin
        # that still verifies costs one buffer read and no cursor movement at all.
        $firstTarget = $targets[0]
        $lineHasNewline = $bufferText.IndexOf("`n") -ge 0

        $probeOrigin = {
            param($ProbeX, $ProbeY)

            if ($ProbeX -lt 0 -or $ProbeY -lt 0) { return $false }
            $probeRuns = & $script:GetScreenRuns -Text $bufferText -Offset $firstTarget.StartOffset -Length $firstTarget.Length -StartX $ProbeX -BufferWidth $bufferWidth
            if ($probeRuns.Count -eq 0 -or $probeRuns[0].Length -le 0) { return $false }

            $probeRun = $probeRuns[0]
            $probeRow = $ProbeY + $probeRun.Y
            $probeRec = New-Object System.Management.Automation.Host.Rectangle($probeRun.X, $probeRow, ($probeRun.X + $probeRun.Length - 1), $probeRow)
            try {
                $probeBuf = $host.UI.RawUI.GetBufferContents($probeRec)
            }
            catch {
                return $false
            }

            $probeCount = [Math]::Min($probeRun.Length, $probeBuf.GetLength(1))
            if ($probeCount -le 0) { return $false }

            for ($i = 0; $i -lt $probeCount; $i++) {
                $textIndex = $firstTarget.StartOffset + $i
                if ($textIndex -ge $bufferText.Length) { return $false }
                if ($probeBuf.GetValue(0, $i).Character -ne $bufferText[$textIndex]) { return $false }
            }

            return $true
        }
        # NB: deliberately not .GetNewClosure() - a closure gets its own session state, where
        # $script: no longer resolves to this module (that silently breaks $script:GetScreenRuns).

        $chosenOrigin = $null

        # 1) the origin that verified last frame (no cursor movement, one buffer read)
        if ($script:VerifiedOriginX -ge 0 -and (& $probeOrigin $script:VerifiedOriginX $script:VerifiedOriginY)) {
            $chosenOrigin = [pscustomobject]@{ X = $script:VerifiedOriginX; Y = $script:VerifiedOriginY; Via = 'verified-cache' }
        }

        # 2) arithmetic from the live cursor (no cursor movement)
        if (-not $chosenOrigin -and -not $lineHasNewline) {
            $cursorOffset = [int]$cursor
            $liveCursor = $host.UI.RawUI.CursorPosition
            $arithmeticX = ((($liveCursor.X - $cursorOffset) % $bufferWidth) + $bufferWidth) % $bufferWidth
            $rowsDown = [int][Math]::Floor((($arithmeticX + $cursorOffset) / $bufferWidth))
            $arithmeticY = [Math]::Max(0, $liveCursor.Y - $rowsDown)
            if (& $probeOrigin $arithmeticX $arithmeticY) {
                $chosenOrigin = [pscustomobject]@{ X = $arithmeticX; Y = $arithmeticY; Via = 'cursor-arithmetic' }
            }
        }

        # 3) ask PSReadLine to seek to buffer offset 0 (two cursor movements: last resort)
        if (-not $chosenOrigin) {
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition(0)
            $seekX = $host.UI.RawUI.CursorPosition.X
            $seekY = $host.UI.RawUI.CursorPosition.Y
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor)
            if (& $probeOrigin $seekX $seekY) {
                $chosenOrigin = [pscustomobject]@{ X = $seekX; Y = $seekY; Via = 'cursor-seek' }
            }
        }

        if ($null -eq $chosenOrigin) {
            # Nothing verifies: leave the line uncoloured for a frame rather than paint the wrong
            # characters or the prompt.
            $script:Perf.PaintVerifyFails++
            & $script:AddDebugTraceEvent 'origin-unverified' $eventKey $firstTarget.Text
            if ($script:EnableTelemetry) {
                $perfStart.Stop()
                $script:Perf.TotalRenderMs += $perfStart.Elapsed.TotalMilliseconds
                & $script:PublishMetrics
            }
            return
        }

        $bufferOriginX = $chosenOrigin.X
        $bufferOriginY = $chosenOrigin.Y
        $originMethod = $chosenOrigin.Via
        $script:VerifiedOriginX = $chosenOrigin.X
        $script:VerifiedOriginY = $chosenOrigin.Y

        $signatureParts = foreach ($target in $targets) {
            "$($target.Text)|$($target.StartOffset)|$($target.Length)|$($target.Color)"
        }
        $signature = (@($signatureParts) -join ';') + "|$bufferOriginX|$bufferOriginY|$bufferLength|$($bufferText.GetHashCode())"

        $forceRepaint = $false
        if ($normalizedKeyInfo.Key -in @(
                [System.ConsoleKey]::Spacebar,
                [System.ConsoleKey]::UpArrow,
                [System.ConsoleKey]::DownArrow,
                [System.ConsoleKey]::LeftArrow,
                [System.ConsoleKey]::RightArrow,
                [System.ConsoleKey]::Home,
                [System.ConsoleKey]::End,
                [System.ConsoleKey]::Tab
            )) {
            $forceRepaint = $true
        }

        if (-not $forceRepaint -and $signature -eq $script:LastRenderSignature) {
            & $script:AddDebugTraceEvent 'skipped-unchanged' $eventKey
            if ($script:EnableTelemetry) {
                $script:Perf.SkippedUnchanged++
                $perfStart.Stop()
                $script:Perf.TotalRenderMs += $perfStart.Elapsed.TotalMilliseconds
            }
            return
        }

        # Geometry probe: with debug tracing on, record what the renderer thinks the layout is,
        # so a mis-paint can be traced to the origin/width reading instead of guessed at.
        if ($script:EnableDebugTrace -and $targets.Count -gt 0) {
            $probe = $targets[0]
            $probeRuns = & $script:GetScreenRuns -Text $bufferText -Offset $probe.StartOffset -Length $probe.Length -StartX $bufferOriginX -BufferWidth $bufferWidth
            $probeRun = if ($probeRuns.Count -gt 0) { $probeRuns[0] } else { [pscustomobject]@{ X = -1; Y = -1; Length = 0 } }
            $geometry = 'origin={0},{1} via={2} width={3} bufLen={4} cursorOffset={5} target={6}@{7}+{8} run={9},{10}+{11}' -f `
                $bufferOriginX, $bufferOriginY, $originMethod, $bufferWidth, `
                $bufferText.Length, [int]$cursor, $probe.Text, $probe.StartOffset, $probe.Length, `
                $probeRun.X, $probeRun.Y, $probeRun.Length
            & $script:AddDebugTraceEvent 'frame-geometry' $eventKey $bufferText $geometry
        }

        $paintedFrames = 0
        foreach ($target in $targets) {
            $runs = & $script:GetScreenRuns -Text $bufferText -Offset $target.StartOffset -Length $target.Length -StartX $bufferOriginX -BufferWidth $bufferWidth

            $runOffset = 0
            foreach ($run in $runs) {
                $rowY = $bufferOriginY + $run.Y
                $finalRec = New-Object System.Management.Automation.Host.Rectangle($run.X, $rowY, ($run.X + $run.Length - 1), $rowY)
                $finalBuf = $host.UI.RawUI.GetBufferContents($finalRec)

                # Verify before colouring: the cells we are about to change must actually hold the
                # token's characters. Console cursor reads are not reliable enough to trust a
                # computed origin (measured drift: the same line reported 5, 11, 31, 49), and a
                # mis-paint is not repaired by PSReadLine's diff renderer. A mismatch means the
                # geometry is wrong this frame, so skip it rather than corrupt the line.
                $cellCount = [Math]::Min($run.Length, $finalBuf.GetLength(1))
                $verified = $true
                for ($xPosition = 0; $xPosition -lt $cellCount; $xPosition++) {
                    $textIndex = $target.StartOffset + $runOffset + $xPosition
                    if ($textIndex -ge $bufferText.Length) { $verified = $false; break }
                    if ($finalBuf.GetValue(0, $xPosition).Character -ne $bufferText[$textIndex]) {
                        $verified = $false
                        break
                    }
                }

                if (-not $verified) {
                    $script:Perf.PaintVerifyFails++
                    & $script:AddDebugTraceEvent 'paint-verify-fail' $eventKey $target.Text ("origin={0},{1} run={2},{3}+{4}" -f $bufferOriginX, $bufferOriginY, $run.X, $rowY, $run.Length)
                    $runOffset += $run.Length
                    continue
                }

                $needsWrite = $false
                for ($xPosition = 0; $xPosition -lt $cellCount; $xPosition++) {
                    $bufferItem = $finalBuf.GetValue(0, $xPosition)
                    if ($bufferItem.ForegroundColor -ne $target.Color) {
                        $bufferItem.ForegroundColor = $target.Color
                        $finalBuf.SetValue($bufferItem, 0, $xPosition)
                        $needsWrite = $true
                        if ($script:EnableTelemetry) { $script:Perf.PaintChars++ }
                    }
                }

                if ($needsWrite) {
                    $coords = New-Object System.Management.Automation.Host.Coordinates $run.X, $rowY
                    $host.UI.RawUI.SetBufferContents($coords, $finalBuf)
                    $paintedFrames++
                    if ($script:EnableTelemetry) { $script:Perf.PaintOps++ }
                }
                elseif ($script:EnableTelemetry) {
                    $script:Perf.NoColorWrite++
                }

                $runOffset += $run.Length
            }
        }

        $script:LastRenderSignature = $signature
        $script:LastRenderTick = $nowTick
        $script:LastPaintedLength = $bufferText.Length
        $global:lastRender = Get-Date
        & $script:AddDebugTraceEvent 'painted' $eventKey ([string]$targets[0].Text)

        if ($script:EnableTelemetry) {
            $perfStart.Stop()
            $script:Perf.TotalRenderMs += $perfStart.Elapsed.TotalMilliseconds
            & $script:PublishMetrics
        }
    }
    catch {
        # Keep the message: a silent degradation is undiagnosable for users.
        $script:LastRenderError = $_.Exception.Message
        & $script:AddDebugTraceEvent 'exception' $eventKey $script:LastRenderError $_.Exception.Message
        $script:Perf.RenderErrors++
        if ($script:Perf.RenderErrors -ge $script:RenderErrorBudget) {
            $script:DegradedMode = $true
            $script:DegradedSince = [Environment]::TickCount64
            $script:EnableDebugTrace = $false
            $script:Perf.ErrorBudgetTrips++
            & $script:AddDebugTraceEvent 'error-budget-tripped' $eventKey $script:LastRenderError $script:LastRenderError
        }
        & $script:PublishMetrics
        return
    }
}.GetNewClosure()

function Set-SyntaxHighlightingThrottle {
    <#
    .SYNOPSIS
        Gets or sets the render throttle for pwsh-syntax-highlighting.
    .DESCRIPTION
        Controls the minimum interval (in milliseconds) between command-validation
        repaints. Raise it if validation feels laggy on a slow terminal or over SSH;
        lower it for snappier feedback. Keys that must feel instant (arrows, Home/End,
        Tab, Space, Backspace/Delete) always bypass the throttle.
    .PARAMETER Milliseconds
        Throttle in milliseconds. 0 disables throttling (not recommended).
    .PARAMETER Get
        Return the current throttle value instead of changing it.
    .PARAMETER Reset
        Restore the default throttle (50ms).
    .EXAMPLE
        syntax-highlighting 100
    .EXAMPLE
        syntax-highlighting -Get
    #>
    [CmdletBinding(DefaultParameterSetName = 'Set', SupportsShouldProcess = $true)]
    param(
        [Parameter(ParameterSetName = 'Set', Mandatory = $true, Position = 0)]
        [ValidateRange(0, 5000)]
        [int]$Milliseconds,

        [Parameter(ParameterSetName = 'Get', Mandatory = $true)]
        [switch]$Get,

        [Parameter(ParameterSetName = 'Reset', Mandatory = $true)]
        [switch]$Reset
    )

    if ($Get) { return $script:ThrottleLimit }

    $targetThrottle = if ($Reset) { 50 } else { $Milliseconds }
    if (-not $PSCmdlet.ShouldProcess('pwsh-syntax-highlighting render throttle', "Set to ${targetThrottle}ms")) {
        return
    }

    $script:ThrottleLimit = $targetThrottle
    Write-Verbose "Syntax-highlighting throttle set to $($script:ThrottleLimit)ms."

    [pscustomobject]@{
        Module       = 'pwsh-syntax-highlighting'
        ThrottleMs   = $script:ThrottleLimit
        TakesEffect  = 'Immediately (no re-import needed)'
    }
}

Set-Alias -Name syntax-highlighting -Value Set-SyntaxHighlightingThrottle

$printableChars = [char[]](0x20..0x7e + 0xa0..0xff)
$functionKeyMap = @(
    @{ Key = 'UpArrow'; Function = 'PreviousHistory' }
    @{ Key = 'DownArrow'; Function = 'NextHistory' }
    @{ Key = 'RightArrow'; Function = 'ForwardChar' }
    @{ Key = 'LeftArrow'; Function = 'BackwardChar' }
    @{ Key = 'Home'; Function = 'BeginningOfLine' }
    @{ Key = 'End'; Function = 'EndOfLine' }
    @{ Key = 'Ctrl+RightArrow'; Function = 'NextWord' }
    @{ Key = 'Ctrl+LeftArrow'; Function = 'BackwardWord' }
    @{ Key = 'Alt+f'; Function = 'NextWord' }
    @{ Key = 'Alt+b'; Function = 'BackwardWord' }
    @{ Key = 'Ctrl+a'; Function = 'BeginningOfLine' }
    @{ Key = 'Ctrl+e'; Function = 'EndOfLine' }
    @{ Key = 'Ctrl+v'; Function = 'Paste' }
    @{ Key = 'Ctrl+Shift+v'; Function = 'Paste' }
    @{ Key = 'Shift+Insert'; Function = 'Paste' }
    @{ Key = 'Shift+Tab'; Function = 'TabCompletePrevious' }
    @{ Key = 'Backspace'; Function = 'BackwardDeleteChar' }
    @{ Key = 'Delete'; Function = 'DeleteChar' }
)

if ($script:SafeMode) {
    $functionKeyMap = @(
        @{ Key = 'UpArrow'; Function = 'PreviousHistory' }
        @{ Key = 'DownArrow'; Function = 'NextHistory' }
        @{ Key = 'RightArrow'; Function = 'ForwardChar' }
        @{ Key = 'LeftArrow'; Function = 'BackwardChar' }
        @{ Key = 'Ctrl+v'; Function = 'Paste' }
        @{ Key = 'Ctrl+Shift+v'; Function = 'Paste' }
        @{ Key = 'Shift+Insert'; Function = 'Paste' }
        @{ Key = 'Backspace'; Function = 'BackwardDeleteChar' }
        @{ Key = 'Delete'; Function = 'DeleteChar' }
    )
}
$script:RegisteredFunctionKeys = @{}

Invoke-SyntaxHighlightingPreflight
& $script:PublishMetrics

$ExecutionContext.SessionState.Module.OnRemove = {
    foreach ($key in $printableChars) {
        Set-PSReadLineKeyHandler -Key $key -Function SelfInsert -ErrorAction SilentlyContinue
    }

    Set-PSReadLineKeyHandler -Key Tab -Function Complete -ErrorAction SilentlyContinue
    foreach ($entry in $script:RegisteredFunctionKeys.GetEnumerator()) {
        Set-PSReadLineKeyHandler -Key $entry.Key -Function $entry.Value -ErrorAction SilentlyContinue
    }

    & $script:PublishMetrics
}

$renderAction = $script:RenderAction
if (-not $script:Preflight.Passed) {
    return
}

$printableChars + "Tab" | ForEach-Object {
    Set-PSReadLineKeyHandler -Key $_ `
        -BriefDescription ValidatePrograms `
        -LongDescription "Validate typed program's existence in path variable" `
        -ScriptBlock {
        param($key, $arg)

        if ($key.Key -ne [System.ConsoleKey]::Tab) {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($key.KeyChar)
        }
        else {
            [Microsoft.PowerShell.PSConsoleReadLine]::TabCompleteNext($key)
        }

        & $renderAction $key
    }.GetNewClosure()
}

foreach ($entry in $functionKeyMap) {
    $methodName = [string]$entry.Function
    $keyName = [string]$entry.Key

    try {
        Set-PSReadLineKeyHandler -Key $keyName `
            -BriefDescription ValidatePrograms `
            -LongDescription "Validate typed program's existence in path variable" `
            -ScriptBlock {
            param($key, $arg)
            switch ($methodName) {
                'PreviousHistory' { [Microsoft.PowerShell.PSConsoleReadLine]::PreviousHistory($key, $arg) }
                'NextHistory' { [Microsoft.PowerShell.PSConsoleReadLine]::NextHistory($key, $arg) }
                'ForwardChar' { [Microsoft.PowerShell.PSConsoleReadLine]::ForwardChar($key, $arg) }
                'BackwardChar' { [Microsoft.PowerShell.PSConsoleReadLine]::BackwardChar($key, $arg) }
                'BeginningOfLine' { [Microsoft.PowerShell.PSConsoleReadLine]::BeginningOfLine($key, $arg) }
                'EndOfLine' { [Microsoft.PowerShell.PSConsoleReadLine]::EndOfLine($key, $arg) }
                'Paste' { [Microsoft.PowerShell.PSConsoleReadLine]::Paste($key, $arg) }
                'NextWord' { [Microsoft.PowerShell.PSConsoleReadLine]::NextWord($key, $arg) }
                'BackwardWord' { [Microsoft.PowerShell.PSConsoleReadLine]::BackwardWord($key, $arg) }
                'TabCompletePrevious' { [Microsoft.PowerShell.PSConsoleReadLine]::TabCompletePrevious($key, $arg) }
                'BackwardDeleteChar' { [Microsoft.PowerShell.PSConsoleReadLine]::BackwardDeleteChar($key, $arg) }
                'DeleteChar' { [Microsoft.PowerShell.PSConsoleReadLine]::DeleteChar($key, $arg) }
                default { return }
            }
            & $renderAction $key
        }.GetNewClosure()
        $script:RegisteredFunctionKeys[$keyName] = $methodName
    }
    catch {
        if ($script:EnableTelemetry) { $script:Perf.RegistrationSkipped++ }
    }
}