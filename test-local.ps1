param(
    [ValidateRange(1, 10000)]
    [int]$Cycles = 100
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleName = 'syntax-highlighting'
$moduleManifest = Join-Path $PSScriptRoot 'syntax-highlighting.psd1'
$keys = @('UpArrow', 'DownArrow', 'RightArrow', 'LeftArrow', 'Backspace', 'Delete')
$expectedDefault = @{
    UpArrow = 'PreviousHistory'
    DownArrow = 'NextHistory'
    RightArrow = 'ForwardChar'
    LeftArrow = 'BackwardChar'
    Backspace = 'BackwardDeleteChar'
    Delete = 'DeleteChar'
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
    $printableKey = [System.ConsoleKeyInfo]::new('a', [System.ConsoleKey]::A, $false, $false, $false)
    & $script:RenderAction $printableKey
    $afterPrintable = [int]$script:Perf.Throttled

    $script:LastRenderTick = [Environment]::TickCount64
    $spaceKey = [System.ConsoleKeyInfo]::new(' ', [System.ConsoleKey]::Spacebar, $false, $false, $false)
    & $script:RenderAction $spaceKey
    $afterSpace = [int]$script:Perf.Throttled

    [pscustomobject]@{
        Printable = $afterPrintable
        Space = $afterSpace
    }
}
Assert-True -Name 'Printable key should be throttle-eligible at 0ms elapsed' -Condition ($throttleCheck.Printable -ge 1)
Assert-Equal -Name 'Space key should bypass throttle at 0ms elapsed' -Actual ([string]$throttleCheck.Space) -Expected ([string]$throttleCheck.Printable)
Write-Host "  PASS: immediate-key throttle bypass works"

Write-Host "[5/5] Validating key binding restore after remove..."
Remove-Module $moduleName -ErrorAction Stop
foreach ($k in $expectedDefault.Keys) {
    Assert-Equal -Name "Default key binding ($k)" -Actual (Get-KeyFunction -Key $k) -Expected $expectedDefault[$k]
}
Assert-Equal -Name 'Default key binding (Tab)' -Actual (Get-KeyFunction -Key 'Tab') -Expected 'Complete'
Write-Host "  PASS: default key bindings restored"

Write-Host ''
Write-Host 'All local checks passed.'
Write-Host "Performance: $Cycles lifecycle cycles in $([math]::Round($sw.Elapsed.TotalMilliseconds, 2)) ms"