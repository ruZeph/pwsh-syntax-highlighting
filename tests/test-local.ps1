param(
    [ValidateRange(1, 10000)]
    [int]$Cycles = 100
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module PSReadLine -ErrorAction Stop

$moduleName = 'pwsh-syntax-highlighting'
$repoRoot = Split-Path -Parent $PSScriptRoot
$moduleManifest = Join-Path $repoRoot 'pwsh-syntax-highlighting.psd1'
$env:PWSH_SYNTAX_HIGHLIGHTING_DEBUG = '1'
$keys = @('UpArrow', 'DownArrow', 'RightArrow', 'LeftArrow', 'Backspace', 'Delete')
$expectedDefault = @{
    UpArrow    = 'PreviousHistory'
    DownArrow  = 'NextHistory'
    RightArrow = 'ForwardChar'
    LeftArrow  = 'BackwardChar'
    Backspace  = 'BackwardDeleteChar'
    Delete     = 'DeleteChar'
}

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Actual,

        [Parameter(Mandatory = $true)]
        [string]$Expected
    )

    if ($Actual -ne $Expected) {
        throw "$Name failed. expected='$Expected' actual='$Actual'"
    }
}

function Assert-True {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [bool]$Condition
    )

    if (-not $Condition) {
        throw "$Name failed. expected condition to be true."
    }
}

function Get-KeyFunction {
    param([Parameter(Mandatory = $true)][string]$Key)
    $handler = Get-PSReadLineKeyHandler -Key $Key
    if (-not $handler) {
        throw "No key handler found for '$Key'"
    }
    return [string]$handler.Function
}

if (-not (Test-Path $moduleManifest)) {
    throw "Could not find module manifest at $moduleManifest"
}

Write-Host "[1/13] Running lifecycle stress test ($Cycles cycles)..."
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$cycleFailures = @()
for ($i = 1; $i -le $Cycles; $i++) {
    try {
        Remove-Module $moduleName -ErrorAction SilentlyContinue
        Import-Module $moduleManifest -Force -ErrorAction Stop
        Remove-Module $moduleName -ErrorAction Stop
    }
    catch {
        $cycleFailures += "cycle ${i}: $($_.Exception.Message)"
    }
}
$sw.Stop()

if ($cycleFailures.Count -gt 0) {
    $cycleFailures | Select-Object -First 10 | ForEach-Object { Write-Host "  $_" }
    throw "Lifecycle stress test failed in $($cycleFailures.Count) cycle(s)."
}

Write-Host "  PASS: $Cycles cycles in $([math]::Round($sw.Elapsed.TotalMilliseconds, 2)) ms"

Write-Host "[2/13] Validating custom key bindings after import..."
Import-Module $moduleManifest -Force -ErrorAction Stop
foreach ($k in $keys) {
    Assert-Equal -Name "Custom key binding ($k)" -Actual (Get-KeyFunction -Key $k) -Expected 'ValidatePrograms'
}
Assert-Equal -Name 'Custom key binding (Tab)' -Actual (Get-KeyFunction -Key 'Tab') -Expected 'ValidatePrograms'
Write-Host "  PASS: custom key bindings are active"

$handlers = Get-PSReadLineKeyHandler
$boundKeys = @($handlers.Key)
foreach ($pasteKey in @('Ctrl+v', 'Shift+Insert')) {
    Assert-True -Name "Paste key binding ($pasteKey)" -Condition ($boundKeys -contains $pasteKey)
}
Write-Host "  PASS: custom key bindings are active"

Write-Host "[3/13] Validating render action smoke test..."
$module = Get-Module $moduleName -ErrorAction Stop
$renderResult = & $module { & $script:RenderAction; 'render-ok' }
Assert-Equal -Name 'RenderAction invocation' -Actual $renderResult -Expected 'render-ok'
Write-Host "  PASS: render action executes"

Write-Host "[4/13] Validating immediate-key throttle bypass edge case..."
$throttleCheck = & $module {
    $script:EnableTelemetry = $true
    $script:Perf.Throttled = 0

    $script:LastRenderTick = [Environment]::TickCount64
    $spaceKey = [System.ConsoleKeyInfo]::new(' ', [System.ConsoleKey]::Spacebar, $false, $false, $false)
    & $script:RenderAction $spaceKey
    [int]$script:Perf.Throttled
}
Assert-Equal -Name 'Space key should bypass throttle at 0ms elapsed' -Actual ([string]$throttleCheck) -Expected '0'
Write-Host "  PASS: immediate-key throttle bypass works"

Write-Host "[5/13] Validating debug trace and cache behavior under simulated key flow..."
$debugCheck = & $module {
    $script:EnableTelemetry = $true
    $script:EnableDebugTrace = $true
    $script:DebugTrace.Clear()
    $script:Perf.CacheHit = 0
    $script:Perf.CacheMiss = 0
    $script:CommandLookupCache.Clear()

    $spaceKey = [System.ConsoleKeyInfo]::new(' ', [System.ConsoleKey]::Spacebar, $false, $false, $false)
    $upKey = [System.ConsoleKeyInfo]::new([char]0, [System.ConsoleKey]::UpArrow, $false, $false, $false)
    $leftKey = [System.ConsoleKeyInfo]::new([char]0, [System.ConsoleKey]::LeftArrow, $false, $false, $false)
    $backspaceKey = [System.ConsoleKeyInfo]::new([char]8, [System.ConsoleKey]::Backspace, $false, $false, $false)

    foreach ($k in @($spaceKey, $upKey, $leftKey, $backspaceKey, $spaceKey)) {
        $script:LastRenderTick = [Environment]::TickCount64
        & $script:RenderAction $k
    }

    [pscustomobject]@{
        TraceCount      = [int]$script:DebugTrace.Count
        ExceptionEvents = @($script:DebugTrace | Where-Object Reason -eq 'exception').Count
        SpaceThrottled  = @($script:DebugTrace | Where-Object { $_.Key -eq 'Spacebar' -and $_.Reason -eq 'throttled' }).Count
    }
}
Assert-True -Name 'Debug simulation should produce trace events' -Condition ($debugCheck.TraceCount -ge 1)
Assert-Equal -Name 'Space in simulated flow should not throttle' -Actual ([string]$debugCheck.SpaceThrottled) -Expected '0'
Write-Host "  PASS: debug trace behavior validated"

Write-Host "[6/13] Validating command cache miss/hit behavior directly..."
$cacheCheck = & $module {
    $script:EnableTelemetry = $true
    $script:Perf.CacheHit = 0
    $script:Perf.CacheMiss = 0
    $script:CommandLookupCache.Clear()
    while ($script:CommandLookupOrder.Count -gt 0) { [void]$script:CommandLookupOrder.Dequeue() }

    $ctx = [pscustomobject]@{ TokenText = 'Get-ChildItem' }
    $paint = $script:Highlighters[0].Paint
    & $paint $ctx | Out-Null
    & $paint $ctx | Out-Null

    [pscustomobject]@{
        CacheHit  = [int]$script:Perf.CacheHit
        CacheMiss = [int]$script:Perf.CacheMiss
    }
}
Assert-True -Name 'Direct cache check should produce hit(s)' -Condition ($cacheCheck.CacheHit -ge 1)
Assert-True -Name 'Direct cache check should produce miss(es)' -Condition ($cacheCheck.CacheMiss -ge 1)
Write-Host "  PASS: debug trace and cache behavior validated"

Write-Host "[7/13] Validating failure injection resilience..."
$injectionCheck = & $module {
    $original = $script:AddDebugTraceEvent
    $script:AddDebugTraceEvent = { throw 'debug-trace-failure' }
    try {
        $k = [System.ConsoleKeyInfo]::new(' ', [System.ConsoleKey]::Spacebar, $false, $false, $false)
        & $script:RenderAction $k
        'ok'
    }
    catch {
        'failed'
    }
    finally {
        $script:AddDebugTraceEvent = $original
    }
}
Assert-Equal -Name 'Render path should survive injected debug failure' -Actual $injectionCheck -Expected 'ok'
Write-Host "  PASS: failure injection resilience validated"

Write-Host "[8/13] Validating safe-mode reduced keymap..."
Remove-Module $moduleName -ErrorAction SilentlyContinue
$env:PWSH_SYNTAX_HIGHLIGHTING_SAFE_MODE = '1'
Import-Module $moduleManifest -Force -ErrorAction Stop
$altF = Get-KeyFunction -Key 'Alt+f'
Assert-True -Name 'Safe mode should not register extended compatibility key handlers' -Condition ($altF -ne 'ValidatePrograms')
Remove-Module $moduleName -ErrorAction SilentlyContinue
Remove-Item Env:PWSH_SYNTAX_HIGHLIGHTING_SAFE_MODE -ErrorAction SilentlyContinue
Import-Module $moduleManifest -Force -ErrorAction Stop
Write-Host "  PASS: safe-mode reduced keymap validated"

Write-Host "[9/13] Validating upstream-parity token gating (keywords, variables, comments)..."
$gateCases = @(
    @{ Line = 'Get-ChildItem'; Expect = $true }
    @{ Line = 'git status'; Expect = $true }
    @{ Line = '.\script.ps1'; Expect = $true }
    @{ Line = '    Get-Date'; Expect = $true }
    @{ Line = 'if (Test-Path x) { }'; Expect = $false }
    @{ Line = 'foreach ($i in 1..3) { }'; Expect = $false }
    @{ Line = 'function foo { }'; Expect = $false }
    @{ Line = 'exit'; Expect = $false }
    @{ Line = 'return 1'; Expect = $false }
    @{ Line = 'try { } catch { }'; Expect = $false }
    @{ Line = '$foo'; Expect = $false }
    @{ Line = '@args'; Expect = $false }
    @{ Line = '# comment'; Expect = $false }
    @{ Line = '(Get-Date)'; Expect = $false }
    @{ Line = '1 + 2'; Expect = $false }
    @{ Line = "'quoted'"; Expect = $false }
)

$module = Get-Module $moduleName -ErrorAction Stop
$gateFailures = @()
foreach ($case in $gateCases) {
    $gateTokens = $null; $gateErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseInput($case.Line, [ref]$gateTokens, [ref]$gateErrors)
    $gateCtx = [pscustomobject]@{ Token = $gateTokens[0]; TokenText = [string]$gateTokens[0].Text }
    $gateActual = [bool](& $module { param($c) & $script:Highlighters[0].Predicate $c } $gateCtx)
    if ($gateActual -ne $case.Expect) {
        $gateFailures += "'$($case.Line)' expected=$($case.Expect) actual=$gateActual"
    }
}
if ($gateFailures.Count -gt 0) {
    $gateFailures | ForEach-Object { Write-Host "  $_" }
    throw "Token gating failed for $($gateFailures.Count) case(s)."
}
Write-Host "  PASS: keywords, variables, comments and operators are not validated"

Write-Host "[10/13] Validating throttle command (Set-SyntaxHighlightingThrottle)..."
Assert-Equal -Name 'Throttle default value' -Actual ([string](Set-SyntaxHighlightingThrottle -Get)) -Expected '50'
Assert-Equal -Name 'Throttle set value' -Actual ([string](Set-SyntaxHighlightingThrottle 120).ThrottleMs) -Expected '120'
Assert-Equal -Name 'Throttle persists after set' -Actual ([string](Set-SyntaxHighlightingThrottle -Get)) -Expected '120'
Assert-Equal -Name 'Throttle reset value' -Actual ([string](Set-SyntaxHighlightingThrottle -Reset).ThrottleMs) -Expected '50'
Assert-Equal -Name 'Throttle alias' -Actual ([string](Get-Alias -Name 'syntax-highlighting').Definition) -Expected 'Set-SyntaxHighlightingThrottle'
Write-Host "  PASS: throttle command and alias validated"

Write-Host "[11/13] Validating multi-token validation (pipelines, semicolons, wrapping)..."
$multiToken = & $module {
    $lines = @(
        'Get-ChildItem; nosuchcmd',
        'Get-ChildItem | Select-Object',
        'nosuchcmd | Select-Object',
        'Get-ChildItem -Path . | Where-Object { $_ } ; foo.exe'
    )

    $claims = foreach ($line in $lines) {
        $tokens = $null; $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseInput($line, [ref]$tokens, [ref]$errors)
        $claimed = foreach ($token in $tokens) {
            $ctx = [pscustomobject]@{ Token = $token; TokenText = [string]$token.Text }
            if (& $script:Highlighters[0].Predicate $ctx) { [string]$token.Text }
        }
        [pscustomobject]@{ Line = $line; Claimed = @($claimed) }
    }

    $wrapped = Get-ScreenRunForToken -Text ('#' + ('x' * 14)) -Offset 1 -Length 14 -StartX 0 -BufferWidth 10
    $offset = Get-ScreenRunForToken -Text 'abcGet-Date' -Offset 3 -Length 8 -StartX 6 -BufferWidth 120
    $afterNewline = Get-ScreenRunForToken -Text "aaa`nbbb" -Offset 4 -Length 3 -StartX 6 -BufferWidth 120

    [pscustomobject]@{
        Claims        = $claims
        WrappedRuns   = @($wrapped | ForEach-Object { "$($_.X),$($_.Y),$($_.Length)" })
        OffsetRun     = "$($offset[0].X),$($offset[0].Y),$($offset[0].Length)"
        NewlineRun    = "$($afterNewline[0].X),$($afterNewline[0].Y),$($afterNewline[0].Length)"
    }
}

Assert-Equal -Name 'Semicolon line claims both commands' -Actual ($multiToken.Claims[0].Claimed -join ',') -Expected 'Get-ChildItem,nosuchcmd'
Assert-Equal -Name 'Pipeline line claims both commands' -Actual ($multiToken.Claims[1].Claimed -join ',') -Expected 'Get-ChildItem,Select-Object'
Assert-Equal -Name 'Pipeline line claims invalid first command' -Actual ($multiToken.Claims[2].Claimed -join ',') -Expected 'nosuchcmd,Select-Object'
Assert-Equal -Name 'Mixed line claims three command tokens' -Actual ($multiToken.Claims[3].Claimed -join ',') -Expected 'Get-ChildItem,Where-Object,foo.exe'
Assert-Equal -Name 'Wrapped token splits into per-row runs' -Actual ($multiToken.WrappedRuns -join ' ') -Expected '1,0,9 0,1,5'
Assert-Equal -Name 'Token offset is added to the buffer origin' -Actual $multiToken.OffsetRun -Expected '9,0,8'
Assert-Equal -Name 'Token after a newline starts in the first column' -Actual $multiToken.NewlineRun -Expected '0,1,3'
Write-Host "  PASS: multi-token selection and screen-offset mapping validated"

Write-Host "[12/13] Validating degraded-mode gate and render-error diagnostics..."
$gate = & $module {
    $savedRetryMs = $script:DegradedRetryMs
    $savedDegraded = $script:DegradedMode
    $savedSince = $script:DegradedSince
    $savedErrors = $script:Perf.RenderErrors

    $script:DegradedRetryMs = 60000
    $script:DegradedMode = $true
    $script:DegradedSince = [Environment]::TickCount64

    $blockedWhileCooling = -not (& $script:EnterRenderGate 'T')

    # Pretend the retry window has elapsed
    $script:DegradedSince = [Environment]::TickCount64 - 61000
    $allowedAfterWindow = [bool](& $script:EnterRenderGate 'T')
    $stateCleared = -not $script:DegradedMode
    $errorsReset = ($script:Perf.RenderErrors -eq 0)

    $script:DegradedRetryMs = $savedRetryMs
    $script:DegradedMode = $savedDegraded
    $script:DegradedSince = $savedSince
    $script:Perf.RenderErrors = $savedErrors

    [pscustomobject]@{
        BlockedWhileCooling = $blockedWhileCooling
        AllowedAfterWindow  = $allowedAfterWindow
        StateCleared        = $stateCleared
        ErrorsReset         = $errorsReset
        MetricsHaveError    = ($null -ne $global:SyntaxHighlightingMetrics -and
                               $null -ne $global:SyntaxHighlightingMetrics.PSObject.Properties['LastRenderError'])
        MetricsHaveRetry    = ($null -ne $global:SyntaxHighlightingMetrics -and
                               $null -ne $global:SyntaxHighlightingMetrics.PSObject.Properties['DegradedRetryMs'])
    }
}

Assert-True -Name 'Degraded mode blocks renders inside the retry window' -Condition $gate.BlockedWhileCooling
Assert-True -Name 'Degraded mode retries after the window elapses' -Condition $gate.AllowedAfterWindow
Assert-True -Name 'Retry clears degraded mode' -Condition $gate.StateCleared
Assert-True -Name 'Retry resets the render error count' -Condition $gate.ErrorsReset
Assert-True -Name 'Metrics expose LastRenderError' -Condition $gate.MetricsHaveError
Assert-True -Name 'Metrics expose DegradedRetryMs' -Condition $gate.MetricsHaveRetry
Write-Host "  PASS: degradation is time-limited and errors stay diagnosable"

Write-Host "[13/13] Validating key binding restore after remove..."
Remove-Module $moduleName -ErrorAction Stop
foreach ($k in $expectedDefault.Keys) {
    Assert-Equal -Name "Default key binding ($k)" -Actual (Get-KeyFunction -Key $k) -Expected $expectedDefault[$k]
}
Assert-Equal -Name 'Default key binding (Tab)' -Actual (Get-KeyFunction -Key 'Tab') -Expected 'Complete'
Write-Host "  PASS: default key bindings restored"

Write-Host ''
Write-Host 'All local checks passed.'
Write-Host "Performance: $Cycles lifecycle cycles in $([math]::Round($sw.Elapsed.TotalMilliseconds, 2)) ms"