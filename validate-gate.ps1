param(
    [ValidateRange(1, 10000)]
    [int]$Cycles = 50,

    [ValidateRange(10, 200000)]
    [int]$BenchmarkIterations = 200,

    [ValidateRange(0, 10000)]
    [int]$BenchmarkWarmup = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host '[gate] Running local reliability suite...'
& "$PSScriptRoot\test-local.ps1" -Cycles $Cycles

Write-Host '[gate] Running render micro-benchmark...'
& "$PSScriptRoot\benchmark-render.ps1" -Iterations $BenchmarkIterations -WarmupIterations $BenchmarkWarmup

Write-Host ''
Write-Host '[gate] Completed successfully.'
