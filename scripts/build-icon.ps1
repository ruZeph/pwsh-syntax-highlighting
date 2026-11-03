<#
.SYNOPSIS
    Regenerates assets/icon.png (the module/gallery icon referenced by psd1 IconUri).
.DESCRIPTION
    Draws the icon with GDI+ so it is reproducible instead of being a binary blob nobody
    can edit. Run after changing the geometry below, then commit the regenerated PNG.
.EXAMPLE
    pwsh -File scripts/build-icon.ps1
#>
[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'assets/icon.png'),
    [int]$Size = 128
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

function Get-RoundedRectanglePath {
    param([single]$X, [single]$Y, [single]$Width, [single]$Height, [single]$Radius)

    $diameter = $Radius * 2
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc($X, $Y, $diameter, $diameter, 180, 90)
    $path.AddArc(($X + $Width - $diameter), $Y, $diameter, $diameter, 270, 90)
    $path.AddArc(($X + $Width - $diameter), ($Y + $Height - $diameter), $diameter, $diameter, 0, 90)
    $path.AddArc($X, ($Y + $Height - $diameter), $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    return $path
}

$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

$bitmap = New-Object System.Drawing.Bitmap($Size, $Size)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.Clear([System.Drawing.Color]::Transparent)

try {
    # Rounded dark panel with a hairline rim
    $inset = 3
    $panel = Get-RoundedRectanglePath $inset $inset ($Size - 2 * $inset) ($Size - 2 * $inset) 20
    $fill = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Point(0, 0)),
        (New-Object System.Drawing.Point(0, $Size)),
        [System.Drawing.Color]::FromArgb(255, 33, 36, 42),
        [System.Drawing.Color]::FromArgb(255, 16, 17, 20))
    $graphics.FillPath($fill, $panel)
    $rim = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 62, 68, 78), 2)
    $graphics.DrawPath($rim, $panel)

    # Red / amber / green "traffic lights"
    foreach ($dot in @(
            @{ X = 24; Color = [System.Drawing.Color]::FromArgb(255, 255, 95, 86) },
            @{ X = 34; Color = [System.Drawing.Color]::FromArgb(255, 255, 189, 46) },
            @{ X = 44; Color = [System.Drawing.Color]::FromArgb(255, 39, 201, 63) })) {
        $brush = New-Object System.Drawing.SolidBrush($dot.Color)
        $graphics.FillEllipse($brush, $dot.X, 17, 7, 7)
    }

    # Prompt mark: a single bold ">" from a real monospace font, optically centred.
    # One glyph instead of the ">_" pair on purpose - at 16-32px the pair reads as
    # two disconnected marks, and a lone chevron is unambiguous at every size.
    $font = New-Object System.Drawing.Font('Consolas', 76, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $format = New-Object System.Drawing.StringFormat
    $format.Alignment = [System.Drawing.StringAlignment]::Center
    $format.LineAlignment = [System.Drawing.StringAlignment]::Center
    $format.FormatFlags = [System.Drawing.StringFormatFlags]::NoClip

    $glyphBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 63, 185, 80))
    $glyphRect = New-Object System.Drawing.RectangleF(0, 10, $Size, $Size)
    $graphics.DrawString('>', $font, $glyphBrush, $glyphRect, $format)
}
finally {
    $graphics.Dispose()
}

$bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
$bitmap.Dispose()
Write-Output "Wrote $OutputPath ($Size x $Size)"
