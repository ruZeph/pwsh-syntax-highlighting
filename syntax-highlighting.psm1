$global:lastRender = Get-Date
$script:LastRenderTick = [Environment]::TickCount64

$script:CommandLookupCache = @{}
$script:CommandLookupOrder = [System.Collections.Generic.Queue[string]]::new()
$script:CommandCacheMaxSize = 512
$script:CommandCacheTtlMs = 5000
$script:MaxBufferLength = if ($env:PWSH_SYNTAX_HIGHLIGHTING_MAX_LENGTH) { [int]$env:PWSH_SYNTAX_HIGHLIGHTING_MAX_LENGTH } else { 0 }
$script:MaxCommandLookupLength = if ($env:PWSH_SYNTAX_HIGHLIGHTING_MAX_COMMAND_LENGTH) { [int]$env:PWSH_SYNTAX_HIGHLIGHTING_MAX_COMMAND_LENGTH } else { 256 }

$script:Styles = @{
    ValidCommand = [System.ConsoleColor]::Green
    InvalidCommand = [System.ConsoleColor]::Red
}

$script:Highlighters = @(
    @{
        Name = 'main-command'
        Predicate = {
            param($ctx)
            -not [string]::IsNullOrWhiteSpace($ctx.TokenText) -and
            -not $ctx.TokenText.Contains('[') -and
            -not $ctx.TokenText.Contains(']')
        }
        Paint = {
            param($ctx)

            if ($script:MaxCommandLookupLength -gt 0 -and $ctx.TokenText.Length -gt $script:MaxCommandLookupLength) {
                return $script:Styles.InvalidCommand
            }

            $nowTicks = [Environment]::TickCount64
            $cacheEntry = $script:CommandLookupCache[$ctx.TokenText]
            if ($cacheEntry -and (($nowTicks - [int64]$cacheEntry.Tick) -lt $script:CommandCacheTtlMs)) {
                if ($script:EnableTelemetry) { $script:Perf.CacheHit++ }
                return (if ([bool]$cacheEntry.Exists) { $script:Styles.ValidCommand } else { $script:Styles.InvalidCommand })
            }

            if ($cacheEntry) {
                $script:CommandLookupCache.Remove($ctx.TokenText) | Out-Null
            }

            if ($script:EnableTelemetry) { $script:Perf.CacheMiss++ }
            $exists = [bool](Get-Command -Name $ctx.TokenText -ErrorAction Ignore)
            $script:CommandLookupCache[$ctx.TokenText] = @{
                Exists = $exists
                Tick = $nowTicks
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
$script:EnableTelemetry = ($env:PWSH_SYNTAX_HIGHLIGHTING_METRICS -eq '1')
$script:Perf = [ordered]@{
    RenderCalls = 0
    Throttled = 0
    NoToken = 0
    SkippedUnchanged = 0
    RenderErrors = 0
    RegistrationSkipped = 0
    CacheHit = 0
    CacheMiss = 0
    PaintOps = 0
    PaintChars = 0
    NoColorWrite = 0
    TotalRenderMs = 0.0
}

$script:RenderAction = {
    param([System.ConsoleKeyInfo]$KeyInfo)

    if ($script:EnableTelemetry) { $script:Perf.RenderCalls++ }

    try {

    $minRenderIntervalMs = 30
    if ($KeyInfo -and $KeyInfo.Key -in @(
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
        if ($script:EnableTelemetry) {
            $script:Perf.NoToken++
            $perfStart.Stop()
            $script:Perf.TotalRenderMs += $perfStart.Elapsed.TotalMilliseconds
        }
        return
    }

    $token = $tokens[0]
    $tokenText = [string]$token.Text
    if ([string]::IsNullOrWhiteSpace($tokenText)) {
        if ($script:EnableTelemetry) {
            $perfStart.Stop()
            $script:Perf.TotalRenderMs += $perfStart.Elapsed.TotalMilliseconds
        }
        return
    }

    if (-not $host -or -not $host.UI -or -not $host.UI.RawUI) {
        return
    }

    [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition(0)
    $cursorPosX = $host.UI.RawUI.CursorPosition.X
    $cursorPosY = $host.UI.RawUI.CursorPosition.Y
    [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor)

    $tokenStartOffset = ($token.Extent.StartOffset)
    $tokenLength = ($token.Extent.EndOffset - $tokenStartOffset)
    if ($tokenLength -le 0) {
        if ($script:EnableTelemetry) {
            $perfStart.Stop()
            $script:Perf.TotalRenderMs += $perfStart.Elapsed.TotalMilliseconds
        }
        return
    }

    $bufferLength = if ($ast -and $ast.Extent) { $ast.Extent.EndOffset } else { -1 }
    if ($script:MaxBufferLength -gt 0 -and $bufferLength -gt $script:MaxBufferLength) {
        if ($script:EnableTelemetry) {
            $perfStart.Stop()
            $script:Perf.TotalRenderMs += $perfStart.Elapsed.TotalMilliseconds
        }
        return
    }

    $ctx = [pscustomobject]@{
        Token = $token
        TokenText = $tokenText
        TokenStartOffset = $tokenStartOffset
        TokenLength = $tokenLength
        BufferLength = $bufferLength
        CursorX = $cursorPosX
        CursorY = $cursorPosY
        Ast = $ast
        Tokens = $tokens
        Errors = $errors
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

    if ($null -eq $color) {
        if ($script:EnableTelemetry) {
            $perfStart.Stop()
            $script:Perf.TotalRenderMs += $perfStart.Elapsed.TotalMilliseconds
        }
        return
    }

    $bufferHash = if ($ast -and $ast.Extent -and $ast.Extent.Text) { $ast.Extent.Text.GetHashCode() } else { 0 }
    $signature = "$tokenText|$tokenStartOffset|$tokenLength|$cursorPosX|$cursorPosY|$bufferLength|$bufferHash|$color"
    $forceRepaint = $false
    if ($KeyInfo -and $KeyInfo.Key -in @(
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
        if ($script:EnableTelemetry) {
            $script:Perf.SkippedUnchanged++
            $perfStart.Stop()
            $script:Perf.TotalRenderMs += $perfStart.Elapsed.TotalMilliseconds
        }
        return
    }

    $sX = ($cursorPosX + $tokenStartOffset)
    $Y = $cursorPosY
    $eX = ($sX + $tokenLength)
    $nextLine = $false

    $painted = 0
    $bufSize = $host.UI.RawUI.BufferSize.Width
    while ($painted -ne $tokenLength) {
        $scanXEnd = $eX
        if ($eX -gt $bufSize) {
            $scanXEnd = $bufSize
            $eX = $eX - $bufSize
            $nextLine = $true
        }

        $finalRec = New-Object System.Management.Automation.Host.Rectangle($sX, $Y, ($scanXEnd - 1), $Y)
        $finalBuf = $host.UI.RawUI.GetBufferContents($finalRec)
        $needsWrite = $false
        for ($xPosition = 0; $xPosition -lt ($scanXEnd - $sX); $xPosition++) {
            $bufferItem = $finalBuf.GetValue(0, $xPosition)
            if ($bufferItem.ForegroundColor -ne $color) {
                $bufferItem.ForegroundColor = $color
                $finalBuf.SetValue($bufferItem, 0, $xPosition)
                $needsWrite = $true
                if ($script:EnableTelemetry) { $script:Perf.PaintChars++ }
            }
            $painted++
        }

        if ($needsWrite) {
            $coords = New-Object System.Management.Automation.Host.Coordinates $sX, $Y
            $host.UI.RawUI.SetBufferContents($coords, $finalBuf)
            if ($script:EnableTelemetry) { $script:Perf.PaintOps++ }
        }
        elseif ($script:EnableTelemetry) {
            $script:Perf.NoColorWrite++
        }

        if ($nextLine) {
            $sX = 0
            $Y++
            $nextLine = $false
        }
    }

    $script:LastRenderSignature = $signature
    $script:LastRenderTick = $nowTick
    $global:lastRender = Get-Date

    if ($script:EnableTelemetry) {
        $perfStart.Stop()
        $script:Perf.TotalRenderMs += $perfStart.Elapsed.TotalMilliseconds
        $global:SyntaxHighlightingMetrics = [pscustomobject]$script:Perf
    }
    }
    catch {
        if ($script:EnableTelemetry) {
            $script:Perf.RenderErrors++
            $global:SyntaxHighlightingMetrics = [pscustomobject]$script:Perf
        }
        return
    }
}.GetNewClosure()

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
    @{ Key = 'Shift+Tab'; Function = 'TabCompletePrevious' }
    @{ Key = 'Backspace'; Function = 'BackwardDeleteChar' }
    @{ Key = 'Delete'; Function = 'DeleteChar' }
)
$script:RegisteredFunctionKeys = @{}

$ExecutionContext.SessionState.Module.OnRemove = {
    foreach ($key in $printableChars) {
        Set-PSReadLineKeyHandler -Key $key -Function SelfInsert -ErrorAction SilentlyContinue
    }

    Set-PSReadLineKeyHandler -Key Tab -Function Complete -ErrorAction SilentlyContinue
    foreach ($entry in $script:RegisteredFunctionKeys.GetEnumerator()) {
        Set-PSReadLineKeyHandler -Key $entry.Key -Function $entry.Value -ErrorAction SilentlyContinue
    }

    if ($script:EnableTelemetry) {
        $global:SyntaxHighlightingMetrics = [pscustomobject]$script:Perf
    }
}

$renderAction = $script:RenderAction
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
    $method = [Microsoft.PowerShell.PSConsoleReadLine].GetMethod($methodName, [type[]]@([System.ConsoleKeyInfo], [object]))
    if (-not $method) {
        if ($script:EnableTelemetry) { $script:Perf.RegistrationSkipped++ }
        continue
    }

    try {
        Set-PSReadLineKeyHandler -Key $keyName `
            -BriefDescription ValidatePrograms `
            -LongDescription "Validate typed program's existence in path variable" `
            -ScriptBlock {
                param($key, $arg)
                $method.Invoke($null, @($key, $arg)) | Out-Null
                & $renderAction $key
            }.GetNewClosure()
        $script:RegisteredFunctionKeys[$keyName] = $methodName
    }
    catch {
        if ($script:EnableTelemetry) { $script:Perf.RegistrationSkipped++ }
    }
}