$global:lastRender = Get-Date

$script:RenderAction = {
    if (((Get-Date) - $global:lastRender).TotalMilliseconds -le 20) {
        return
    }

    $ast = $null; $tokens = $null; $errors = $null; $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$ast, [ref]$tokens, [ref]$errors, [ref]$cursor)
    if (-not $tokens -or $tokens.Count -eq 0 -or -not $tokens[0]) {
        return
    }

    $token = $tokens[0]
    if ([string]::IsNullOrEmpty($token.Text.Trim()) -or $token.Text -match "\[|\]") {
        return
    }

    [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition(0)
    $cursorPosX = $host.UI.RawUI.CursorPosition.X
    $cursorPosY = $host.UI.RawUI.CursorPosition.Y
    [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor)

    $tokenLength = ($token.Extent.EndOffset - $token.Extent.StartOffset)
    if ($tokenLength -le 0) {
        return
    }

    $color = "Red"
    if (Get-Command $token.Text -ErrorAction Ignore) {
        $color = "Green"
    }

    $sX = ($cursorPosX + $token.Extent.StartOffset)
    $Y = $cursorPosY
    $eX = ($sX + $tokenLength)
    $nextLine = $false

    $painted = 0
    $bufSize = $host.UI.RawUI.BufferSize.Width
    while ($painted -ne $tokenLength) {
        $scanXEnd = $eX
        if ($eX -gt $bufSize) {
            $scanXEnd = $bufSize
            $eX = $eX - $bufSize
            $nextLine = $true
        }

        $finalRec = New-Object System.Management.Automation.Host.Rectangle($sX, $Y, ($scanXEnd - 1), $Y)
        $finalBuf = $host.UI.RawUI.GetBufferContents($finalRec)
        for ($xPosition = 0; $xPosition -lt ($scanXEnd - $sX); $xPosition++) {
            $bufferItem = $finalBuf.GetValue(0, $xPosition)
            $bufferItem.ForegroundColor = $color
            $finalBuf.SetValue($bufferItem, 0, $xPosition)
            $painted++
        }

        $coords = New-Object System.Management.Automation.Host.Coordinates $sX, $Y
        $host.UI.RawUI.SetBufferContents($coords, $finalBuf)
        if ($nextLine) {
            $sX = 0
            $Y++
            $nextLine = $false
        }
    }

    $global:lastRender = Get-Date
}.GetNewClosure()

$printableChars = [char[]](0x20..0x7e + 0xa0..0xff)
$functionKeyMap = @{
    UpArrow   = "PreviousHistory"
    DownArrow = "NextHistory"
    RightArrow = "ForwardChar"
    LeftArrow = "BackwardChar"
    Backspace = "BackwardDeleteChar"
    Delete = "DeleteChar"
}

$ExecutionContext.SessionState.Module.OnRemove = {
    foreach ($key in $printableChars) {
        Set-PSReadLineKeyHandler -Key $key -Function SelfInsert -ErrorAction SilentlyContinue
    }

    Set-PSReadLineKeyHandler -Key Tab -Function Complete -ErrorAction SilentlyContinue
    foreach ($entry in $functionKeyMap.GetEnumerator()) {
        Set-PSReadLineKeyHandler -Key $entry.Key -Function $entry.Value -ErrorAction SilentlyContinue
    }
}

$renderAction = $script:RenderAction
$printableChars + "Tab" | ForEach-Object {
    Set-PSReadLineKeyHandler -Key $_ `
        -BriefDescription ValidatePrograms `
        -LongDescription "Validate typed program's existence in path variable" `
        -ScriptBlock {
            param($key, $arg)

            if ($key.Key -ne [System.ConsoleKey]::Tab) {
                [Microsoft.PowerShell.PSConsoleReadLine]::Insert($key.KeyChar)
            }
            else {
                [Microsoft.PowerShell.PSConsoleReadLine]::TabCompleteNext($key)
            }

            & $renderAction
        }.GetNewClosure()
}

foreach ($entry in $functionKeyMap.GetEnumerator()) {
    $methodName = $entry.Value
    $method = [Microsoft.PowerShell.PSConsoleReadLine].GetMethod($methodName, [type[]]@([System.ConsoleKeyInfo], [object]))
    if (-not $method) {
        throw "Could not find PSReadLine method '$methodName' for key '$($entry.Key)'."
    }

    Set-PSReadLineKeyHandler -Key $entry.Key `
        -BriefDescription ValidatePrograms `
        -LongDescription "Validate typed program's existence in path variable" `
        -ScriptBlock {
            param($key, $arg)
            $method.Invoke($null, @($key, $arg)) | Out-Null
            & $renderAction
        }.GetNewClosure()
}