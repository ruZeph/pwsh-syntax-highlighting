<#
.SYNOPSIS
    Measures the hot paths of pwsh-syntax-highlighting.
.DESCRIPTION
    Benchmarks the work a keystroke actually triggers, one component at a time so a
    regression can be attributed:

      import     - module import + key-handler registration
      tokenize   - the PowerShell parser pass PSReadLine does inside GetBufferState
      paint-warm - highlighter predicate + Paint with a warm command cache
      paint-cold - same, with the cache cleared every iteration (Get-Command cost)
      screen-map - buffer offset -> terminal cell run mapping
      render     - full RenderAction (only measurable with a real console attached)

    Reports p50/p95/p99/max per component and supports -Json for before/after comparison
    across git revisions (point -ManifestPath/-ModulePath at another checkout).
.EXAMPLE
    pwsh -File scripts/benchmark-render.ps1 -Iterations 2000
.EXAMPLE
    pwsh -File scripts/benchmark-render.ps1 -Iterations 5000 -Json out.json
#>
[CmdletBinding()]
param(
    [ValidateRange(10, 200000)]
    [int]$Iterations = 1000,

    [ValidateRange(0, 20000)]
    [int]$WarmupIterations = 200,

    [string]$ManifestPath,

    [string]$ModulePath,

    [ValidateSet('short', 'long', 'pipeline')]
    [string]$Scenario = 'pipeline',

    [string]$Json,

    [string]$Label = 'current'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $ManifestPath) { $ManifestPath = Join-Path $repoRoot 'pwsh-syntax-highlighting.psd1' }

$scenarios = @{
    short    = 'Get-ChildItem'
    long     = 'Get-ChildItem -Path . -Filter *.ps1 -Recurse -Depth 1 -ErrorAction SilentlyContinue'
    pipeline = 'Get-ChildItem; nosuchcmd | Select-Object -First 5'
}
$line = $scenarios[$Scenario]

function Get-Percentile {
    param([double[]]$Values, [double]$Percentile)

    if (-not $Values -or $Values.Count -eq 0) { return [double]::NaN }
    $sorted = @($Values | Sort-Object)
    if ($sorted.Count -eq 1) { return [double]$sorted[0] }

    $rank = ($Percentile / 100.0) * ($sorted.Count - 1)
    $lower = [int][Math]::Floor($rank)
    $upper = [int][Math]::Ceiling($rank)
    if ($lower -eq $upper) { return [double]$sorted[$lower] }
    $weight = $rank - $lower
    return ([double]$sorted[$lower] * (1 - $weight)) + ([double]$sorted[$upper] * $weight)
}

function Measure-Component {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [int]$Count = $Iterations,
        [int]$Warmup = $WarmupIterations
    )

    for ($i = 0; $i -lt $Warmup; $i++) { & $Action }

    $samples = New-Object 'double[]' $Count
    for ($i = 0; $i -lt $Count; $i++) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        & $Action
        $sw.Stop()
        $samples[$i] = $sw.Elapsed.TotalMilliseconds
    }

    $mean = ($samples | Measure-Object -Average).Average
    [pscustomobject]@{
        Component = $Name
        Samples   = $Count
        MeanMs    = [math]::Round($mean, 4)
        P50Ms     = [math]::Round((Get-Percentile -Values $samples -Percentile 50), 4)
        P95Ms     = [math]::Round((Get-Percentile -Values $samples -Percentile 95), 4)
        P99Ms     = [math]::Round((Get-Percentile -Values $samples -Percentile 99), 4)
        MaxMs     = [math]::Round(($samples | Measure-Object -Maximum).Maximum, 4)
        OpsPerSec = if ($mean -gt 0) { [math]::Round(1000 / $mean, 0) } else { 0 }
    }
}

$results = New-Object System.Collections.Generic.List[object]
$warmupDefault = $WarmupIterations

# --- import -------------------------------------------------------------------------------
Remove-Module pwsh-syntax-highlighting -ErrorAction SilentlyContinue
$importSamples = New-Object System.Collections.Generic.List[double]
for ($i = 0; $i -lt 10; $i++) {
    Remove-Module pwsh-syntax-highlighting -ErrorAction SilentlyContinue
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    if ($ModulePath) { Import-Module $ModulePath -Force -ErrorAction Stop }
    else { Import-Module $ManifestPath -Force -ErrorAction Stop }
    $sw.Stop()
    $importSamples.Add($sw.Elapsed.TotalMilliseconds)
}
$importArray = $importSamples.ToArray()
$results.Add([pscustomobject]@{
        Component = 'import'
        Samples   = $importArray.Count
        MeanMs    = [math]::Round(($importArray | Measure-Object -Average).Average, 3)
        P50Ms     = [math]::Round((Get-Percentile -Values $importArray -Percentile 50), 3)
        P95Ms     = [math]::Round((Get-Percentile -Values $importArray -Percentile 95), 3)
        P99Ms     = [math]::Round((Get-Percentile -Values $importArray -Percentile 99), 3)
        MaxMs     = [math]::Round(($importArray | Measure-Object -Maximum).Maximum, 3)
        OpsPerSec = 0
    })

$module = Get-Module pwsh-syntax-highlighting -ErrorAction Stop

# --- tokenize -----------------------------------------------------------------------------
$results.Add((Measure-Component -Name 'tokenize' -Action {
            $tokens = $null; $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseInput($line, [ref]$tokens, [ref]$errors)
        }))

# --- highlighter predicate + paint --------------------------------------------------------
$paint = & $module {
    $tokens = $null; $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseInput($args[0], [ref]$tokens, [ref]$errors)
    $first = $tokens | Where-Object { $_.TokenFlags -band [System.Management.Automation.Language.TokenFlags]::CommandName } | Select-Object -First 1
    if (-not $first) { $first = $tokens[0] }
    [pscustomobject]@{
        Predicate = $script:Highlighters[0].Predicate
        Paint     = $script:Highlighters[0].Paint
        Ctx       = [pscustomobject]@{ Token = $first; TokenText = [string]$first.Text }
    }
} $line

$results.Add((Measure-Component -Name 'paint-warm' -Action {
            if (& $paint.Predicate $paint.Ctx) { $null = & $paint.Paint $paint.Ctx }
        }))

$results.Add((Measure-Component -Name 'paint-cold' -Action {
            & $module { $script:CommandLookupCache.Clear(); while ($script:CommandLookupOrder.Count -gt 0) { [void]$script:CommandLookupOrder.Dequeue() } } | Out-Null
            if (& $paint.Predicate $paint.Ctx) { $null = & $paint.Paint $paint.Ctx }
        } -Count ([Math]::Max(10, [int]($Iterations / 10))) -Warmup ([Math]::Min($warmupDefault, 20))))

# --- screen mapping -----------------------------------------------------------------------
$hasMapper = $false
try {
    $hasMapper = [bool](& $module { $null -ne (Get-Command Get-ScreenRunForToken -ErrorAction SilentlyContinue) })
}
catch {
    $hasMapper = $false
}

if ($hasMapper) {
    $results.Add((Measure-Component -Name 'screen-map' -Action {
                $null = & $module { Get-ScreenRunForToken -Text $args[0] -Offset 20 -Length 12 -StartX 44 -BufferWidth 120 } $line
            }))
}

# --- full render (console only) ------------------------------------------------------------
$consoleRenderable = (& $module { $script:Preflight.HostSupportsRawUI -and $script:Preflight.PSReadLineLoaded })
if ($consoleRenderable) {
    $results.Add((Measure-Component -Name 'render(console)' -Action {
                & $module { & $script:RenderAction } | Out-Null
            } -Count ([Math]::Max(10, [int]($Iterations / 10))) -Warmup ([Math]::Min($warmupDefault, 20))))
}

else {
    $results.Add([pscustomobject]@{
            Component = 'render(n/a - no console)'
            Samples   = 0; MeanMs = 0; P50Ms = 0; P95Ms = 0; P99Ms = 0; MaxMs = 0; OpsPerSec = 0
        })
}

$results | Format-Table -AutoSize

$payload = [pscustomobject]@{
    Label     = $Label
    Scenario  = $Scenario
    Line      = $line
    Iterations = $Iterations
    Timestamp = (Get-Date).ToString('o')
    PsVersion = $PSVersionTable.PSVersion.ToString()
    Results   = $results.ToArray()
}
if ($Json) {
    $payload | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Json -Encoding utf8
    Write-Output "wrote $Json"
}
