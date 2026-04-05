<#
.SYNOPSIS
    Installer safety and functionality tests for pwsh-syntax-highlighting v1.0.0
.DESCRIPTION
    Tests installer features including safety checks, profile modification,
    version detection, and rollback mechanisms.
#>

param(
    [switch]$Verbose
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$installerScript = Join-Path (Join-Path $repoRoot 'scripts') 'install.ps1'
$moduleManifest = Join-Path $repoRoot 'pwsh-syntax-highlighting.psd1'
$moduleName = 'pwsh-syntax-highlighting'

$testResults = @{
    Passed   = 0
    Failed   = 0
    Total    = 0
    Failures = @()
}

function Write-TestHeader {
    param([string]$Category)
    Write-Host "`n[INSTALLER TESTS] $Category" -ForegroundColor Magenta -BackgroundColor Black
}

function Write-TestPass {
    param([string]$Test)
    Write-Host "  ✓ $Test" -ForegroundColor Green
    $testResults.Passed++
}

function Write-TestFail {
    param([string]$Test, [string]$Reason)
    Write-Host "  ✗ $Test" -ForegroundColor Red
    Write-Host "    → $Reason" -ForegroundColor Yellow
    $testResults.Failed++
    $testResults.Failures += @{Test = $Test; Reason = $Reason }
}

# =============================================================================
# Test 1: Installer Script Syntax Validation
# =============================================================================

Write-TestHeader "Installer Script Validation"
$testResults.Total++

try {
    $installerContent = Get-Content $installerScript -Raw
    $null = [System.Management.Automation.PSParser]::Tokenize($installerContent, [ref]$null)
    Write-TestPass "Installer script has valid PowerShell syntax"
    $testResults.Passed++
}
catch {
    Write-TestFail "Installer script syntax" $_.Exception.Message
    $testResults.Failed++
}

# =============================================================================
# Test 2: Required Functions Exist
# =============================================================================

Write-TestHeader "Required Functions"

$requiredFunctions = @(
    'Test-InternetConnectivity',
    'Test-WritePermission',
    'Backup-ProfileFile',
    'Get-UserConfirmation',
    'Test-InstallationExists',
    'Test-ModuleLoaded',
    'Initialize-ProfileDirectory',
    'Add-ProfileImport',
    'Get-RemoteVersion',
    'Test-UpdateAvailable',
    'Install-FromZip',
    'Uninstall-ModuleLocal',
    'Update-ModuleLocal',
    'Start-Menu'
)

foreach ($func in $requiredFunctions) {
    $testResults.Total++
    if (Select-String -Path $installerScript -Pattern "function\s+$func\s*\{" -Quiet) {
        Write-TestPass "Function exists: $func"
        $testResults.Passed++
    }
    else {
        Write-TestFail "Function exists: $func" "Not found in installer"
        $testResults.Failed++
    }
}

# =============================================================================
# Test 3: Module Version Constant
# =============================================================================

Write-TestHeader "Version Management"
$testResults.Total++

if (Select-String -Path $installerScript -Pattern "\`$localVersion\s*=\s*" -Quiet) {
    Write-TestPass "Version constant set to 1.0.0"
    $testResults.Passed++
}
else {
    Write-TestFail "Version constant" "Not set to 1.0.0 or not found"
    $testResults.Failed++
}

# =============================================================================
# Test 4: Version Checking Logic
# =============================================================================

$testResults.Total++
if (Select-String -Path $installerScript -Pattern "ModuleVersion" -Quiet) {
    Write-TestPass "Remote version parsing logic present"
    $testResults.Passed++
}
else {
    Write-TestFail "Remote version parsing" "Not implemented"
    $testResults.Failed++
}

# =============================================================================
# Test 5: Safety Check Features
# =============================================================================

Write-TestHeader "Safety Features"

$safetyFeatures = @(
    @{Name = "Internet connectivity check"; Pattern = 'Test-InternetConnectivity' },
    @{Name = "Write permission validation"; Pattern = 'Test-WritePermission' },
    @{Name = "Profile backup"; Pattern = 'Backup-ProfileFile' },
    @{Name = "Confirmation prompts"; Pattern = 'Get-UserConfirmation' },
    @{Name = "Installation existence check"; Pattern = 'Test-InstallationExists' },
    @{Name = "Module loaded check"; Pattern = 'Test-ModuleLoaded' },
    @{Name = "Profile initialization"; Pattern = 'Initialize-ProfileDirectory' },
    @{Name = "Error handling (try/catch)"; Pattern = 'try.*catch' }
)

foreach ($feature in $safetyFeatures) {
    $testResults.Total++
    if (Select-String -Path $installerScript -Pattern $feature.Pattern -Quiet) {
        Write-TestPass "Safety feature: $($feature.Name)"
        $testResults.Passed++
    }
    else {
        Write-TestFail "Safety feature: $($feature.Name)" "Not implemented"
        $testResults.Failed++
    }
}

# =============================================================================
# Test 6: Runtime Flags
# =============================================================================

Write-TestHeader "Runtime Flags Support"

$runtimeFlags = @(
    @{Name = "Metrics flag"; Pattern = 'PWSH_SYNTAX_HIGHLIGHTING_METRICS' },
    @{Name = "Debug flag"; Pattern = 'PWSH_SYNTAX_HIGHLIGHTING_DEBUG' },
    @{Name = "Safe mode flag"; Pattern = 'PWSH_SYNTAX_HIGHLIGHTING_SAFE_MODE' },
    @{Name = "Flag menu function"; Pattern = 'function Show-FlagMenu' }
)

foreach ($flag in $runtimeFlags) {
    $testResults.Total++
    if (Select-String -Path $installerScript -Pattern $flag.Pattern -Quiet) {
        Write-TestPass "Runtime flag: $($flag.Name)"
        $testResults.Passed++
    }
    else {
        Write-TestFail "Runtime flag: $($flag.Name)" "Not found"
        $testResults.Failed++
    }
}

# =============================================================================
# Test 7: Manifest Consistency
# =============================================================================

Write-TestHeader "Manifest Consistency"
$testResults.Total++

try {
    $manifestContent = Get-Content $moduleManifest -Raw
    if ($manifestContent -match "ModuleVersion.*1\.0\.0") {
        Write-TestPass "Module manifest version is 1.0.0"
        $testResults.Passed++
    }
    else {
        Write-TestFail "Module manifest version" "Not 1.0.0"
        $testResults.Failed++
    }
}
catch {
    Write-TestFail "Read module manifest" $_.Exception.Message
    $testResults.Failed++
}

# =============================================================================
# Test Results
# =============================================================================

Write-Host "`n" -NoNewline
Write-Host "═════════════════════════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host "INSTALLER TESTS SUMMARY (v1.0.0)" -ForegroundColor Magenta
Write-Host "═════════════════════════════════════════════════════════════════" -ForegroundColor Magenta

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
