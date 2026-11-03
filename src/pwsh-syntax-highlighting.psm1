$global:lastRender = Get-Date
$script:LastRenderTick = [Environment]::TickCount64

$script:CommandLookupCache = @{}
$script:CommandLookupOrder = [System.Collections.Generic.Queue[string]]::new()
$script:CommandCacheMaxSize = 512
$script:CommandCacheTtlMs = 5000
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

            $nowTicks = [Environment]::TickCount64
            $cacheEntry = $script:CommandLookupCache[$ctx.TokenText]
            if ($cacheEntry -and (($nowTicks - [int64]$cacheEntry.Tick) -lt $script:CommandCacheTtlMs)) {
                if ($script:EnableTelemetry) { $script:Perf.CacheHit++ }
                if ([bool]$cacheEntry.Exists) {
                    return $script:Styles.ValidCommand
                }
                return $script:Styles.InvalidCommand
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

            if ($exists) { return $script:Styles.ValidCommand }
            return $script:Styles.InvalidCommand
        }
    }
)

$script:LastRenderSignature = ''
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
    PaintOps            = 0
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

        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition(0)
        $bufferOriginX = $host.UI.RawUI.CursorPosition.X
        $bufferOriginY = $host.UI.RawUI.CursorPosition.Y
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor)

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

        $bufferWidth = $host.UI.RawUI.BufferSize.Width
        foreach ($target in $targets) {
            $runs = & $script:GetScreenRuns -Text $bufferText -Offset $target.StartOffset -Length $target.Length -StartX $bufferOriginX -BufferWidth $bufferWidth

            foreach ($run in $runs) {
                $rowY = $bufferOriginY + $run.Y
                $finalRec = New-Object System.Management.Automation.Host.Rectangle($run.X, $rowY, ($run.X + $run.Length - 1), $rowY)
                $finalBuf = $host.UI.RawUI.GetBufferContents($finalRec)

                $needsWrite = $false
                $cellCount = [Math]::Min($run.Length, $finalBuf.GetLength(1))
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
                    if ($script:EnableTelemetry) { $script:Perf.PaintOps++ }
                }
                elseif ($script:EnableTelemetry) {
                    $script:Perf.NoColorWrite++
                }
            }
        }

        $script:LastRenderSignature = $signature
        $script:LastRenderTick = $nowTick
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