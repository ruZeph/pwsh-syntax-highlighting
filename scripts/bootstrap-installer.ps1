<#
.SYNOPSIS
    Bootstrap installer for pwsh-syntax-highlighting module.
.DESCRIPTION
    Downloads and installs pwsh-syntax-highlighting from GitHub to the current user's module path.
    Supports interactive menu with runtime flag configuration.
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

function Add-ProfileImport {
    if ($NoProfileUpdate) {
        Write-Info 'Skipping profile update due to -NoProfileUpdate.'
        return
    }

    $profilePath = $PROFILE.CurrentUserCurrentHost
    $profileDir = Split-Path -Parent $profilePath

    if (-not (Test-Path -LiteralPath $profileDir)) {
        New-Item -Path $profileDir -ItemType Directory -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $profilePath)) {
        New-Item -Path $profilePath -ItemType File -Force | Out-Null
    }

    try {
        $profileContent = Get-Content -LiteralPath $profilePath -Raw -ErrorAction Stop
    }
    catch {
        $profileContent = ''
    }

    if ($profileContent -notmatch [regex]::Escape($profileImportLine)) {
        Add-Content -LiteralPath $profilePath -Value "`n$profileImportLine"
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
        Add-Content -LiteralPath $ProfilePath -Value $flagContent
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

    try {
        [string[]]$lines = @(Get-Content -LiteralPath $profilePath -ErrorAction Stop)
    }
    catch {
        return
    }
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
        Set-Content -LiteralPath $profilePath -Value $filtered
    }

    Write-Good "Removed module autoload entries from profile: $profilePath"
}

function Install-FromZip {
    $zipUrl = "https://github.com/$RepoOwner/$RepoName/archive/refs/heads/$Branch.zip"
    $zipPath = Join-Path $env:TEMP "$RepoName-$Branch.zip"
    $extractBase = Join-Path $env:TEMP "$RepoName-$Branch"
    $expandedRoot = Join-Path $extractBase "$RepoName-$Branch"

    Write-Info "Downloading: $zipUrl"
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath

    if (Test-Path -LiteralPath $extractBase) {
        Remove-Item -LiteralPath $extractBase -Recurse -Force
    }

    Expand-Archive -Path $zipPath -DestinationPath $extractBase -Force

    if (-not (Test-Path -LiteralPath $expandedRoot)) {
        throw "Expanded folder not found: $expandedRoot"
    }

    if (-not (Test-Path -LiteralPath $moduleRoot)) {
        New-Item -Path $moduleRoot -ItemType Directory -Force | Out-Null
    }

    Get-ChildItem -LiteralPath $moduleRoot -Force |
    Remove-Item -Recurse -Force

    $null = Copy-Item -Path (Join-Path $expandedRoot '*') -Destination $moduleRoot -Recurse -Force

    if (Get-Module -Name $moduleName) {
        Remove-Module $moduleName
    }
    Import-Module $moduleName -Force

    Add-ProfileImport

    Write-Good "Installed $moduleName to: $moduleRoot"
    Write-Good 'Module imported for current session.'
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
        Write-WarnMsg "Could not clean some environment variables: $($_)"
    }
}

function Uninstall-ModuleLocal {
    if (Get-Module -Name $moduleName) {
        Remove-Module $moduleName
    }

    if (Test-Path -LiteralPath $moduleRoot) {
        Remove-Item -LiteralPath $moduleRoot -Recurse -Force
        Write-Good "Removed module directory: $moduleRoot"
    }
    else {
        Write-Info "Module directory not found: $moduleRoot"
    }

    Remove-ProfileImport
    Remove-RuntimeEnvironmentVariables
    Write-Good "Uninstalled $moduleName from current user scope."
}

function Update-ModuleLocal {
    if (Test-Path -LiteralPath $moduleRoot) {
        $currentVersion = try { (Get-Module -Name $moduleName -ErrorAction Stop).Version } catch { 'unknown' }
        Write-Info "Current version: $currentVersion"
    }

    Install-FromZip

    $newVersion = try { (Get-Module -Name $moduleName -ErrorAction Stop).Version } catch { 'unknown' }
    Write-Good "Updated to version: $newVersion"
}

function Start-Menu {
    while ($true) {
        Write-Host ''
        Write-Host 'pwsh-syntax-highlighting bootstrap' -ForegroundColor Magenta
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
