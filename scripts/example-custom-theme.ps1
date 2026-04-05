<#
.SYNOPSIS
    Example: Custom color theme for pwsh-syntax-highlighting
.DESCRIPTION
    Add this to your PowerShell profile to customize syntax highlighting colors.
    Edit the $colors hashtable to match your preferred color scheme.
.EXAMPLE
    . $PROFILE -ErrorAction SilentlyContinue
    # Then add this script's contents to your profile after the Import-Module line
#>

# Customize syntax highlighting colors
# Add this code AFTER the 'Import-Module pwsh-syntax-highlighting' line in your profile

if (Get-Module pwsh-syntax-highlighting) {
    $module = Get-Module pwsh-syntax-highlighting
    $colors = @{
        ValidCommand   = [System.ConsoleColor]::Green      # Change to preferred color
        InvalidCommand = [System.ConsoleColor]::Red        # Change to preferred color
    }

    # Apply custom colors
    & $module {
        param($c)
        $script:Styles = $c
    } $colors

    Write-Host "[pwsh-syntax-highlighting] Loaded custom theme" -ForegroundColor Cyan
}
else {
    Write-Warning "pwsh-syntax-highlighting module not loaded; cannot apply custom theme."
}

# Available colors:
# Black, DarkBlue, DarkGreen, DarkCyan, DarkRed, DarkMagenta, DarkYellow,
# Gray, DarkGray, Blue, Green, Cyan, Red, Magenta, Yellow, White
