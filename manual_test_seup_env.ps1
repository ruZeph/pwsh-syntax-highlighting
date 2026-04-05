Set-Location "D:\MediaNData\Open Source Work\pwsh-syntax-highlighting"
Remove-Module syntax-highlighting -ErrorAction Ignore

$printable = [char[]](0x20..0x7e + 0xa0..0xff)
foreach ($k in $printable) { Set-PSReadLineKeyHandler -Key $k -Function SelfInsert -ErrorAction SilentlyContinue }
Set-PSReadLineKeyHandler -Key Tab -Function Complete -ErrorAction SilentlyContinue
Set-PSReadLineKeyHandler -Key UpArrow -Function PreviousHistory -ErrorAction SilentlyContinue
Set-PSReadLineKeyHandler -Key DownArrow -Function NextHistory -ErrorAction SilentlyContinue
Set-PSReadLineKeyHandler -Key RightArrow -Function ForwardChar -ErrorAction SilentlyContinue
Set-PSReadLineKeyHandler -Key LeftArrow -Function BackwardChar -ErrorAction SilentlyContinue
Set-PSReadLineKeyHandler -Key Backspace -Function BackwardDeleteChar -ErrorAction SilentlyContinue
Set-PSReadLineKeyHandler -Key Delete -Function DeleteChar -ErrorAction SilentlyContinue

$env:PWSH_SYNTAX_HIGHLIGHTING_DEBUG='1'
$env:PWSH_SYNTAX_HIGHLIGHTING_METRICS='1'
Import-Module ".\syntax-highlighting.psd1" -Force