<#
.SYNOPSIS
    Installer for pwsh-syntax-highlighting module.
.DESCRIPTION
    Downloads and installs pwsh-syntax-highlighting from GitHub to the current user's module path.
    Supports interactive menu with runtime flag configuration and safety checks.
.PARAMETER Install
    If specified, install the module without prompting.
.PARAMETER Update
    If specified, update an existing installation without prompting.
.PARAMETER Uninstall
    If specified, uninstall the module without prompting.
.PARAMETER NoProfileUpdate
    If specified, skip adding autoload line to PowerShell profile.
.PARAMETER RepoOwner
    GitHub repository owner; defaults to 'ruZeph'.
.PARAMETER RepoName
    GitHub repository name; defaults to 'pwsh-syntax-highlighting'.
.PARAMETER Branch
    Git branch to download; defaults to 'main'.
#>
[CmdletBinding()]
param(
    [switch]$Install,
    [switch]$Update,
    [switch]$Uninstall,
    [switch]$NoProfileUpdate,
    [ValidateNotNullOrEmpty()]
    [string]$RepoOwner = 'ruZeph',
    [ValidateNotNullOrEmpty()]
    [string]$RepoName = 'pwsh-syntax-highlighting',
    [ValidateNotNullOrEmpty()]
    [string]$Branch = 'main'
)

$ErrorActionPreference = 'Stop'
$moduleName = 'pwsh-syntax-highlighting'
$profileImportLine = "try { Import-Module '$moduleName' } catch { }"
$moduleRoot = Join-Path (Join-Path $HOME 'Documents\PowerShell\Modules') $moduleName
$profileBackupExt = '.pwsh-syntax-highlighting.backup'

# Runtime flag configuration state
$script:EnableMetrics = $false
$script:EnableDebug = $false
$script:SafeMode = $false

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Good {
    param([string]$Message)
    Write-Host "[OK]   $Message" -ForegroundColor Green
}

function Write-WarnMsg {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-ErrorMsg {
    param([string]$Message)
    Write-Host "[ERR]  $Message" -ForegroundColor Red
}

function Test-InternetConnectivity {
    Write-Info "Checking internet connectivity..."
    try {
        $null = [System.Net.Http.HttpClient]::new().GetAsync('https://github.com', [System.Threading.CancellationToken]::new(1000)).Result
        Write-Good "Internet connection available"
        return $true
    }
    catch {
        Write-ErrorMsg "Cannot reach GitHub. Check your internet connection."
        return $false
    }
}

function Test-WritePermission {
    param([string]$Path)
    
    $testFile = Join-Path $Path '.pwsh-syntax-highlighting-write-test'
    try {
        "test" | Out-File -LiteralPath $testFile -Force -ErrorAction Stop
        Remove-Item -LiteralPath $testFile -Force -ErrorAction SilentlyContinue
        return $true
    }
    catch {
        Write-ErrorMsg "No write permission: $Path"
        return $false
    }
}

function Backup-ProfileFile {
    param([string]$ProfilePath)
    
    if (-not (Test-Path -LiteralPath $ProfilePath)) {
        return
    }

    $backupPath = "$ProfilePath$profileBackupExt"
    try {
        Copy-Item -LiteralPath $ProfilePath -Destination $backupPath -Force -ErrorAction Stop
        Write-Good "Profile backed up to: $backupPath"
        return $backupPath
    }
    catch {
        Write-WarnMsg "Could not backup profile: $_"
        return $null
    }
}

function Get-UserConfirmation {
    param(
        [string]$Title,
        [string]$Message,
        [string]$YesDescription = 'Continue',
        [string]$NoDescription = 'Cancel'
    )
    
    Write-Host ""
    Write-Host "⚠️  $Title" -ForegroundColor Yellow
    Write-Host "   $Message"
    Write-Host ""
    Write-Host "   [Y] $YesDescription"
    Write-Host "   [N] $NoDescription"
    Write-Host ""
    
    $choice = Read-Host "Proceed?"
    return $choice -match '^(y|yes)$'
}

function Test-InstallationExists {
    param([switch]$Verbose)
    
    if (Test-Path -LiteralPath $moduleRoot) {
        if ($Verbose) {
            $versionInfo = try { (Get-Module -Name $moduleName -ErrorAction Stop).Version } catch { 'unknown' }
            Write-WarnMsg "Existing installation found at: $moduleRoot (version: $versionInfo)"
        }
        return $true
    }
    return $false
}

function Test-ModuleLoaded {
    return $null -ne (Get-Module -Name $moduleName -ErrorAction SilentlyContinue)
}

function Ensure-ProfileDirectory {
    param([string]$ProfilePath)
    
    $profileDir = Split-Path -Parent $profilePath
    if (-not (Test-Path -LiteralPath $profileDir)) {
        try {
            $null = New-Item -Path $profileDir -ItemType Directory -Force -ErrorAction Stop
            Write-Good "Created profile directory: $profileDir"
        }
        catch {
            Write-ErrorMsg "Failed to create profile directory: $_"
            throw
        }
    }

    if (-not (Test-Path -LiteralPath $profilePath)) {
        try {
            $null = New-Item -Path $profilePath -ItemType File -Force -ErrorAction Stop
            Write-Good "Created profile file: $profilePath"
        }
        catch {
            Write-ErrorMsg "Failed to create profile file: $_"
            throw
        }
    }
}

function Add-ProfileImport {
    if ($NoProfileUpdate) {
        Write-Info 'Skipping profile update due to -NoProfileUpdate.'
        return
    }

    $profilePath = $PROFILE.CurrentUserCurrentHost
    
    # Ensure directory and file exist
    Ensure-ProfileDirectory -ProfilePath $profilePath

    # Check write permission
    if (-not (Test-WritePermission -Path (Split-Path -Parent $profilePath))) {
        Write-ErrorMsg "Cannot write to profile directory. Check permissions."
        throw "Profile write permission denied"
    }

    # Backup before modification
    $backupPath = Backup-ProfileFile -ProfilePath $profilePath

    try {
        $profileContent = Get-Content -LiteralPath $profilePath -Raw -ErrorAction SilentlyContinue
        if ([string]::IsNullOrEmpty($profileContent)) {
            $profileContent = ''
        }

        if ($profileContent -notmatch [regex]::Escape($profileImportLine)) {
            Add-Content -LiteralPath $profilePath -Value "`n$profileImportLine" -ErrorAction Stop
            Write-Good "Added module autoload to profile: $profilePath"
        }
        else {
            Write-Info 'Profile already contains autoload line.'
        }

        # Add runtime flags if any are enabled
        if ($script:EnableMetrics -or $script:EnableDebug -or $script:SafeMode) {
            Add-RuntimeFlags -ProfilePath $profilePath
        }
    }
    catch {
        Write-ErrorMsg "Failed to update profile: $_"
        if ($backupPath) {
            Write-Info "Restoring profile from backup..."
            Copy-Item -LiteralPath $backupPath -Destination $profilePath -Force -ErrorAction SilentlyContinue
        }
        throw
    }
}

function Add-RuntimeFlags {
    param([string]$ProfilePath)

    $flagLines = @()
    if ($script:EnableMetrics) {
        $flagLines += '[Environment]::SetEnvironmentVariable("PWSH_SYNTAX_HIGHLIGHTING_METRICS", "1", "User")'
    }
    if ($script:EnableDebug) {
        $flagLines += '[Environment]::SetEnvironmentVariable("PWSH_SYNTAX_HIGHLIGHTING_DEBUG", "1", "User")'
    }
    if ($script:SafeMode) {
        $flagLines += '[Environment]::SetEnvironmentVariable("PWSH_SYNTAX_HIGHLIGHTING_SAFE_MODE", "1", "User")'
    }

    if ($flagLines.Count -gt 0) {
        $flagContent = "`n# pwsh-syntax-highlighting runtime flags`n" + ($flagLines -join "`n")
        Add-Content -LiteralPath $ProfilePath -Value $flagContent -ErrorAction Stop
        Write-Good "Runtime flags configured:"
        if ($script:EnableMetrics) { Write-Host "  [X] Metrics collection enabled" -ForegroundColor Green }
        if ($script:EnableDebug) { Write-Host "  [X] Debug tracing enabled" -ForegroundColor Green }
        if ($script:SafeMode) { Write-Host "  [X] Safe mode enabled" -ForegroundColor Green }
    }
}

function Show-FlagMenu {
    while ($true) {
        Write-Host ''
        Write-Host 'Configure Runtime Flags' -ForegroundColor Cyan
        Write-Host "1) Metrics collection      $($script:EnableMetrics ? '[X]' : '[ ]')"
        Write-Host "2) Debug tracing           $($script:EnableDebug ? '[X]' : '[ ]')"
        Write-Host "3) Safe mode               $($script:SafeMode ? '[X]' : '[ ]')"
        Write-Host 'B) Back to main menu'
        Write-Host ''

        $choice = Read-Host 'Select option'
        switch -Regex ($choice) {
            '^1$' {
                $script:EnableMetrics = -not $script:EnableMetrics
                Write-Good "Metrics collection $(if ($script:EnableMetrics) { 'enabled' } else { 'disabled' })"
                break
            }
            '^2$' {
                $script:EnableDebug = -not $script:EnableDebug
                Write-Good "Debug tracing $(if ($script:EnableDebug) { 'enabled' } else { 'disabled' })"
                break
            }
            '^3$' {
                $script:SafeMode = -not $script:SafeMode
                Write-Good "Safe mode $(if ($script:SafeMode) { 'enabled' } else { 'disabled' })"
                break
            }
            '^(b|back)$' {
                return
            }
            default {
                Write-WarnMsg 'Invalid selection.'
                break
            }
        }
    }
}

function Remove-ProfileImport {
    $profilePath = $PROFILE.CurrentUserCurrentHost
    if (-not (Test-Path -LiteralPath $profilePath)) {
        return
    }

    $backupPath = Backup-ProfileFile -ProfilePath $profilePath

    try {
        [string[]]$lines = @(Get-Content -LiteralPath $profilePath -ErrorAction Stop)
        if ($null -eq $lines -or $lines.Count -eq 0) {
            return
        }

        $escapedModuleName = [regex]::Escape($moduleName)
        $pattern = "Import-Module\s+['\`"]?$escapedModuleName['\`"]?"
        [string[]]$filtered = @($lines | Where-Object { $_ -notmatch $pattern })

        # Also remove runtime flag environment variable setters
        $filtered = @($filtered | Where-Object { 
                $_ -notmatch 'PWSH_SYNTAX_HIGHLIGHTING' -and
                $_ -notmatch '# pwsh-syntax-highlighting runtime flags'
            })

        if ($filtered.Count -gt 0) {
            Set-Content -LiteralPath $profilePath -Value $filtered -ErrorAction Stop
        }

        Write-Good "Removed module autoload entries from profile"
    }
    catch {
        Write-ErrorMsg "Failed to update profile: $_"
        if ($backupPath) {
            Write-Info "Restoring profile from backup..."
            Copy-Item -LiteralPath $backupPath -Destination $profilePath -Force -ErrorAction SilentlyContinue
        }
        throw
    }
}

function Install-FromZip {
    # Safety checks
    if (-not (Test-InternetConnectivity)) {
        throw "No internet connectivity"
    }

    if (Test-ModuleLoaded) {
        Write-WarnMsg "Module is currently loaded in this session"
        if (-not (Get-UserConfirmation -Title "Module Loaded" -Message "Continue with installation? It will be reloaded." -YesDescription "Continue" -NoDescription "Cancel")) {
            Write-Info "Installation cancelled"
            return
        }
    }

    if (Test-InstallationExists -Verbose) {
        if (-not (Get-UserConfirmation -Title "Overwrite Existing Installation" -Message "An installation already exists. Overwrite it?" -YesDescription "Overwrite" -NoDescription "Cancel")) {
            Write-Info "Installation cancelled"
            return
        }
    }

    $zipUrl = "https://github.com/$RepoOwner/$RepoName/archive/refs/heads/$Branch.zip"
    $zipPath = Join-Path $env:TEMP "$RepoName-$Branch.zip"
    $extractBase = Join-Path $env:TEMP "$RepoName-$Branch"
    $expandedRoot = Join-Path $extractBase "$RepoName-$Branch"

    try {
        Write-Info "Downloading: $zipUrl"
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -ErrorAction Stop

        if (Test-Path -LiteralPath $extractBase) {
            Remove-Item -LiteralPath $extractBase -Recurse -Force -ErrorAction SilentlyContinue
        }

        Expand-Archive -Path $zipPath -DestinationPath $extractBase -Force -ErrorAction Stop

        if (-not (Test-Path -LiteralPath $expandedRoot)) {
            throw "Expanded folder not found: $expandedRoot"
        }

        if (-not (Test-Path -LiteralPath $moduleRoot)) {
            $null = New-Item -Path $moduleRoot -ItemType Directory -Force -ErrorAction Stop
        }

        # Check write permission before clearing
        if (-not (Test-WritePermission -Path $moduleRoot)) {
            throw "No write permission to module directory"
        }

        Get-ChildItem -LiteralPath $moduleRoot -Force -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

        $null = Copy-Item -Path (Join-Path $expandedRoot '*') -Destination $moduleRoot -Recurse -Force -ErrorAction Stop

        if (Test-ModuleLoaded) {
            Remove-Module $moduleName -ErrorAction SilentlyContinue
        }
        Import-Module $moduleName -Force -ErrorAction Stop

        Add-ProfileImport

        Write-Good "Successfully installed $moduleName to: $moduleRoot"
        Write-Good 'Module imported for current session.'
    }
    finally {
        # Clean up temp files
        Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $extractBase -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Remove-RuntimeEnvironmentVariables {
    Write-Info "Cleaning up runtime environment variables..."
    try {
        [Environment]::SetEnvironmentVariable('PWSH_SYNTAX_HIGHLIGHTING_METRICS', $null, 'User')
        [Environment]::SetEnvironmentVariable('PWSH_SYNTAX_HIGHLIGHTING_DEBUG', $null, 'User')
        [Environment]::SetEnvironmentVariable('PWSH_SYNTAX_HIGHLIGHTING_SAFE_MODE', $null, 'User')
        [Environment]::SetEnvironmentVariable('PWSH_SYNTAX_HIGHLIGHTING_MAX_LENGTH', $null, 'User')
        [Environment]::SetEnvironmentVariable('PWSH_SYNTAX_HIGHLIGHTING_MAX_COMMAND_LENGTH', $null, 'User')
        [Environment]::SetEnvironmentVariable('PWSH_SYNTAX_HIGHLIGHTING_RENDER_ERROR_BUDGET', $null, 'User')
        Write-Good "Cleaned up environment variables"
    }
    catch {
        Write-WarnMsg "Could not clean some environment variables: $_"
    }
}

function Uninstall-ModuleLocal {
    if (Test-ModuleLoaded) {
        Write-WarnMsg "Module is currently loaded in this session"
    }

    if (-not (Test-InstallationExists)) {
        Write-WarnMsg "No installation found at: $moduleRoot"
        return
    }

    if (-not (Get-UserConfirmation -Title "Confirm Uninstall" -Message "Remove $moduleName and all related configurations?" -YesDescription "Uninstall" -NoDescription "Cancel")) {
        Write-Info "Uninstall cancelled"
        return
    }

    try {
        if (Test-ModuleLoaded) {
            Remove-Module $moduleName -ErrorAction SilentlyContinue
        }

        if (Test-Path -LiteralPath $moduleRoot) {
            Remove-Item -LiteralPath $moduleRoot -Recurse -Force -ErrorAction Stop
            Write-Good "Removed module directory: $moduleRoot"
        }

        Remove-ProfileImport
        Remove-RuntimeEnvironmentVariables
        Write-Good "Successfully uninstalled $moduleName"
    }
    catch {
        Write-ErrorMsg "Uninstall failed: $_"
        throw
    }
}

function Update-ModuleLocal {
    if (-not (Test-InstallationExists -Verbose)) {
        Write-WarnMsg "No existing installation found"
        if (-not (Get-UserConfirmation -Title "Installation Not Found" -Message "Perform new installation instead?" -YesDescription "Install" -NoDescription "Cancel")) {
            Write-Info "Update cancelled"
            return
        }
        Install-FromZip
        return
    }

    Write-Info "Updating module..."
    Install-FromZip
}

function Start-Menu {
    while ($true) {
        Write-Host ''
        Write-Host 'pwsh-syntax-highlighting installer' -ForegroundColor Magenta
        Write-Host '1) Install to current user + autoload in profile'
        Write-Host '2) Update existing installation'
        Write-Host '3) Configure runtime flags'
        Write-Host '4) Uninstall from current user + remove profile autoload'
        Write-Host 'Q) Quit'
        Write-Host ''

        $choice = Read-Host 'Select an option'
        switch -Regex ($choice) {
            '^(1|i|install)$' {
                Install-FromZip
                return
            }
            '^(2|u|update)$' {
                Update-ModuleLocal
                return
            }
            '^(3|f|flags)$' {
                Show-FlagMenu
            }
            '^(4|uninstall)$' {
                Uninstall-ModuleLocal
                return
            }
            '^(q|quit)$' {
                Write-Info 'No changes made.'
                return
            }
            default {
                Write-WarnMsg 'Invalid selection. No changes made.'
            }
        }
    }
}

if ($Install -and ($Uninstall -or $Update)) {
    throw 'Use only one of -Install, -Update, or -Uninstall.'
}

if ($Uninstall -and $Update) {
    throw 'Use only one of -Install, -Update, or -Uninstall.'
}

if ($Install) {
    Install-FromZip
}
elseif ($Update) {
    Update-ModuleLocal
}
elseif ($Uninstall) {
    Uninstall-ModuleLocal
}
else {
    Start-Menu
}
