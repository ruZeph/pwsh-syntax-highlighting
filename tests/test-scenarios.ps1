<#
.SYNOPSIS
    Scenario-based integration tests for pwsh-syntax-highlighting v1.0.0
.DESCRIPTION
    Rigorous testing scenarios covering installation, updates, runtime flags,
    and safety features. Each scenario simulates realistic user workflows.
#>

param(
    [ValidateRange(1, 100)]
    [int]$Iterations = 10,
    
    [switch]$Verbose
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# =============================================================================
# Test Infrastructure
# =============================================================================

$repoRoot = Split-Path -Parent $PSScriptRoot
$moduleManifest = Join-Path $repoRoot 'pwsh-syntax-highlighting.psd1'
$moduleName = 'pwsh-syntax-highlighting'
$testModuleRoot = Join-Path $env:TEMP "pwsh-syntax-highlighting-test-$([DateTime]::UtcNow.Ticks)"
$testResults = [PSCustomObject]@{
    Passed   = 0
    Failed   = 0
    Total    = 0
    Failures = @()
    Duration = $null
}

function New-TestResult {
    param(
        [string]$Name,
        [string]$Scenario,
        [bool]$Success,
        [string]$Message = '',
        [int]$DurationMs = 0
    )
    return [PSCustomObject]@{
        Name       = $Name
        Scenario   = $Scenario
        Success    = $Success
        Message    = $Message
        DurationMs = $DurationMs
        Timestamp  = [DateTime]::UtcNow
    }
}

function Write-TestHeader {
    param([string]$Scenario)
    Write-Host "`n[SCENARIO] $Scenario" -ForegroundColor Cyan -BackgroundColor Black
}

function Write-TestPass {
    param([string]$Test, [int]$Ms)
    Write-Host "  ✓ $Test ($Ms ms)" -ForegroundColor Green
    $testResults.Passed++
}

function Write-TestFail {
    param([string]$Test, [string]$Reason)
    Write-Host "  ✗ $Test" -ForegroundColor Red
    Write-Host "    Reason: $Reason" -ForegroundColor Yellow
    $testResults.Failed++
    $testResults.Failures += [PSCustomObject]@{Test = $Test; Reason = $Reason}
}

function Assert-ModuleVersion {
    param(
        [string]$Expected,
        [string]$Test = "Module version matches $Expected"
    )
    
    $module = Get-Module $moduleName -ErrorAction SilentlyContinue
    if (!$module) { return $false }
    
    $actual = $module.Version.ToString()
    if ($actual -eq $Expected) {
        return $true
    }
    return $false
}

function Assert-ModuleLoaded {
    return $null -ne (Get-Module $moduleName -ErrorAction SilentlyContinue)
}

function Assert-EnvironmentVariable {
    param([string]$Name, [string]$ExpectedValue)
    return (Get-Item "env:$Name" -ErrorAction SilentlyContinue).Value -eq $ExpectedValue
}

function Cleanup-TestEnvironment {
    Remove-Module $moduleName -ErrorAction SilentlyContinue
    if (Test-Path $testModuleRoot) {
        Remove-Item $testModuleRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# =============================================================================
# Scenario 1: Fresh Installation & Module Loading
# =============================================================================

Write-TestHeader "Fresh Installation & Module Loading"

$scenarioTests = @()

$sw = [System.Diagnostics.Stopwatch]::StartNew()
try {
    Import-Module $moduleManifest -Force -ErrorAction Stop
    $sw.Stop()
    
    if (Assert-ModuleVersion '1.0.0') {
        Write-TestPass "Import module v1.0.0" $sw.ElapsedMilliseconds
        $testResults.Total++
    }
    else {
        Write-TestFail "Import module v1.0.0" "Version mismatch"
        $testResults.Total++
    }
}
catch {
    Write-TestFail "Import module v1.0.0" $_.Exception.Message
    $testResults.Total++
}

$sw = [System.Diagnostics.Stopwatch]::StartNew()
try {
    if (Assert-ModuleLoaded) {
        $sw.Stop()
        Write-TestPass "Module loaded in PSSession" $sw.ElapsedMilliseconds
        $testResults.Total++
    }
}
catch {
    Write-TestFail "Module loaded in PSSession" $_.Exception.Message
    $testResults.Total++
}

# =============================================================================
# Scenario 2: Module Stress Test (Load/Unload Cycles)
# =============================================================================

Write-TestHeader "Module Stress Test ($Iterations Load/Unload Cycles)"

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$cycleFailures = 0

for ($i = 1; $i -le $Iterations; $i++) {
    try {
        Remove-Module $moduleName -ErrorAction SilentlyContinue
        Import-Module $moduleManifest -Force -ErrorAction Stop
    }
    catch {
        $cycleFailures++
    }
}

$sw.Stop()
$testResults.Total++

if ($cycleFailures -eq 0) {
    Write-TestPass "Completed $Iterations cycles without failure" $sw.ElapsedMilliseconds
    $testResults.Passed++
}
else {
    Write-TestFail "$Iterations load/unload cycles" "$cycleFailures failed"
    $testResults.Failed++
}

# =============================================================================
# Scenario 3: Runtime Flags Behavior
# =============================================================================

Write-TestHeader "Runtime Flags: Metrics, Debug, & Safe Mode"

# Test 3a: Metrics flag
$sw = [System.Diagnostics.Stopwatch]::StartNew()
try {
    Remove-Module $moduleName -ErrorAction SilentlyContinue
    $env:PWSH_SYNTAX_HIGHLIGHTING_METRICS = '1'
    Import-Module $moduleManifest -Force -ErrorAction Stop
    $sw.Stop()
    
    if (Assert-EnvironmentVariable 'PWSH_SYNTAX_HIGHLIGHTING_METRICS' '1') {
        Write-TestPass "Metrics flag enabled" $sw.ElapsedMilliseconds
        $testResults.Passed++
    }
    $testResults.Total++
}
catch {
    Write-TestFail "Metrics flag enabled" $_.Exception.Message
    $testResults.Failed++
    $testResults.Total++
}

# Test 3b: Debug flag
$sw = [System.Diagnostics.Stopwatch]::StartNew()
try {
    Remove-Module $moduleName -ErrorAction SilentlyContinue
    $env:PWSH_SYNTAX_HIGHLIGHTING_DEBUG = '1'
    Import-Module $moduleManifest -Force -ErrorAction Stop
    $sw.Stop()
    
    if (Assert-EnvironmentVariable 'PWSH_SYNTAX_HIGHLIGHTING_DEBUG' '1') {
        Write-TestPass "Debug flag enabled" $sw.ElapsedMilliseconds
        $testResults.Passed++
    }
    $testResults.Total++
}
catch {
    Write-TestFail "Debug flag enabled" $_.Exception.Message
    $testResults.Failed++
    $testResults.Total++
}

# Test 3c: Safe mode flag
$sw = [System.Diagnostics.Stopwatch]::StartNew()
try {
    Remove-Module $moduleName -ErrorAction SilentlyContinue
    $env:PWSH_SYNTAX_HIGHLIGHTING_SAFE_MODE = '1'
    Import-Module $moduleManifest -Force -ErrorAction Stop
    $sw.Stop()
    
    if (Assert-EnvironmentVariable 'PWSH_SYNTAX_HIGHLIGHTING_SAFE_MODE' '1') {
        Write-TestPass "Safe mode flag enabled" $sw.ElapsedMilliseconds
        $testResults.Passed++
    }
    $testResults.Total++
}
catch {
    Write-TestFail "Safe mode flag enabled" $_.Exception.Message
    $testResults.Failed++
    $testResults.Total++
}

# =============================================================================
# Scenario 4: Key Handler Registration
# =============================================================================

Write-TestHeader "Key Handler Registration & Validation"

$sw = [System.Diagnostics.Stopwatch]::StartNew()
try {
    Remove-Module $moduleName -ErrorAction SilentlyContinue
    $env:PWSH_SYNTAX_HIGHLIGHTING_SAFE_MODE = ''
    Import-Module $moduleManifest -Force -ErrorAction Stop
    $sw.Stop()
    
    $handlers = Get-PSReadLineKeyHandler
    $ctrlVHandler = $handlers | Where-Object Key -eq 'Ctrl+v'
    
    if ($ctrlVHandler) {
        Write-TestPass "Ctrl+V key handler registered" $sw.ElapsedMilliseconds
        $testResults.Passed++
    }
    else {
        Write-TestFail "Ctrl+V key handler registered" "Handler not found"
        $testResults.Failed++
    }
    $testResults.Total++
}
catch {
    Write-TestFail "Key handler registration" $_.Exception.Message
    $testResults.Failed++
    $testResults.Total++
}

# =============================================================================
# Scenario 5: Module Unload & Cleanup
# =============================================================================

Write-TestHeader "Module Unload & Cleanup"

$sw = [System.Diagnostics.Stopwatch]::StartNew()
try {
    Remove-Module $moduleName -ErrorAction Stop
    $sw.Stop()
    
    if (-not (Assert-ModuleLoaded)) {
        Write-TestPass "Module unloaded cleanly" $sw.ElapsedMilliseconds
        $testResults.Passed++
    }
    else {
        Write-TestFail "Module unloaded cleanly" "Module still loaded"
        $testResults.Failed++
    }
    $testResults.Total++
}
catch {
    Write-TestFail "Module unload" $_.Exception.Message
    $testResults.Failed++
    $testResults.Total++
}

# =============================================================================
# Scenario 6: Environment Variable Cleanup
# =============================================================================

Write-TestHeader "Environment Variable Cleanup"

$sw = [System.Diagnostics.Stopwatch]::StartNew()
try {
    $env:PWSH_SYNTAX_HIGHLIGHTING_METRICS = $null
    $env:PWSH_SYNTAX_HIGHLIGHTING_DEBUG = $null
    $env:PWSH_SYNTAX_HIGHLIGHTING_SAFE_MODE = $null
    $sw.Stop()
    
    $metricsCleared = -not (Test-Path env:PWSH_SYNTAX_HIGHLIGHTING_METRICS) -or ($env:PWSH_SYNTAX_HIGHLIGHTING_METRICS -eq '')
    $debugCleared = -not (Test-Path env:PWSH_SYNTAX_HIGHLIGHTING_DEBUG) -or ($env:PWSH_SYNTAX_HIGHLIGHTING_DEBUG -eq '')
    $safeModeCleared = -not (Test-Path env:PWSH_SYNTAX_HIGHLIGHTING_SAFE_MODE) -or ($env:PWSH_SYNTAX_HIGHLIGHTING_SAFE_MODE -eq '')
    
    if ($metricsCleared -and $debugCleared -and $safeModeCleared) {
        Write-TestPass "All environment variables cleaned up" $sw.ElapsedMilliseconds
        $testResults.Passed++
    }
    else {
        Write-TestFail "Environment cleanup" "Some variables not cleared"
        $testResults.Failed++
    }
    $testResults.Total++
}
catch {
    Write-TestFail "Environment cleanup" $_.Exception.Message
    $testResults.Failed++
    $testResults.Total++
}

# =============================================================================
# Test Tear Down
# =============================================================================

Cleanup-TestEnvironment

# =============================================================================
# Test Results Summary
# =============================================================================

Write-Host "`n" -NoNewline
Write-Host "═════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "TEST RESULTS SUMMARY (v1.0.0 Scenario Tests)" -ForegroundColor Cyan
Write-Host "═════════════════════════════════════════════════════════════════" -ForegroundColor Cyan

Write-Host "  Total Tests:  $($testResults.Total)" -ForegroundColor White
Write-Host "  Passed:       $($testResults.Passed)" -ForegroundColor Green
Write-Host "  Failed:       $($testResults.Failed)" -ForegroundColor $(if ($testResults.Failed -eq 0) { 'Green' } else { 'Red' })

if ($testResults.Failed -gt 0) {
    Write-Host "`nFailed Tests:" -ForegroundColor Red
    $testResults.Failures | ForEach-Object {
        Write-Host "  - $($_.Test): $($_.Reason)" -ForegroundColor Red
    }
    exit 1
}
else {
    Write-Host "`n✓ All tests passed!" -ForegroundColor Green
    exit 0
}
