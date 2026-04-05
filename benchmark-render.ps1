param(
    [ValidateRange(10, 200000)]
    [int]$Iterations = 500,

    [ValidateRange(0, 10000)]
    [int]$WarmupIterations = 100
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleManifest = Join-Path $PSScriptRoot 'syntax-highlighting.psd1'
if (-not (Test-Path $moduleManifest)) {
    throw "Module manifest not found: $moduleManifest"
}

function Get-Percentile {
    param(
        [Parameter(Mandatory = $true)]
        [double[]]$Values,

        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 100)]
        [double]$Percentile
    )

    if (-not $Values -or $Values.Count -eq 0) {
        return [double]::NaN
    }

    $sorted = $Values | Sort-Object
    if ($sorted.Count -eq 1) {
        return [double]$sorted[0]
    }

    $rank = ($Percentile / 100.0) * ($sorted.Count - 1)
    $lowerIndex = [int][Math]::Floor($rank)
    $upperIndex = [int][Math]::Ceiling($rank)
    if ($lowerIndex -eq $upperIndex) {
        return [double]$sorted[$lowerIndex]
    }

    $weight = $rank - $lowerIndex
    return ([double]$sorted[$lowerIndex] * (1 - $weight)) + ([double]$sorted[$upperIndex] * $weight)
}

function Invoke-RenderMeasure {
    param(
        [Parameter(Mandatory = $true)]
        [int]$Count
    )

    $samples = New-Object System.Collections.Generic.List[double]
    $mod = Get-Module syntax-highlighting -ErrorAction Stop

    for ($i = 0; $i -lt $Count; $i++) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        & $mod { & $script:RenderAction } | Out-Null
        $sw.Stop()
        $samples.Add($sw.Elapsed.TotalMilliseconds)
    }

    return ,$samples.ToArray()
}

Write-Host "Preparing benchmark environment..."
$env:PWSH_SYNTAX_HIGHLIGHTING_METRICS = '1'
Remove-Module syntax-highlighting -ErrorAction SilentlyContinue
Import-Module $moduleManifest -Force

if ($WarmupIterations -gt 0) {
    Write-Host "Warmup: $WarmupIterations render calls"
    [void](Invoke-RenderMeasure -Count $WarmupIterations)
}

Write-Host "Benchmark: $Iterations render calls"
$samples = Invoke-RenderMeasure -Count $Iterations

$avg = ($samples | Measure-Object -Average).Average
$min = ($samples | Measure-Object -Minimum).Minimum
$max = ($samples | Measure-Object -Maximum).Maximum
$p50 = Get-Percentile -Values $samples -Percentile 50
$p95 = Get-Percentile -Values $samples -Percentile 95
$p99 = Get-Percentile -Values $samples -Percentile 99

$report = [pscustomobject]@{
    Iterations = $Iterations
    WarmupIterations = $WarmupIterations
    AvgMs = [math]::Round($avg, 4)
    MinMs = [math]::Round($min, 4)
    P50Ms = [math]::Round($p50, 4)
    P95Ms = [math]::Round($p95, 4)
    P99Ms = [math]::Round($p99, 4)
    MaxMs = [math]::Round($max, 4)
}

Write-Host ''
Write-Host 'Render latency summary (ms):'
$report | Format-List

if ($null -ne $global:SyntaxHighlightingMetrics) {
    Write-Host ''
    Write-Host 'Module metrics snapshot:'
    $global:SyntaxHighlightingMetrics | Format-List
}

Write-Host ''
Write-Host 'Tip: run multiple times and compare p95/p99 between branches.'