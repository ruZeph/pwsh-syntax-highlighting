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

Write-Host "[1/4] Running lifecycle stress test ($Cycles cycles)..."
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

Write-Host "[2/4] Validating custom key bindings after import..."
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

Write-Host "[3/4] Validating render action smoke test..."
$module = Get-Module $moduleName -ErrorAction Stop
$renderResult = & $module { & $script:RenderAction; 'render-ok' }
Assert-Equal -Name 'RenderAction invocation' -Actual $renderResult -Expected 'render-ok'
Write-Host "  PASS: render action executes"

Write-Host "[4/5] Validating immediate-key throttle bypass edge case..."
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

Write-Host "[5/6] Validating debug trace and cache behavior under simulated key flow..."
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

Write-Host "[6/7] Validating command cache miss/hit behavior directly..."
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

Write-Host "[7/8] Validating failure injection resilience..."
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

Write-Host "[8/9] Validating safe-mode reduced keymap..."
Remove-Module $moduleName -ErrorAction SilentlyContinue
$env:PWSH_SYNTAX_HIGHLIGHTING_SAFE_MODE = '1'
Import-Module $moduleManifest -Force -ErrorAction Stop
$altF = Get-KeyFunction -Key 'Alt+f'
Assert-True -Name 'Safe mode should not register extended compatibility key handlers' -Condition ($altF -ne 'ValidatePrograms')
Remove-Module $moduleName -ErrorAction SilentlyContinue
Remove-Item Env:PWSH_SYNTAX_HIGHLIGHTING_SAFE_MODE -ErrorAction SilentlyContinue
Import-Module $moduleManifest -Force -ErrorAction Stop
Write-Host "  PASS: safe-mode reduced keymap validated"

Write-Host "[9/9] Validating key binding restore after remove..."
Remove-Module $moduleName -ErrorAction Stop
foreach ($k in $expectedDefault.Keys) {
    Assert-Equal -Name "Default key binding ($k)" -Actual (Get-KeyFunction -Key $k) -Expected $expectedDefault[$k]
}
Assert-Equal -Name 'Default key binding (Tab)' -Actual (Get-KeyFunction -Key 'Tab') -Expected 'Complete'
Write-Host "  PASS: default key bindings restored"

Write-Host ''
Write-Host 'All local checks passed.'
Write-Host "Performance: $Cycles lifecycle cycles in $([math]::Round($sw.Elapsed.TotalMilliseconds, 2)) ms"