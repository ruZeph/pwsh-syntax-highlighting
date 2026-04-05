<#
.SYNOPSIS
    Master test orchestrator for pwsh-syntax-highlighting v1.0.0
.DESCRIPTION
    Runs all test suites (local reliability, scenario-based, installer safety)
    and provides comprehensive results summary.
#>

param(
    [ValidateRange(1, 100)]
    [int]$StressCycles = 10,
    
    [switch]$Quick,
    [switch]$Verbose
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$testsDir = $PSScriptRoot
$repoRoot = Split-Path -Parent $testsDir

Write-Host "`n" -NoNewline
Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  pwsh-syntax-highlighting v1.0.0 - Master Test Suite          ║" -ForegroundColor Cyan
Write-Host "║  Automated Scenario & Integration Testing                     ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

$totalResults = @{
    Suites      = @()
    TotalPassed = 0
    TotalFailed = 0
    StartTime   = [DateTime]::UtcNow
}

# =============================================================================
# Test Suite 1: Installer Safety Tests
# =============================================================================

Write-Host "[1/3] Running Installer Safety Tests..." -ForegroundColor Cyan
$installerTestPath = Join-Path $testsDir 'test-installer.ps1'
$sw = [System.Diagnostics.Stopwatch]::StartNew()

try {
    & $installerTestPath
    $sw.Stop()
    $installerPass = $true
    $installerDuration = $sw.Elapsed.TotalSeconds
    $installerExitCode = $LASTEXITCODE
}
catch {
    $sw.Stop()
    $installerPass = $false
    $installerDuration = $sw.Elapsed.TotalSeconds
    Write-Host "  Installer tests failed: $($_.Exception.Message)" -ForegroundColor Red
}

$totalResults.Suites += @{
    Name     = 'Installer Safety Tests'
    Passed   = $installerPass
    Duration = $installerDuration
}

if (-not $Quick) {
    # =============================================================================
    # Test Suite 2: Scenario-Based Integration Tests
    # =============================================================================

    Write-Host "`n[2/3] Running Scenario-Based Integration Tests..." -ForegroundColor Cyan
    $scenarioTestPath = Join-Path $testsDir 'test-scenarios.ps1'
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        & $scenarioTestPath -Iterations $StressCycles -Verbose:$Verbose
        $sw.Stop()
        $scenarioPass = $true
        $scenarioDuration = $sw.Elapsed.TotalSeconds
    }
    catch {
        $sw.Stop()
        $scenarioPass = $false
        $scenarioDuration = $sw.Elapsed.TotalSeconds
        Write-Host "  Scenario tests failed: $($_.Exception.Message)" -ForegroundColor Red
    }

    $totalResults.Suites += @{
        Name     = 'Scenario-Based Tests'
        Passed   = $scenarioPass
        Duration = $scenarioDuration
    }

    # =============================================================================
    # Test Suite 3: Local Reliability Tests
    # =============================================================================

    Write-Host "`n[3/3] Running Local Reliability Tests..." -ForegroundColor Cyan
    $localTestPath = Join-Path $testsDir 'test-local.ps1'
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        & $localTestPath -Cycles 50
        $sw.Stop()
        $localPass = $true
        $localDuration = $sw.Elapsed.TotalSeconds
    }
    catch {
        $sw.Stop()
        $localPass = $false
        $localDuration = $sw.Elapsed.TotalSeconds
        Write-Host "  Local tests failed: $($_.Exception.Message)" -ForegroundColor Red
    }

    $totalResults.Suites += @{
        Name     = 'Local Reliability Tests'
        Passed   = $localPass
        Duration = $localDuration
    }
}
else {
    Write-Host "`n[2/2] Skipping full test suite (Quick mode)" -ForegroundColor Yellow
}

$totalResults.EndTime = [DateTime]::UtcNow
$totalResults.TotalDuration = ($totalResults.EndTime - $totalResults.StartTime).TotalSeconds

# =============================================================================
# Results Summary
# =============================================================================

Write-Host "`n" -NoNewline
Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  TEST EXECUTION SUMMARY                                        ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

$allPassed = $true
foreach ($suite in $totalResults.Suites) {
    $status = if ($suite.Passed) { "✓ PASS" } else { "✗ FAIL" }
    $color = if ($suite.Passed) { "Green" } else { "Red" }
    Write-Host "  [$status]  $($suite.Name)" -ForegroundColor $color
    Write-Host "           Duration: $([math]::Round($suite.Duration, 2))s" -ForegroundColor Gray
    
    if (-not $suite.Passed) {
        $allPassed = $false
    }
}

Write-Host ""
Write-Host "  Total Duration: $([math]::Round($totalResults.TotalDuration, 2))s" -ForegroundColor Gray
Write-Host "  Test Mode: $(if ($Quick) { 'Quick (installer only)' } else { 'Full (all suites)' })" -ForegroundColor Gray
Write-Host ""

if ($allPassed) {
    Write-Host "  ✓ ALL TESTS PASSED" -ForegroundColor Green -BackgroundColor Black
    Write-Host ""
    exit 0
}
else {
    Write-Host "  ✗ SOME TESTS FAILED" -ForegroundColor Red -BackgroundColor Black
    Write-Host ""
    exit 1
}
